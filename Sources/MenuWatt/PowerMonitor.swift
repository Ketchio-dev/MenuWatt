import AppKit
import SwiftUI
import MenuWattCore
import MenuWattSystem

@MainActor
final class PowerMonitor: ObservableObject {
    struct Configuration: Sendable {
        let refreshInterval: TimeInterval
        let animationMinimumInterval: TimeInterval

        static let live = Configuration(
            refreshInterval: 1.0,
            animationMinimumInterval: 0.02
        )
    }

    @Published private(set) var snapshot = BatterySnapshot.unavailable
    @Published private(set) var systemSnapshot = SystemSnapshot.unavailable
    @Published private(set) var currentFrame = SpriteRenderer.image(for: .run1)

    private(set) var currentSpriteFrame = SpriteFrame.run1

    private var refreshLoopTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var animationLoopTask: Task<Void, Never>?
    private var frameIndex = 0
    private var refreshSequence: UInt64 = 0
    private var isRunning = false

    private let sampler: any MonitorSampling
    private let configuration: Configuration
    private let logger = MenuWattDiagnostics.monitoring

    init(
        sampler: any MonitorSampling = LiveMonitorSampler(),
        configuration: Configuration = .live
    ) {
        self.sampler = sampler
        self.configuration = configuration
        let initialFrame = BoochiPresentation.make(for: snapshot.state).fallbackFrame
        currentSpriteFrame = initialFrame
        currentFrame = SpriteRenderer.image(for: initialFrame)
    }

    func start() {
        isRunning = true
        logger.info("Power monitor started")

        if refreshLoopTask == nil {
            requestRefresh(resetAnimation: true)
            refreshLoopTask = Task { [weak self] in
                await self?.runRefreshLoop()
            }
        }

        if animationLoopTask == nil {
            animationLoopTask = Task { [weak self] in
                await self?.runAnimationLoop()
            }
        }
    }

    func stop() {
        isRunning = false
        refreshSequence &+= 1
        logger.info("Power monitor stopped")

        refreshLoopTask?.cancel()
        refreshLoopTask = nil

        refreshTask?.cancel()
        refreshTask = nil

        animationLoopTask?.cancel()
        animationLoopTask = nil
    }

    func refreshNow() {
        requestRefresh(resetAnimation: true)
    }

    private func runRefreshLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: nanoseconds(for: configuration.refreshInterval))
            guard !Task.isCancelled else { return }
            requestRefresh(resetAnimation: false)
        }
    }

    private func runAnimationLoop() async {
        while !Task.isCancelled {
            let interval = BoochiAnimationPolicy.interval(
                for: snapshot.state,
                cpuUsage: systemSnapshot.cpu.totalUsage,
                minimumInterval: configuration.animationMinimumInterval
            )
            try? await Task.sleep(nanoseconds: nanoseconds(for: interval))
            guard !Task.isCancelled else { return }
            advanceFrame()
        }
    }

    private func requestRefresh(resetAnimation: Bool) {
        guard isRunning else { return }

        refreshSequence &+= 1
        let sequence = refreshSequence

        refreshTask?.cancel()
        refreshTask = Task { [weak self, sampler] in
            let payload = await sampler.sample()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.applyIfCurrent(payload, resetAnimation: resetAnimation, sequence: sequence)
            }
        }
    }

    private func applyIfCurrent(_ payload: SamplePayload, resetAnimation: Bool, sequence: UInt64) {
        guard isRunning, sequence == refreshSequence else { return }
        apply(payload, resetAnimation: resetAnimation)
        refreshTask = nil
    }

    private func apply(_ payload: SamplePayload, resetAnimation: Bool) {
        let previousState = snapshot.state
        let previousBattery = snapshot
        let previousSystem = systemSnapshot
        let nextSnapshot = payload.battery

        snapshot = nextSnapshot
        systemSnapshot = payload.system
        logTransitions(fromBattery: previousBattery, toBattery: nextSnapshot, fromSystem: previousSystem, toSystem: payload.system)

        if resetAnimation || previousState != nextSnapshot.state {
            frameIndex = 0
        }

        updateCurrentFrame()
    }

    private func advanceFrame() {
        let presentation = BoochiPresentation.make(for: snapshot.state)
        let frames = presentation.animationFrames
        guard !frames.isEmpty else { return }

        frameIndex = (frameIndex + 1) % frames.count
        updateCurrentFrame()
    }

    private func updateCurrentFrame() {
        let presentation = BoochiPresentation.make(for: snapshot.state)
        let frames = presentation.animationFrames
        let safeIndex = frames.isEmpty ? 0 : frameIndex % frames.count
        let nextFrame = frames.isEmpty ? presentation.fallbackFrame : frames[safeIndex]

        currentSpriteFrame = nextFrame
        currentFrame = SpriteRenderer.image(for: nextFrame)
    }

    private func nanoseconds(for interval: TimeInterval) -> UInt64 {
        UInt64(max(interval, 0.001) * 1_000_000_000)
    }

    private func logTransitions(
        fromBattery previousBattery: BatterySnapshot,
        toBattery nextBattery: BatterySnapshot,
        fromSystem previousSystem: SystemSnapshot,
        toSystem nextSystem: SystemSnapshot
    ) {
        if previousBattery.state != nextBattery.state {
            logger.info("Battery state changed to \(String(describing: nextBattery.state), privacy: .public)")
        }

        logAvailabilityChange(component: "battery", wasAvailable: previousBattery.state != .unavailable, isAvailable: nextBattery.state != .unavailable)
        logAvailabilityChange(component: "cpu", wasAvailable: previousSystem.cpu.isAvailable, isAvailable: nextSystem.cpu.isAvailable)
        logAvailabilityChange(component: "memory", wasAvailable: previousSystem.memory.isAvailable, isAvailable: nextSystem.memory.isAvailable)
        logAvailabilityChange(component: "storage", wasAvailable: previousSystem.storage.isAvailable, isAvailable: nextSystem.storage.isAvailable)
    }

    private func logAvailabilityChange(component: StaticString, wasAvailable: Bool, isAvailable: Bool) {
        guard wasAvailable != isAvailable else { return }
        if isAvailable {
            logger.info("\(component, privacy: .public) metrics recovered")
        } else {
            logger.error("\(component, privacy: .public) metrics became unavailable")
        }
    }
}
