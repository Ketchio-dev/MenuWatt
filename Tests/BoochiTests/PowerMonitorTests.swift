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
            .init(payload: firstPayload, delayNanoseconds: 200_000_000),
            .init(payload: secondPayload, delayNanoseconds: 0)
        ]
    )

    let monitor = await MainActor.run {
        PowerMonitor(
            sampler: sampler,
            configuration: .init(refreshInterval: 60, animationMinimumInterval: 0.02)
        )
    }

    await MainActor.run {
        monitor.refreshNow()
        monitor.refreshNow()
    }

    try? await Task.sleep(nanoseconds: 350_000_000)

    await MainActor.run {
        #expect(monitor.snapshot.percentage == 88)
        #expect(monitor.snapshot.state == .charging)
        #expect(abs(monitor.systemSnapshot.cpu.totalUsage - 72) < 0.001)
    }
}

@Test
func startIsIdempotent() async {
    let sampler = TestSampler(
        responses: [
            .steadyState
        ]
    )

    let monitor = await MainActor.run {
        PowerMonitor(
            sampler: sampler,
            configuration: .init(refreshInterval: 60, animationMinimumInterval: 0.02)
        )
    }

    await MainActor.run {
        monitor.start()
        monitor.start()
    }

    try? await Task.sleep(nanoseconds: 100_000_000)

    #expect(await sampler.count() == 1)
}

@Test
func stopPreventsFurtherRefreshesAndAnimationTicks() async {
    let payload = SamplePayload(
        battery: makeBatterySnapshot(percentage: 80, state: .charging),
        system: makeSystemSnapshot(cpuUsage: 100)
    )
    let sampler = TestSampler(
        responses: [
            .init(payload: payload, delayNanoseconds: 0)
        ]
    )

    let monitor = await MainActor.run {
        PowerMonitor(
            sampler: sampler,
            configuration: .init(refreshInterval: 0.05, animationMinimumInterval: 0.02)
        )
    }

    await MainActor.run {
        monitor.start()
    }

    try? await Task.sleep(nanoseconds: 160_000_000)

    let frozenCount = await sampler.count()
    let frozenFrame = await MainActor.run {
        monitor.stop()
        return monitor.currentSpriteFrame
    }

    try? await Task.sleep(nanoseconds: 160_000_000)

    #expect(await sampler.count() == frozenCount)
    await MainActor.run {
        #expect(monitor.currentSpriteFrame == frozenFrame)
    }
}

@Test
func allBatteryStatesUseTheSameRunningFrames() {
    let expectedFrames = BoochiPresentation.runningFrames
    let states: [BatteryState] = [.charging, .pluggedIn, .onBattery, .full, .unavailable]

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
