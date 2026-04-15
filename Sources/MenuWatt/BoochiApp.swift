import AppKit
import SwiftUI
import MenuWattCore

private enum MenuWattLayout {
    static let menuPanelWidth: CGFloat = 340
}

@main
struct MenuWattApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor: PowerMonitor
    @StateObject private var preferences: AppPreferences
    @StateObject private var updateChecker: UpdateChecker

    init() {
        let prefs = AppPreferences()
        let monitor = PowerMonitor()
        monitor.batteryTransitionHandler = { [weak prefs] previous, next in
            guard let prefs else { return }
            NotificationDispatcher.evaluate(previous: previous, next: next, preferences: prefs)
        }
        monitor.start()
        _monitor = StateObject(wrappedValue: monitor)
        _preferences = StateObject(wrappedValue: prefs)

        let checker = UpdateChecker()
        _updateChecker = StateObject(wrappedValue: checker)

        AppDelegate.sharedPreferences = prefs
        AppDelegate.sharedUpdateChecker = checker
        AppDelegate.sharedSettingsPanel = SettingsPanel(preferences: prefs, updateChecker: checker)

        NotificationManager.shared.requestAuthorizationIfNeeded()
        AppDelegate.scheduleStartupUpdateCheck(preferences: prefs, checker: checker)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(monitor: monitor, preferences: preferences)
        } label: {
            MenuBarLabel(monitor: monitor, preferences: preferences)
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

// MARK: - Menu Bar Label

private struct MenuBarLabel: View {
    @ObservedObject var monitor: PowerMonitor
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        HStack(spacing: 4) {
            if preferences.showsSprite {
                Image(nsImage: monitor.currentFrame)
            }

            if let text = indicatorText {
                Text(text)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
            }
        }
        .help(BoochiPresentation.tooltip(for: monitor.snapshot))
        .onAppear {
            monitor.setRefreshInterval(preferences.refreshInterval.seconds)
        }
        .onChange(of: preferences.refreshInterval) { newValue in
            monitor.setRefreshInterval(newValue.seconds)
        }
    }

    private var indicatorText: String? {
        switch preferences.menuBarIndicator {
        case .power:
            return monitor.snapshot.menuBarPowerText
        case .battery:
            guard monitor.snapshot.state != .unavailable else { return nil }
            return "\(monitor.snapshot.percentage)%"
        case .cpu:
            guard monitor.systemSnapshot.cpu.isAvailable else { return nil }
            return String(format: "%.0f%%", monitor.systemSnapshot.cpu.totalUsage)
        case .temperature:
            guard let celsius = monitor.snapshot.temperatureCelsius else { return nil }
            return String(format: "%.0f°C", celsius)
        case .gpu:
            guard monitor.systemSnapshot.gpu.isAvailable else { return nil }
            return String(format: "%.0f%%", monitor.systemSnapshot.gpu.utilizationPercent)
        case .network:
            guard monitor.systemSnapshot.network.isAvailable else { return nil }
            let total = monitor.systemSnapshot.network.downloadBytesPerSecond
                + monitor.systemSnapshot.network.uploadBytesPerSecond
            return Formatters.bytesPerSecond(total)
        case .fan:
            guard let fan = monitor.systemSnapshot.fan.fans.first else { return nil }
            return String(format: "%.0f RPM", fan.rpm)
        }
    }
}

// MARK: - Menu Bar Content

private struct MenuBarContentView: View {
    @ObservedObject var monitor: PowerMonitor
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        MonitorPanelView(
            battery: monitor.snapshot,
            system: monitor.systemSnapshot,
            processes: monitor.processSnapshot,
            sprite: monitor.currentFrame,
            visibleSections: preferences.visibleDashboardSections
        )
        .frame(width: MenuWattLayout.menuPanelWidth)

        Divider()

        MenuBarActionsView(
            onOpenSettings: {
                MenuBarPanelDismisser.dismiss()
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
    static var sharedUpdateChecker: UpdateChecker?

    static func scheduleStartupUpdateCheck(preferences: AppPreferences, checker: UpdateChecker) {
        guard preferences.autoCheckForUpdates else { return }
        let throttle: TimeInterval = 24 * 60 * 60
        if let last = preferences.lastUpdateCheck, Date().timeIntervalSince(last) < throttle {
            return
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            if let release = await checker.check() {
                NotificationManager.shared.notify(
                    kind: .updateAvailable,
                    title: "MenuWatt Update Available",
                    body: "Version \(release.tagName) is available on GitHub.",
                    userInfo: ["url": release.htmlURL.absoluteString]
                )
            }
            preferences.lastUpdateCheck = Date()
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier ?? "com.junsu.menuwatt"
        let duplicates = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != myPID }
        if !duplicates.isEmpty {
            NSApp.terminate(nil)
        }
    }

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

@MainActor
private enum MenuBarPanelDismisser {
    static func dismiss() {
        for window in NSApp.windows {
            let className = String(describing: type(of: window))
            if className.contains("MenuBarExtra") || className.contains("NSStatusBarWindow") {
                window.orderOut(nil)
            }
        }
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
