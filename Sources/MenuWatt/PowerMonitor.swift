import AppKit
import SwiftUI
import MenuWattCore
import MenuWattSystem

/// Publishes live battery, system and process snapshots plus the animated
/// menu bar sprite.
///
/// Wiring only: sampling cadence lives in `MonitorRefreshScheduler`, sprite
/// ticks in `MonitorSpriteAnimator`, transition logging in
/// `MonitorTransitionLog`. Public API (`init(sampler:configuration:)`,
/// `start/stop/refreshNow/setRefreshInterval`, published snapshots) is
/// unchanged.
@MainActor
final class PowerMonitor: ObservableObject {
    struct Configuration: Sendable {
        var refreshInterval: TimeInterval
        let animationMinimumInterval: TimeInterval

        static let live = Configuration(
            refreshInterval: 1.0,
            animationMinimumInterval: 0.02
        )
    }

    @Published private(set) var snapshot = BatterySnapshot.unavailable
    @Published private(set) var systemSnapshot = SystemSnapshot.unavailable
    @Published private(set) var processSnapshot = ProcessEnergySnapshot.unavailable
    @Published private(set) var currentFrame = SpriteRenderer.image(for: .run1)
    private(set) var currentSpriteFrame = SpriteFrame.run1

    private let scheduler: MonitorRefreshScheduler
    private let animator: MonitorSpriteAnimator
    private let sampler: any MonitorSampling
    private let logger = MenuWattDiagnostics.monitoring

    var batteryTransitionHandler: ((BatterySnapshot, BatterySnapshot) -> Void)?

    var refreshInterval: TimeInterval { scheduler.refreshInterval }

    func setRefreshInterval(_ interval: TimeInterval) {
        guard scheduler.refreshInterval != interval else { return }
        scheduler.refreshInterval = interval
        if scheduler.running {
            scheduler.restartLoop { [weak self] in self?.requestRefresh(resetAnimation: false) }
        }
        logger.info("Refresh interval updated to \(interval, privacy: .public)s")
    }

    init(
        sampler: any MonitorSampling = LiveMonitorSampler(),
        configuration: Configuration = .live
    ) {
        self.sampler = sampler
        scheduler = MonitorRefreshScheduler(refreshInterval: configuration.refreshInterval)
        animator = MonitorSpriteAnimator(
            minimumInterval: configuration.animationMinimumInterval,
            initialState: BatterySnapshot.unavailable.state
        )
        currentSpriteFrame = animator.currentSpriteFrame
        currentFrame = animator.currentFrame
    }

    func start() {
        logger.info("Power monitor started")
        scheduler.start(
            requestImmediate: { [weak self] in self?.requestRefresh(resetAnimation: true) },
            requestTick: { [weak self] in self?.requestRefresh(resetAnimation: false) }
        )
        animator.start { [weak self] in
            guard let self else { return (state: .unavailable, cpuUsage: 0) }
            return (state: self.snapshot.state, cpuUsage: self.systemSnapshot.cpu.totalUsage)
        }
    }

    func stop() {
        scheduler.stop()
        animator.stop()
        logger.info("Power monitor stopped")
    }

    func refreshNow() {
        requestRefresh(resetAnimation: true)
    }

    private func requestRefresh(resetAnimation: Bool) {
        scheduler.requestSample(sampler: sampler) { [weak self] payload, sequence in
            self?.applyIfCurrent(payload, resetAnimation: resetAnimation, sequence: sequence)
        }
    }

    private func applyIfCurrent(_ payload: SamplePayload, resetAnimation: Bool, sequence: UInt64) {
        guard scheduler.isCurrent(sequence) else { return }
        apply(payload, resetAnimation: resetAnimation)
        scheduler.finishRequest()
    }

    private func apply(_ payload: SamplePayload, resetAnimation: Bool) {
        let previousState = snapshot.state
        let previousBattery = snapshot
        let previousSystem = systemSnapshot
        let nextSnapshot = payload.battery

        snapshot = nextSnapshot
        systemSnapshot = payload.system
        processSnapshot = payload.processes
        MonitorTransitionLog.log(
            fromBattery: previousBattery, toBattery: nextSnapshot,
            fromSystem: previousSystem, toSystem: payload.system
        )
        batteryTransitionHandler?(previousBattery, nextSnapshot)

        if resetAnimation || previousState != nextSnapshot.state {
            animator.reset()
        }

        animator.refresh(state: nextSnapshot.state)
        currentSpriteFrame = animator.currentSpriteFrame
        currentFrame = animator.currentFrame
    }
}
