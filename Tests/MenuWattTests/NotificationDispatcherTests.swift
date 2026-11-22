import Foundation
import Testing
import UserNotifications
@testable import MenuWatt
@testable import MenuWattCore

@Suite(.serialized)
@MainActor
struct NotificationDispatcherTests {
    @Test
    func enabledAlertsFireOnlyOnTheirBatteryTransitions() {
        let fixture = Fixture()
        defer { fixture.dispose() }
        let notify = Recorder()
        fixture.preferences.notifyChargeComplete = true
        fixture.preferences.notifyLowBattery = true
        for (previous, next) in [
            (battery(.charging, 99), battery(.full, 100)),
            (battery(.pluggedIn, 99), battery(.full, 100)),
            (battery(.onBattery, 21), battery(.onBattery, 20))
        ] {
            NotificationDispatcher.evaluate(previous: previous, next: next,
                preferences: fixture.preferences, notifier: notify)
        }
        #expect(notify.kinds == [.chargeComplete, .chargeComplete, .lowBattery])
        #expect(notify.bodies.last?.contains("20%") == true)
        for (previous, next) in [
            (battery(.full, 100), battery(.full, 100)),
            (battery(.onBattery, 20), battery(.onBattery, 19)),
            (BatterySnapshot.unavailable, battery(.onBattery, 10)),
            (battery(.onBattery, 21), battery(.charging, 20)),
            (battery(.onBattery, 21), battery(.onBattery, 0))
        ] {
            NotificationDispatcher.evaluate(previous: previous, next: next,
                preferences: fixture.preferences, notifier: notify)
        }
        #expect(notify.kinds.count == 3)
    }

    @Test
    func disabledAlertsDoNotDeliver() {
        let fixture = Fixture()
        defer { fixture.dispose() }
        let notify = Recorder()
        #expect(!fixture.preferences.notifyChargeComplete)
        #expect(!fixture.preferences.notifyLowBattery)
        NotificationDispatcher.evaluate(previous: battery(.charging, 99), next: battery(.full, 100),
            preferences: fixture.preferences, notifier: notify)
        NotificationDispatcher.evaluate(previous: battery(.onBattery, 21), next: battery(.onBattery, 20),
            preferences: fixture.preferences, notifier: notify)
        #expect(notify.kinds.isEmpty)
    }

    @Test
    func foregroundAlertsAndUpdateLinkPayloadHaveExplicitHandling() {
        #expect(NotificationInteraction.presentationOptions.contains(.banner))
        #expect(NotificationInteraction.presentationOptions.contains(.list))
        #expect(NotificationInteraction.presentationOptions.contains(.sound))
        let release = "https://github.com/Ketchio-dev/MenuWatt/releases/tag/v1.1.1"
        #expect(NotificationInteraction.releaseURL(from: ["url": release])?.absoluteString == release)
        for url in ["file:///tmp/test", "http://github.com/Ketchio-dev/MenuWatt/releases",
                    "https://github.com.evil.invalid/Ketchio-dev/MenuWatt/releases",
                    "https://github.com/another/repo/releases", "https://github.com/Ketchio-dev/MenuWatt/releases-elsewhere"] {
            #expect(NotificationInteraction.releaseURL(from: ["url": url]) == nil)
        }
        #expect(NotificationInteraction.releaseURL(from: [:]) == nil)
    }

    private func battery(_ state: BatteryState, _ percentage: Int) -> BatterySnapshot {
        .init(name: "Test Battery", percentage: percentage, state: state, sourceDescription: "Fixture",
            timeEstimate: nil, rateDetail: nil, liveInputDetail: nil, batteryWatts: nil,
            adapterWatts: nil, systemInputWatts: nil, systemLoadWatts: nil,
            cycleCount: nil, temperatureCelsius: nil, updatedAt: .now)
    }
}

@MainActor
private final class Recorder: NotificationSending {
    var kinds: [NotificationManager.Kind] = []
    var bodies: [String] = []
    func notify(kind: NotificationManager.Kind, title: String, body: String, userInfo: [String: String]) {
        kinds.append(kind); bodies.append(body)
    }
}

@MainActor
private final class Fixture {
    let domain = "MenuWatt.NotificationTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let preferences: AppPreferences
    init() {
        defaults = UserDefaults(suiteName: domain)!
        preferences = AppPreferences(launchAtLoginController: LoginStub(), defaults: defaults)
    }
    func dispose() { defaults.removePersistentDomain(forName: domain) }
}

private struct LoginStub: LaunchAtLoginControlling {
    let isEnabled = false
    func setEnabled(_ enabled: Bool) throws {}
}
