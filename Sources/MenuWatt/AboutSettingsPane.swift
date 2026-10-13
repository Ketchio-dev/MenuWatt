import AppKit
import SwiftUI
import MenuWattCore

struct AboutSettingsPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsPaneTitle(title: "About", subtitle: "A small utility for a clearer view of your Mac.")
            AboutHero()

            SettingsCard(title: "Support & Contact", systemImage: "bubble.left.and.bubble.right") {
                SettingsNote("Questions, bug reports or feature requests? Reach the developer on Discord.")

                HStack(spacing: 10) {
                    SupportLinkButton(
                        title: "Discord",
                        systemImage: "bubble.left.and.bubble.right.fill",
                        url: URL(string: "https://discord.gg/Cc2RGrN7dh")!
                    )
                }
            }
        }
    }
}

struct AboutHero: View {
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: appIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("MenuWatt")
                    .font(.system(size: 22, weight: .bold))
                Text("Version \(versionString) (\(buildString))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("Live power, battery and system metrics, right in your macOS menu bar.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
    }

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildString: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private var appIconImage: NSImage {
        if let icon = NSImage(named: NSImage.applicationIconName), icon.size.width > 0 {
            return icon
        }
        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }
}

struct SupportLinkButton: View {
    let title: String
    let systemImage: String
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(SettingsActionStyle())
    }
}
