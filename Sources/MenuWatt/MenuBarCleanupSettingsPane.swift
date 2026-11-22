import AppKit
import SwiftUI
import MenuWattCore

struct MenuBarCleanupSettingsPane: View {
    @ObservedObject var cleanup: MenuBarCleanupController
    @State private var appSearch = ""

    private var filteredApps: [MenuBarCleanupEntry] {
        let query = appSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanup.entries.filter {
            $0.bundleID != nil && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                || $0.bundleID?.localizedCaseInsensitiveContains(query) == true)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsPaneTitle(title: "Menu Bar", subtitle: "Choose which icons stay visible.")

            cleanupStatus

            if cleanup.isSupported {
                SettingsCard(title: "Reveal & Restore", systemImage: "arrow.left.and.right") {
                    HStack(spacing: 8) {
                        Button(cleanup.isExpanded ? "Collapse" : "Show Hidden") { cleanup.toggleHiddenItems() }
                            .disabled(!cleanup.canRevealItems)
                        Button("Show All") { cleanup.showAllItems() }
                            .disabled(!cleanup.canRevealItems)
                            .help("Reveals Always Hidden icons too. Activity controls follow your option below.")
                        Spacer(minLength: 0)
                        Button("Restore Menu Bar") { cleanup.restoreSystemMenuBar() }
                            .help("Turns cleanup off. Your app assignments are kept.")
                    }
                    .buttonStyle(SettingsActionStyle())
                    .disabled(!cleanup.enabled)
                    if cleanup.hotKeysAvailable {
                        HStack(spacing: 16) {
                            shortcut("⌃⌥⌘M", label: "Show / collapse")
                            shortcut("⌃⌥⌘R", label: "Restore")
                        }
                    } else if cleanup.enabled {
                        SettingsNote("A keyboard shortcut is already in use. The buttons remain available.")
                    }
                }

                SettingsCard(title: "Behavior", systemImage: "slider.horizontal.3") {
                    SettingsRow(label: "Hide large activity controls", detail: "Keeps the microphone and camera controls hidden while audio continues.") {
                        Toggle("Hide large activity controls", isOn: $cleanup.keepActivityControlsHidden)
                            .labelsHidden()
                    }
                    SettingsRow(label: "Collapse after 15 seconds") {
                        Toggle("Collapse after 15 seconds", isOn: $cleanup.autoRehide).labelsHidden()
                    }
                    SettingsRow(label: "Reveal on hover", detail: "Shows Hidden icons while the pointer is over the menu bar.") {
                        Toggle("Reveal on hover", isOn: $cleanup.revealOnHover).labelsHidden()
                    }
                }

                SettingsCard(title: "System Icons", systemImage: "menubar.rectangle") {
                    ForEach(cleanup.entries.filter { $0.bundleID == nil }) { entry in
                        cleanupRow(entry)
                    }
                    SettingsNote("The clock, Control Center and MenuWatt stay visible. Use ⌘-drag in the menu bar to reorder icons.")
                }

                SettingsCard(title: "Apps", systemImage: "app") {
                    SettingsNote("All icons from the same app share a setting. Helpers are listed separately.")
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        TextField("Name or bundle ID", text: $appSearch)
                            .textFieldStyle(.plain)
                            .accessibilityLabel("Search apps")
                            .accessibilityIdentifier("settings.apps.search")
                        if !appSearch.isEmpty {
                            Button { appSearch = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                    .frame(width: 24, height: 24)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear app search")
                        }
                    }
                    .padding(9)
                    .background(SettingsTheme.inset, in: RoundedRectangle(cornerRadius: 6))
                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(SettingsTheme.rule) }

                    if filteredApps.isEmpty {
                        Text(appSearch.isEmpty ? "No apps to show. Open an app or refresh the list."
                             : "No apps match “\(appSearch.trimmingCharacters(in: .whitespacesAndNewlines))”.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 12)
                    }
                    ForEach(filteredApps) { entry in cleanupRow(entry) }
                    HStack {
                        Text("\(filteredApps.count) apps").font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Refresh Apps") { cleanup.refresh() }
                            .buttonStyle(SettingsActionStyle())
                    }
                }
            }
        }
        .onAppear { cleanup.refresh() }
    }

    private var cleanupStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Menu Bar Cleanup").font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle("Enable Menu Bar Cleanup", isOn: $cleanup.enabled).labelsHidden()
                    .disabled(!cleanup.isSupported)
            }
            Rectangle().fill(SettingsTheme.rule).frame(height: 1)
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: cleanup.errorMessage != nil ? "exclamationmark.circle"
                      : cleanup.isPaused ? "pause.circle" : "menubar.rectangle")
                    .font(.system(size: 18))
                    .foregroundStyle(cleanup.isPaused || cleanup.errorMessage != nil
                                     ? SettingsTheme.accent : Color.secondary)
                    .accessibilityHidden(true)
                Text(cleanup.errorMessage ?? (cleanup.isPaused ? "Cleanup is paused." : cleanup.status))
                    .font(.system(size: 12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if cleanup.isSupported {
                    Button(cleanup.isPaused ? "Resume Cleanup" : "Pause Cleanup") {
                        if cleanup.isPaused { cleanup.resumeCleanup() } else { cleanup.pauseCleanup() }
                    }
                    .buttonStyle(SettingsActionStyle(prominent: cleanup.isPaused))
                    .disabled(!cleanup.enabled)
                    .help(cleanup.isPaused ? "Reapplies cleanup with your saved choices."
                          : "Releases the system restriction and may reveal all icons, including Always Hidden.")
                }
            }
            if cleanup.isSupported, cleanup.enabled {
                SettingsNote(cleanup.isPaused
                    ? "Your choices are saved. Cleanup resumes when you click Resume Cleanup or reopen MenuWatt."
                    : "Cleanup can affect Focus, media controls and the clock. Pause restores system controls and may reveal all icons.")
            }
        }
        .padding(14)
        .background(SettingsTheme.inset, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(SettingsTheme.rule) }
    }

    private func shortcut(_ keys: String, label: String) -> some View {
        HStack(spacing: 5) {
            Text(keys).font(.system(size: 11, design: .monospaced))
            Text(label).font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
    }

    private func cleanupRow(_ entry: MenuBarCleanupEntry) -> some View {
        HStack(spacing: 8) {
            if let url = entry.bundleURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable().frame(width: 18, height: 18).accessibilityHidden(true)
            } else {
                Image(systemName: entry.symbol == "bluetooth" ? "antenna.radiowaves.left.and.right" : entry.symbol)
                    .frame(width: 18)
                    .foregroundStyle(.secondary).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).lineLimit(1)
                if entry.isMenuBarHelper {
                    Text("Menu bar helper").font(.caption2).foregroundStyle(.secondary)
                } else if !entry.isRunning {
                    Text("Not running · saved choice").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .help(entry.bundleID ?? entry.title)
            Spacer()
            Picker("", selection: Binding(
                get: { cleanup.section(for: entry.id) },
                set: { cleanup.setSection($0, for: entry.id) }
            )) {
                ForEach(MenuBarItemSection.allCases, id: \.rawValue) { section in
                    Text(section.title).tag(section)
                }
            }
            .labelsHidden().pickerStyle(.menu).frame(width: 122)
            .accessibilityLabel(entry.isMenuBarHelper ? "\(entry.title) menu bar helper" : entry.title)
            .help(entry.bundleID ?? entry.title)
        }
        .frame(minHeight: 32)
        .padding(.vertical, 2)
        .overlay(alignment: .bottom) { SettingsTheme.rule.opacity(0.5).frame(height: 0.5) }
    }
}
