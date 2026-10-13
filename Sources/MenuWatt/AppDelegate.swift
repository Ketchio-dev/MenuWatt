import AppKit
import SwiftUI

/// Application lifecycle: single-instance guard, accessory policy, deferred
/// cleanup startup and launch-debug hooks.
///
/// Extracted from BoochiApp.swift; behavior unchanged.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var sharedSettingsPanel: SettingsPanel?
    static var sharedPreferences: AppPreferences?
    static var sharedUpdateChecker: UpdateChecker?
    static var sharedMenuBarCleanup: MenuBarCleanupController?

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
        let environment = ProcessInfo.processInfo.environment
        let startup = MenuBarCleanupStartupOptions(environment: environment)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            if let cleanup = AppDelegate.sharedMenuBarCleanup { startup.startCleanup(cleanup) }
            if environment["MENUWATT_OPEN_CLEANUP_SETTINGS"] == "1" {
                AppDelegate.sharedSettingsPanel?.showMenuBarCleanup()
            }
        }
        LaunchDebugBehavior(environment: ProcessInfo.processInfo.environment).apply(
            openSettings: {
                AppDelegate.sharedSettingsPanel?.show()
            },
            terminateApp: {
                NSApp.terminate(nil)
            }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppDelegate.sharedMenuBarCleanup?.stop()
    }
}

struct LaunchDebugBehavior {
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
