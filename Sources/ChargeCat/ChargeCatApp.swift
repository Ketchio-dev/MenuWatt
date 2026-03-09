import AppKit
import SwiftUI

@main
struct ChargeCatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = PowerMonitor()

    var body: some Scene {
        MenuBarExtra {
            MonitorPanelView(
                battery: monitor.snapshot,
                system: monitor.systemSnapshot,
                sprite: monitor.currentFrame
            )
            .frame(width: 340)

            Divider()

            HStack(spacing: 8) {
                Button("Refresh") {
                    monitor.refreshNow()
                }
                .keyboardShortcut("r", modifiers: .command)

                Spacer()

                Button("Quit ChargeCat") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: monitor.currentFrame)

                if let menuBarPowerText = monitor.snapshot.menuBarPowerText {
                    Text(menuBarPowerText)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                }
            }
            .help(monitor.snapshot.tooltip)
        }
        .menuBarExtraStyle(.window)

        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
