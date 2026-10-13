import Foundation
import MenuWattCore
import MenuWattSystem
import OSLog

/// Runs the periodic sampling loop: immediate first sample, then one sample
/// per interval. Restarting the loop (instead of finishing the old sleep) is
/// what makes interval changes take effect without waiting out the old sleep.
///
/// Extracted from PowerMonitor; tick timing and latest-wins sequencing are
/// unchanged. The sampler call stays on the caller's task so a slow sample
/// never blocks the next tick decision.
@MainActor
final class MonitorRefreshScheduler {
    private var loopTask: Task<Void, Never>?
    private var requestTask: Task<Void, Never>?
    private var sequence: UInt64 = 0
    private var isRunning = false

    var refreshInterval: TimeInterval

    init(refreshInterval: TimeInterval) {
        self.refreshInterval = refreshInterval
    }

    var running: Bool { isRunning }

    func start(requestImmediate: @escaping () -> Void, requestTick: @escaping () -> Void) {
        isRunning = true
        guard loopTask == nil else { return }
        requestImmediate()
        loopTask = Task { [weak self] in await self?.runLoop(requestTick: requestTick) }
    }

    func stop() {
        isRunning = false
        sequence &+= 1
        loopTask?.cancel()
        loopTask = nil
        requestTask?.cancel()
        requestTask = nil
    }

    func restartLoop(requestTick: @escaping () -> Void) {
        // Do not finish sleeping at the old interval after the user changes it.
        loopTask?.cancel()
        loopTask = Task { [weak self] in await self?.runLoop(requestTick: requestTick) }
    }

    /// Samples on a child task and delivers only the latest request's payload.
    func requestSample(
        sampler: any MonitorSampling,
        deliver: @escaping @MainActor (SamplePayload, UInt64) -> Void
    ) {
        guard isRunning else { return }
        sequence &+= 1
        let current = sequence
        requestTask?.cancel()
        requestTask = Task { [sampler] in
            let payload = await sampler.sample()
            guard !Task.isCancelled else { return }
            await MainActor.run { deliver(payload, current) }
        }
    }

    func isCurrent(_ candidate: UInt64) -> Bool {
        isRunning && candidate == sequence
    }

    func finishRequest() {
        requestTask = nil
    }

    private func runLoop(requestTick: @escaping () -> Void) async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: Self.nanoseconds(for: refreshInterval))
            guard !Task.isCancelled else { return }
            requestTick()
        }
    }

    private static func nanoseconds(for interval: TimeInterval) -> UInt64 {
        UInt64(max(interval, 0.001) * 1_000_000_000)
    }
}

/// Advances the menu bar sprite on a CPU-load-dependent tick.
///
/// Extracted from PowerMonitor. Frame selection (reset on state change,
/// round-robin otherwise) is unchanged.
@MainActor
final class MonitorSpriteAnimator {
    private var loopTask: Task<Void, Never>?
    private var frameIndex = 0
    private let minimumInterval: TimeInterval

    private(set) var currentFrame = SpriteRenderer.image(for: .run1)
    private(set) var currentSpriteFrame = SpriteFrame.run1

    init(minimumInterval: TimeInterval, initialState: BatteryState) {
        self.minimumInterval = minimumInterval
        let initial = BoochiPresentation.make(for: initialState).fallbackFrame
        currentSpriteFrame = initial
        currentFrame = SpriteRenderer.image(for: initial)
    }

    func start(tick: @escaping @MainActor () -> (state: BatteryState, cpuUsage: Double)) {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let reading = await MainActor.run { tick() }
                let interval = BoochiAnimationPolicy.interval(
                    for: reading.state,
                    cpuUsage: reading.cpuUsage,
                    minimumInterval: self.minimumInterval
                )
                try? await Task.sleep(nanoseconds: UInt64(max(interval, 0.001) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run { self.advance(state: reading.state) }
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    func reset() {
        frameIndex = 0
    }

    func refresh(state: BatteryState) {
        let presentation = BoochiPresentation.make(for: state)
        let frames = presentation.animationFrames
        let safeIndex = frames.isEmpty ? 0 : frameIndex % frames.count
        let nextFrame = frames.isEmpty ? presentation.fallbackFrame : frames[safeIndex]
        currentSpriteFrame = nextFrame
        currentFrame = SpriteRenderer.image(for: nextFrame)
    }

    private func advance(state: BatteryState) {
        let frames = BoochiPresentation.make(for: state).animationFrames
        guard !frames.isEmpty else { return }
        frameIndex = (frameIndex + 1) % frames.count
        refresh(state: state)
    }
}

/// Logs battery and sensor availability transitions.
///
/// Extracted from PowerMonitor so the monitor file keeps only state wiring.
enum MonitorTransitionLog {
    static func log(
        fromBattery previousBattery: BatterySnapshot,
        toBattery nextBattery: BatterySnapshot,
        fromSystem previousSystem: SystemSnapshot,
        toSystem nextSystem: SystemSnapshot
    ) {
        let logger = MenuWattDiagnostics.monitoring
        if previousBattery.state != nextBattery.state {
            logger.info("Battery state changed to \(String(describing: nextBattery.state), privacy: .public)")
        }
        logAvailabilityChange(logger: logger, component: "battery",
            wasAvailable: isBatteryPresent(previousBattery.state),
            isAvailable: isBatteryPresent(nextBattery.state))
        logAvailabilityChange(logger: logger, component: "cpu",
            wasAvailable: previousSystem.cpu.isAvailable, isAvailable: nextSystem.cpu.isAvailable)
        logAvailabilityChange(logger: logger, component: "memory",
            wasAvailable: previousSystem.memory.isAvailable, isAvailable: nextSystem.memory.isAvailable)
        logAvailabilityChange(logger: logger, component: "storage",
            wasAvailable: previousSystem.storage.isAvailable, isAvailable: nextSystem.storage.isAvailable)
    }

    private static func isBatteryPresent(_ state: BatteryState) -> Bool {
        state != .unavailable && state != .absent
    }

    private static func logAvailabilityChange(
        logger: Logger, component: StaticString, wasAvailable: Bool, isAvailable: Bool
    ) {
        guard wasAvailable != isAvailable else { return }
        if isAvailable {
            logger.info("\(component, privacy: .public) metrics recovered")
        } else {
            logger.error("\(component, privacy: .public) metrics became unavailable")
        }
    }
}
