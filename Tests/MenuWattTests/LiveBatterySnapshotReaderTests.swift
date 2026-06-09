import Foundation
import IOKit.ps
import Testing
@testable import MenuWattCore
@testable import MenuWattSystem

@Test
func batteryReaderBuildsChargingSnapshotFromInjectedDependencies() {
    let reader = LiveBatterySnapshotReader(
        dependencies: .init(
            readPowerSourceSnapshot: {
                .init(
                    currentCapacity: 40,
                    maxCapacity: 80,
                    isCharging: true,
                    isCharged: false,
                    sourceState: kIOPSACPowerValue,
                    name: "Battery A",
                    timeToFullCharge: 90,
                    timeToEmpty: nil
                )
            },
            readMetrics: {
                SmartBatteryMetrics(
                    batteryWatts: 12.4,
                    adapterWatts: 35,
                    systemInputWatts: 27.8,
                    systemLoadWatts: 21.3,
                    cycleCount: 123,
                    temperatureCelsius: 31.5
                )
            },
            now: { Date(timeIntervalSince1970: 1234) }
        )
    )

    let snapshot = reader.read()

    #expect(snapshot.name == "Battery A")
    #expect(snapshot.percentage == 50)
    #expect(snapshot.state == .charging)
    #expect(snapshot.sourceDescription == "Power Adapter")
    #expect(snapshot.timeEstimate?.description == "Full in 1h 30m")
    #expect(snapshot.rateDetail?.kind == .charging)
    #expect(snapshot.liveInputDetail?.kind == .liveInput)
    #expect(snapshot.cycleCount == 123)
    #expect(snapshot.temperatureCelsius == 31.5)
    #expect(snapshot.updatedAt == Date(timeIntervalSince1970: 1234))
}

@Test
func batteryReaderReportsAbsentWithSystemPowerWhenNoPowerSource() {
    let reader = LiveBatterySnapshotReader(
        dependencies: .init(
            readPowerSourceSnapshot: { nil },
            readMetrics: {
                SmartBatteryMetrics(
                    batteryWatts: nil,
                    adapterWatts: nil,
                    systemInputWatts: 30.0,
                    systemLoadWatts: 18.5,
                    cycleCount: nil,
                    temperatureCelsius: nil
                )
            },
            now: { Date(timeIntervalSince1970: 1234) }
        )
    )

    let snapshot = reader.read()

    #expect(snapshot.state == .absent)
    #expect(snapshot.systemLoadWatts == 18.5)
    #expect(snapshot.menuBarPowerText == "18.5W")
    #expect(snapshot.updatedAt == Date(timeIntervalSince1970: 1234))
}

@Test
func batteryReaderReportsAbsentWithoutPowerTextWhenNoMetrics() {
    let reader = LiveBatterySnapshotReader(
        dependencies: .init(
            readPowerSourceSnapshot: { nil },
            readMetrics: { nil },
            now: Date.init
        )
    )

    let snapshot = reader.read()

    #expect(snapshot.state == .absent)
    #expect(snapshot.menuBarPowerText == nil)
}
