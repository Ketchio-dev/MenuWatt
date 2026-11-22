import AppKit
import SwiftUI
import MenuWattCore

struct NotificationsSettingsPane: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsPaneTitle(
                title: "Notifications",
                subtitle: "Battery alerts, delivered by macOS."
            )

            SettingsCard(title: "Battery", systemImage: "battery.50") {
                SettingsRow(label: "Notify when fully charged") {
                    Toggle("Notify when fully charged", isOn: $preferences.notifyChargeComplete)
                        .labelsHidden()
                }

                SettingsRow(label: "Notify when battery is low") {
                    Toggle("Notify when battery is low", isOn: $preferences.notifyLowBattery)
                        .labelsHidden()
                }

                if preferences.notifyLowBattery {
                    SettingsRow(label: "Low battery threshold") {
                        HStack(spacing: 10) {
                            Text("\(preferences.lowBatteryThreshold)%")
                                .font(.system(size: 12, design: .monospaced))
                            Stepper("Low battery threshold", value: $preferences.lowBatteryThreshold,
                                    in: 5...50, step: 5).labelsHidden()
                        }
                    }
                }
            }

            SettingsCard(title: "Delivery", systemImage: "bell") {
                SettingsNote("The same alert fires at most once every 5 minutes. Allow notifications in System Settings → Notifications → MenuWatt.")
            }
        }
    }
}
