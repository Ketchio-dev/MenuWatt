import Foundation
import MenuWattCore

@MainActor
protocol NotificationSending {
    func notify(kind: NotificationManager.Kind, title: String, body: String, userInfo: [String: String])
}

extension NotificationManager: NotificationSending {}

@MainActor
enum NotificationDispatcher {
    static func evaluate(
        previous: BatterySnapshot,
        next: BatterySnapshot,
        preferences: AppPreferences,
        notifier: any NotificationSending = NotificationManager.shared
    ) {
        if preferences.notifyChargeComplete,
           isCharging(previous.state),
           next.state == .full {
            notifier.notify(
                kind: .chargeComplete,
                title: "Battery Charged",
                body: "Your Mac is now fully charged.",
                userInfo: [:]
            )
        }

        if preferences.notifyLowBattery,
           next.state == .onBattery,
           previous.state != .unavailable,
           previous.percentage > preferences.lowBatteryThreshold,
           next.percentage <= preferences.lowBatteryThreshold,
           next.percentage > 0 {
            notifier.notify(
                kind: .lowBattery,
                title: "Low Battery",
                body: "Battery is at \(next.percentage)%. Consider plugging in.",
                userInfo: [:]
            )
        }

    }

    private static func isCharging(_ state: BatteryState) -> Bool {
        state == .charging || state == .pluggedIn
    }
}
