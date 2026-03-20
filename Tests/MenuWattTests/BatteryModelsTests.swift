import Foundation
import Testing
@testable import MenuWattCore

@Test
func chargingMenuBarPowerTextPrefersLiveInputThenBatteryThenAdapter() {
    let preferredInput = makeSnapshot(
        state: .charging,
        batteryWatts: 8.4,
        adapterWatts: 35,
        systemInputWatts: 27.8,
        systemLoadWatts: nil
    )
    let batteryFallback = makeSnapshot(
        state: .charging,
        batteryWatts: 8.4,
        adapterWatts: 35,
        systemInputWatts: nil,
        systemLoadWatts: nil
    )
    let adapterFallback = makeSnapshot(
        state: .charging,
        batteryWatts: nil,
        adapterWatts: 35,
        systemInputWatts: nil,
        systemLoadWatts: nil
    )

    #expect(preferredInput.menuBarPowerText == "27.8W")
    #expect(batteryFallback.menuBarPowerText == "8.4W")
    #expect(adapterFallback.menuBarPowerText == "35W")
}

@Test
func onBatteryMenuBarPowerTextPrefersSystemLoadThenBatteryWatts() {
    let preferredLoad = makeSnapshot(
        state: .onBattery,
        batteryWatts: 6.4,
        adapterWatts: nil,
        systemInputWatts: nil,
        systemLoadWatts: 12.2
    )
    let batteryFallback = makeSnapshot(
        state: .onBattery,
        batteryWatts: 6.4,
        adapterWatts: nil,
        systemInputWatts: nil,
        systemLoadWatts: nil
    )

    #expect(preferredLoad.menuBarPowerText == "12.2W")
    #expect(batteryFallback.menuBarPowerText == "6.4W")
}

@Test
func adapterDescriptionIncludesInputWhenAvailable() {
    let snapshot = makeSnapshot(
        state: .pluggedIn,
        batteryWatts: nil,
        adapterWatts: 67,
        systemInputWatts: 42.3,
        systemLoadWatts: nil
    )

    #expect(snapshot.adapterDescription == "Input 42.3 W / Adapter 67 W")
}

private func makeSnapshot(
    state: BatteryState,
    batteryWatts: Double?,
    adapterWatts: Double?,
    systemInputWatts: Double?,
    systemLoadWatts: Double?
) -> BatterySnapshot {
    BatterySnapshot(
        name: "Battery",
        percentage: 50,
        state: state,
        sourceDescription: "Battery",
        timeEstimate: nil,
        rateDetail: nil,
        liveInputDetail: nil,
        batteryWatts: batteryWatts,
        adapterWatts: adapterWatts,
        systemInputWatts: systemInputWatts,
        systemLoadWatts: systemLoadWatts,
        cycleCount: nil,
        temperatureCelsius: nil,
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}
