import AppKit
import SwiftUI

private enum MenuWattLayout {
    static let menuPanelWidth: CGFloat = 340
}

@main
struct MenuWattApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor: PowerMonitor
    @StateObject private var preferences: AppPreferences

    init() {
        let monitor = PowerMonitor()
        monitor.start()
        _monitor = StateObject(wrappedValue: monitor)

        let prefs = AppPreferences()
        _preferences = StateObject(wrappedValue: prefs)
        AppDelegate.sharedPreferences = prefs
        AppDelegate.sharedSettingsPanel = SettingsPanel(preferences: prefs)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(monitor: monitor)
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: monitor.currentFrame)

                if let menuBarPowerText = monitor.snapshot.menuBarPowerText {
                    Text(menuBarPowerText)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                }
            }
            .help(BoochiPresentation.tooltip(for: monitor.snapshot))
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Settings…") {
                    AppDelegate.sharedSettingsPanel?.show()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

// MARK: - Menu Bar Content

private struct MenuBarContentView: View {
    @ObservedObject var monitor: PowerMonitor

    var body: some View {
        MonitorPanelView(
            battery: monitor.snapshot,
            system: monitor.systemSnapshot,
            sprite: monitor.currentFrame
        )
        .frame(width: MenuWattLayout.menuPanelWidth)

        Divider()

        MenuBarActionsView(
            onOpenSettings: {
                AppDelegate.sharedSettingsPanel?.show()
            },
            onQuit: {
                monitor.stop()
                NSApp.terminate(nil)
            }
        )
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var sharedSettingsPanel: SettingsPanel?
    static var sharedPreferences: AppPreferences?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        LaunchDebugBehavior(environment: ProcessInfo.processInfo.environment).apply(
            openSettings: {
                AppDelegate.sharedSettingsPanel?.show()
            },
            terminateApp: {
                NSApp.terminate(nil)
            }
        )
    }
}

private struct MenuBarActionsView: View {
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpenSettings) {
                HStack(spacing: 3) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                    Text("Settings")
                }
            }

            Spacer()

            Button("Quit MenuWatt", action: onQuit)
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct LaunchDebugBehavior {
    let shouldOpenSettingsOnLaunch: Bool
    let shouldExitAfterSettingsTest: Bool

    init(environment: [String: String]) {
        self.shouldOpenSettingsOnLaunch = environment["MENUWATT_OPEN_SETTINGS_ON_LAUNCH"] == "1"
        self.shouldExitAfterSettingsTest = environment["MENUWATT_EXIT_AFTER_SETTINGS_TEST"] == "1"
    }

    func apply(openSettings: @escaping @MainActor () -> Void, terminateApp: @escaping @MainActor () -> Void) {
        if shouldOpenSettingsOnLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                openSettings()
            }
        }

        if shouldExitAfterSettingsTest {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                terminateApp()
            }
        }
    }
}
