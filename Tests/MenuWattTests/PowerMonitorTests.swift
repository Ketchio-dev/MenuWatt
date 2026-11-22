import AppKit
import Combine
import Foundation
import Testing
@testable import MenuWatt
@testable import MenuWattCore

actor TestSampler: MonitorSampling {
    struct Response {
        let payload: SamplePayload
        let delayNanoseconds: UInt64
    }

    private var responses: [Response]
    private var sampleCount = 0

    init(responses: [Response]) {
        self.responses = responses
    }

    func sample() async -> SamplePayload {
        sampleCount += 1
        let response = responses.isEmpty ? .steadyState : responses.removeFirst()
        if response.delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: response.delayNanoseconds)
        }
        return response.payload
    }

    func count() -> Int {
        sampleCount
    }
}

@Suite @MainActor
struct PowerMonitorTests {
    @Test
    func latestRefreshWinsWhenPreviousRequestFinishesLater() async {
        let firstPayload = SamplePayload(
            battery: makeBatterySnapshot(percentage: 12, state: .onBattery),
            system: makeSystemSnapshot(cpuUsage: 10)
        )
        let secondPayload = SamplePayload(
            battery: makeBatterySnapshot(percentage: 88, state: .charging),
            system: makeSystemSnapshot(cpuUsage: 72)
        )
        let sampler = TestSampler(
            responses: [
                .steadyState,
                .init(payload: firstPayload, delayNanoseconds: 200_000_000),
                .init(payload: secondPayload, delayNanoseconds: 0)
            ]
        )
        let monitor = PowerMonitor(
            sampler: sampler,
            configuration: .init(refreshInterval: 60, animationMinimumInterval: 0.02)
        )
        defer { monitor.stop() }

        monitor.start()
        monitor.refreshNow()
        monitor.refreshNow()
        try? await Task.sleep(nanoseconds: 350_000_000)

        #expect(monitor.snapshot.percentage == 88)
        #expect(monitor.snapshot.state == .charging)
        #expect(abs(monitor.systemSnapshot.cpu.totalUsage - 72) < 0.001)
    }

    @Test
    func startIsIdempotent() async {
        let sampler = TestSampler(responses: [.steadyState])
        let monitor = PowerMonitor(
            sampler: sampler,
            configuration: .init(refreshInterval: 60, animationMinimumInterval: 0.02)
        )
        defer { monitor.stop() }

        monitor.start()
        monitor.start()
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(await sampler.count() == 1)
    }

    @Test
    func shorterRefreshIntervalTakesEffectWithoutWaitingForOldSleep() async throws {
        let sampler = TestSampler(responses: [.steadyState])
        let monitor = PowerMonitor(
            sampler: sampler,
            configuration: .init(refreshInterval: 60, animationMinimumInterval: 0.02)
        )
        defer { monitor.stop() }
        monitor.start()
        try await waitUntil { await sampler.count() >= 1 }
        #expect(await sampler.count() == 1)
        monitor.setRefreshInterval(0.02)
        try await waitUntil { await sampler.count() >= 3 }
        monitor.stop()
        let stoppedCount = await sampler.count()
        try await Task.sleep(for: .milliseconds(60))
        #expect(await sampler.count() == stoppedCount)
    }

    @Test
    func stopPreventsFurtherRefreshesAndAnimationTicks() async {
        let payload = SamplePayload(
            battery: makeBatterySnapshot(percentage: 80, state: .charging),
            system: makeSystemSnapshot(cpuUsage: 100)
        )
        let sampler = TestSampler(responses: [.init(payload: payload, delayNanoseconds: 0)])
        let monitor = PowerMonitor(
            sampler: sampler,
            configuration: .init(refreshInterval: 0.05, animationMinimumInterval: 0.02)
        )
        defer { monitor.stop() }

        monitor.start()
        try? await Task.sleep(nanoseconds: 160_000_000)
        monitor.stop()
        try? await Task.sleep(nanoseconds: 80_000_000)

        let settledCount = await sampler.count()
        let settledFrame = monitor.currentSpriteFrame
        try? await Task.sleep(nanoseconds: 160_000_000)

        #expect(await sampler.count() == settledCount)
        #expect(monitor.currentSpriteFrame == settledFrame)
    }

