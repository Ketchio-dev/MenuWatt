import AppKit
import SwiftUI
import MenuWattCore

struct UpdatesSettingsPane: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var updateChecker: UpdateChecker

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsPaneTitle(
                title: "Updates",
                subtitle: "New versions are published on GitHub."
            )

            SettingsCard(title: "Update Check", systemImage: "arrow.triangle.2.circlepath") {
                SettingsRow(label: "Current version") {
                    Text(updateChecker.currentVersion)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                SettingsRow(label: "Check automatically") {
                    Toggle("Check automatically", isOn: $preferences.autoCheckForUpdates)
                        .labelsHidden()
                }

                SettingsRow(label: "Last checked") {
                    Text(lastCheckedText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()
                    Button {
                        Task {
                            _ = await updateChecker.check()
                            preferences.lastUpdateCheck = Date()
                        }
                    } label: {
                        if case .checking = updateChecker.status {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Checking…")
                            }
                        } else {
                            Text("Check Now")
                        }
                    }
                    .buttonStyle(SettingsActionStyle(prominent: true))
                    .disabled(isChecking)
                }
                .padding(.top, 6)
            }

            statusCard
        }
    }

    private var isChecking: Bool {
        if case .checking = updateChecker.status { return true }
        return false
    }

    private var lastCheckedText: String {
        guard let date = preferences.lastUpdateCheck else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    @ViewBuilder
    private var statusCard: some View {
        switch updateChecker.status {
        case .updateAvailable(let release):
            SettingsCard(title: "Update Available", systemImage: "sparkles") {
                Text("Version \(release.tagName) is available.")
                    .font(.system(size: 13, weight: .semibold))
                if let body = release.body, !body.isEmpty {
                    Text(body)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer()
                    Button("Open Release") {
                        NSWorkspace.shared.open(release.htmlURL)
                    }
                    .buttonStyle(SettingsActionStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                }
            }
        case .upToDate:
            SettingsCard(title: "Up to Date", systemImage: "checkmark.seal") {
                Text("You're running the latest version of MenuWatt.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            SettingsCard(title: "Check Failed", systemImage: "exclamationmark.triangle") {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .idle, .checking:
            EmptyView()
        }
    }
}
