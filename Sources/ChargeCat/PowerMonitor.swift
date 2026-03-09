import AppKit
import SwiftUI

private struct SamplePayload: Sendable {
    let battery: BatterySnapshot
    let system: SystemSnapshot
}

private actor MonitorSamplerEngine {
    private let systemSampler = SystemSampler()

    func sample() -> SamplePayload {
        SamplePayload(
            battery: BatteryReader.read(),
            system: systemSampler.read()
        )
    }
}

@MainActor
final class PowerMonitor: ObservableObject {
    @Published private(set) var snapshot = BatterySnapshot.unavailable
    @Published private(set) var systemSnapshot = SystemSnapshot.unavailable
    @Published private(set) var currentFrame = SpriteRenderer.image(for: .sleep1)

    private var animationTimer: Timer?
    private var refreshTimer: Timer?
    private var frameIndex = 0
    private let refreshInterval: TimeInterval = 1
    private let samplerEngine = MonitorSamplerEngine()

    init() {
        scheduleRefreshTimer()
        scheduleAnimationTimer()
        refreshNow()
    }

    func refreshNow() {
        requestRefresh(resetAnimation: true)
    }

    private func requestRefresh(resetAnimation: Bool) {
        Task { [weak self] in
            guard let self else { return }
            let payload = await samplerEngine.sample()
            self.apply(payload, resetAnimation: resetAnimation)
        }
    }

    private func apply(_ payload: SamplePayload, resetAnimation: Bool) {
        let previousState = snapshot.state
        let previousCpu = systemSnapshot.cpu.totalUsage
        let nextSnapshot = payload.battery
        let nextSystemSnapshot = payload.system

        snapshot = nextSnapshot
        systemSnapshot = nextSystemSnapshot

        if resetAnimation || previousState != nextSnapshot.state {
            frameIndex = 0
        }

        updateCurrentFrame()

        // Reschedule if state changed or if CPU usage changed significantly (e.g. > 2%)
        let cpuChangedSignificantly = abs(previousCpu - nextSystemSnapshot.cpu.totalUsage) > 2.0
        if previousState != nextSnapshot.state || cpuChangedSignificantly {
            scheduleAnimationTimer()
        }
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.requestRefresh(resetAnimation: false)
            }
        }
        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }
    }

    private func scheduleAnimationTimer() {
        animationTimer?.invalidate()

        // Base interval according to battery state
        let baseInterval = snapshot.state.animationInterval
        
        // Calculate dynamic interval based on CPU usage (0-100%)
        // If CPU usage is 100%, we want to be very fast e.g. baseInterval / 10
        // If CPU usage is 0%, we want it to be baseInterval
        let cpuUsage = max(0, min(100.0, systemSnapshot.cpu.totalUsage))
        let speedMultiplier = 1.0 + (cpuUsage / 100.0) * 9.0 // 1x to 10x faster
        let dynamicInterval = max(0.02, baseInterval / speedMultiplier)

        animationTimer = Timer.scheduledTimer(withTimeInterval: dynamicInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceFrame()
            }
        }
        if let animationTimer {
            RunLoop.main.add(animationTimer, forMode: .common)
        }
    }

    private func advanceFrame() {
        let frames = snapshot.state.frames
        guard !frames.isEmpty else { return }

        frameIndex = (frameIndex + 1) % frames.count
        updateCurrentFrame()
    }

    private func updateCurrentFrame() {
        let frames = snapshot.state.frames
        let safeIndex = frames.isEmpty ? 0 : frameIndex % frames.count
        let frame = frames.isEmpty ? SpriteFrame.sleep1 : frames[safeIndex]
        currentFrame = SpriteRenderer.image(for: frame)
    }
}