    @Test
    func publishedFramesAdvanceBetweenSamplesAtLongRefreshInterval() async throws {
        let payload = SamplePayload(
            battery: makeBatterySnapshot(percentage: 80, state: .charging),
            system: makeSystemSnapshot(cpuUsage: 100)
        )
        let sampler = TestSampler(responses: [.init(payload: payload, delayNanoseconds: 0)])
        let monitor = PowerMonitor(
            sampler: sampler,
            configuration: .init(refreshInterval: 60, animationMinimumInterval: 0.02)
        )
        defer { monitor.stop() }
        var publishedFrames: [(frame: SpriteFrame, image: NSImage)] = []
        let subscription = monitor.$currentFrame.dropFirst().sink { image in
            publishedFrames.append((monitor.currentSpriteFrame, image))
        }
        defer { subscription.cancel() }

        monitor.start()
        monitor.start()
        try await waitUntil { monitor.snapshot.percentage == 80 }
        publishedFrames.removeAll()
        try await waitUntil { publishedFrames.count >= 3 }

        #expect(publishedFrames.prefix(3).map(\.frame) == [.run2, .run3, .run4])
        for published in publishedFrames {
            #expect(published.image === SpriteRenderer.image(for: published.frame))
        }
        #expect(monitor.currentFrame === SpriteRenderer.image(for: monitor.currentSpriteFrame))
        #expect(await sampler.count() == 1)
    }

    @Test
    func stopFreezesPublishedFramesAndRestartResumesAtLongRefreshInterval() async throws {
        let sampler = TestSampler(responses: [
            .steadyState,
            .init(payload: SamplePayload(
                battery: makeBatterySnapshot(percentage: 81, state: .charging),
                system: makeSystemSnapshot(cpuUsage: 100)
            ), delayNanoseconds: 0)
        ])
        let monitor = PowerMonitor(
            sampler: sampler,
            configuration: .init(refreshInterval: 60, animationMinimumInterval: 0.02)
        )
        defer { monitor.stop() }
        var publishedFrames: [SpriteFrame] = []
        let subscription = monitor.$currentFrame.dropFirst().sink { _ in
            publishedFrames.append(monitor.currentSpriteFrame)
        }
        defer { subscription.cancel() }

        monitor.start()
        try await waitUntil { monitor.snapshot.percentage == 50 }
        publishedFrames.removeAll()
        try await waitUntil { publishedFrames.count >= 2 }
        monitor.stop()
        monitor.stop()
        let stoppedFrame = monitor.currentSpriteFrame
        let stoppedImage = monitor.currentFrame
        let stoppedPublicationCount = publishedFrames.count
        monitor.refreshNow()
        try await Task.sleep(for: .milliseconds(200))

        #expect(monitor.currentSpriteFrame == stoppedFrame)
        #expect(monitor.currentFrame === stoppedImage)
        #expect(publishedFrames.count == stoppedPublicationCount)
        #expect(await sampler.count() == 1)

        monitor.start()
        monitor.start()
        try await waitUntil { monitor.snapshot.percentage == 81 }
        publishedFrames.removeAll()
        try await waitUntil { publishedFrames.count >= 2 }

        #expect(publishedFrames.prefix(2) == [.run2, .run3])
        #expect(monitor.currentFrame === SpriteRenderer.image(for: monitor.currentSpriteFrame))
        #expect(await sampler.count() == 2)
    }

