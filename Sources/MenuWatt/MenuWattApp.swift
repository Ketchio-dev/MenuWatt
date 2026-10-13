import AppKit
import SwiftUI
import MenuWattCore

/// App composition root: owns the shared objects and the menu bar scene.
///
/// Extracted from BoochiApp.swift. Object graph construction and scene
/// wiring are unchanged; the delegate, label, dashboard and actions live in
/// their own files.
@main
struct MenuWattApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor: PowerMonitor
    @StateObject private var preferences: AppPreferences
    @StateObject private var updateChecker: UpdateChecker
    @StateObject private var cleanup: MenuBarCleanupController

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
        let cleanup = MenuBarCleanupController()
        _cleanup = StateObject(wrappedValue: cleanup)

        AppDelegate.sharedPreferences = prefs
        AppDelegate.sharedUpdateChecker = checker
        AppDelegate.sharedMenuBarCleanup = cleanup
        AppDelegate.sharedSettingsPanel = SettingsPanel(preferences: prefs, updateChecker: checker, cleanup: cleanup)

        if !(Bundle.main.bundleIdentifier ?? "").hasSuffix(".cleanup-preview") {
            NotificationManager.shared.requestAuthorizationIfNeeded()
            AppDelegate.scheduleStartupUpdateCheck(preferences: prefs, checker: checker)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(monitor: monitor, preferences: preferences, cleanup: cleanup)
        } label: {
            MenuBarLabel(monitor: monitor, preferences: preferences)
        }
        .menuBarExtraStyle(.window)
        .commands {
            AppCommands(cleanup: cleanup)
        }
    }
}
