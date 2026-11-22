import AppKit
import SwiftUI
import MenuWattSystem

struct OverviewSettingsPane: View {
    @ObservedObject var preferences: AppPreferences

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { preferences.launchesAtLogin },
            set: { preferences.setLaunchAtLogin($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsPaneTitle(
                title: "Overview",
                subtitle: "Startup, menu bar display and dashboard sections."
            )

            SettingsCard(title: "Startup", systemImage: "power") {
                SettingsRow(label: "Launch at Login") {
                    Toggle("Launch at Login", isOn: launchAtLoginBinding)
                        .labelsHidden()
                }

                if let launchAtLoginError = preferences.launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .onTapGesture {
                            preferences.dismissLaunchAtLoginError()
                        }
                }
            }

            SettingsCard(title: "Menu Bar Display", systemImage: "menubar.rectangle") {
                SettingsRow(label: "Indicator") {
                    Picker("", selection: $preferences.menuBarIndicator) {
                        ForEach(MenuBarIndicator.allCases) { indicator in
                            Text(indicator.title).tag(indicator)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 166, alignment: .trailing)
                    .accessibilityLabel("Menu bar indicator")
                }

                SettingsRow(label: "Update interval") {
                    Picker("", selection: $preferences.refreshInterval) {
                        ForEach(MenuBarRefreshInterval.allCases) { interval in
                            Text(interval.title).tag(interval)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 216)
                    .accessibilityLabel("Update interval")
                }

                SettingsRow(label: "Show pixel character") {
                    Toggle("Show pixel character", isOn: $preferences.showsSprite)
                        .labelsHidden()
                }
            }

            SettingsCard(title: "Dashboard", systemImage: "square.stack.3d.up") {
                SettingsRow(label: "Show graphs", detail: "CPU, GPU and network history.") {
                    Toggle("Show graphs", isOn: $preferences.showsGraphs).labelsHidden()
                }
                Text("Visible sections").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary).padding(.top, 6)
                ForEach(availableSections) { section in
                    SettingsRow(label: section.title, systemImage: section.symbolName) {
                        Toggle(section.title, isOn: dashboardSectionBinding(for: section))
                            .labelsHidden()
                    }
                }

                SettingsNote("Choose what appears in the menu bar panel. Hidden sections are still sampled in the background.")
            }
        }
    }

    // Desktop Macs have no battery — don't offer a Battery section toggle there.
    private var availableSections: [DashboardSection] {
        DashboardSection.allCases.filter { section in
            section != .battery || HostCapabilities.hasInternalBattery
        }
    }

    private func dashboardSectionBinding(for section: DashboardSection) -> Binding<Bool> {
        Binding(
            get: { preferences.isDashboardSectionVisible(section) },
            set: { preferences.setDashboardSection(section, visible: $0) }
        )
    }
}