    @Test
    func animatorReadsCurrentStateAfterSleeping() async throws {
        @MainActor
        final class TickState {
            var state = BatteryState.charging
            var lastReading: BatteryState?
            var advancedState: BatteryState?
        }
        let tickState = TickState()
        let animator = MonitorSpriteAnimator(minimumInterval: 0.02, initialState: .charging)
        defer { animator.stop() }
        animator.start(tick: {
            tickState.lastReading = tickState.state
            return (state: tickState.state, cpuUsage: 0)
        }, onFrameChange: {
            tickState.advancedState = tickState.lastReading
        })
        try await waitUntil { tickState.lastReading != nil }
        tickState.state = .full
        try await waitUntil { tickState.advancedState != nil }

        #expect(tickState.advancedState == .full)
    }

    @Test
    func animatorDoesNotRetainItselfWhileSleeping() async throws {
        var animator: MonitorSpriteAnimator? = MonitorSpriteAnimator(
            minimumInterval: 0.02, initialState: .charging
        )
        weak let releasedAnimator = animator
        defer { releasedAnimator?.stop() }
        var didRead = false
        animator?.start(tick: {
            didRead = true
            return (state: .charging, cpuUsage: 0)
        }, onFrameChange: {})
        try await waitUntil { didRead }
        animator = nil

        #expect(releasedAnimator == nil)
    }

    @Test
    func allBatteryStatesUseTheSameRunningFrames() {
        let expectedFrames = BoochiPresentation.runningFrames
        let states: [BatteryState] = [.charging, .pluggedIn, .onBattery, .full, .unavailable, .absent]

        for state in states {
            let presentation = BoochiPresentation.make(for: state)
            #expect(presentation.animationFrames == expectedFrames)
            #expect(presentation.fallbackFrame == .run1)
        }
    }

    @Test
    func animationIntervalClampsAcrossCpuRange() {
        let low = BoochiAnimationPolicy.interval(for: .charging, cpuUsage: 0, minimumInterval: 0.02)
        let medium = BoochiAnimationPolicy.interval(for: .charging, cpuUsage: 50, minimumInterval: 0.02)
        let high = BoochiAnimationPolicy.interval(for: .charging, cpuUsage: 250, minimumInterval: 0.02)

        #expect(abs(low - 0.14) < 0.0001)
        #expect(medium < low)
        #expect(abs(high - 0.02) < 0.0001)
    }

    @Test
    func presentationMappingsRemainStable() {
        #expect(BoochiPresentation.make(for: .charging).title == "Charging")
        #expect(BoochiPresentation.make(for: .pluggedIn).title == "On Adapter")
        #expect(BoochiPresentation.make(for: .full).title == "Fully Charged")
        #expect(PressureLevelPresentation.themeColor(for: .critical) == .red)
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await condition()), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(await condition())
    }
}

private extension TestSampler.Response {
    static let steadyState = TestSampler.Response(
        payload: SamplePayload(
            battery: makeBatterySnapshot(percentage: 50, state: .charging),
            system: makeSystemSnapshot(cpuUsage: 15)
        ),
        delayNanoseconds: 0
    )
}

private func makeBatterySnapshot(percentage: Int, state: BatteryState) -> BatterySnapshot {
    BatterySnapshot(
        name: "Test Battery",
        percentage: percentage,
        state: state,
        sourceDescription: "Battery",
        timeEstimate: nil,
        rateDetail: nil,
        liveInputDetail: nil,
        batteryWatts: nil,
        adapterWatts: nil,
        systemInputWatts: nil,
        systemLoadWatts: nil,
        cycleCount: nil,
        temperatureCelsius: nil,
        updatedAt: .now
    )
}

private func makeSystemSnapshot(cpuUsage: Double) -> SystemSnapshot {
    SystemSnapshot(
        cpu: CPUSnapshot(
            totalUsage: cpuUsage,
            userUsage: cpuUsage * 0.7,
            systemUsage: cpuUsage * 0.3,
            idleUsage: max(0, 100 - cpuUsage),
            history: []
        ),
        memory: .unavailable,
        storage: .unavailable
    )
}
