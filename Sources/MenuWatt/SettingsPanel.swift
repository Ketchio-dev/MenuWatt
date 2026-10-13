import AppKit
import SwiftUI
import MenuWattSystem
import MenuWattCore

enum SettingsPanelStyle {
    static let windowSize = NSSize(width: 720, height: 520)
    static let windowTitle = "MenuWatt Settings"
}

/// A standalone settings window for the app.
/// Since menu bar accessory apps cannot use SwiftUI's Settings scene reliably,
/// we host the settings view in a regular NSWindow.
@MainActor
final class SettingsPanel {

    private var window: NSWindow?
    private let preferences: AppPreferences
    private let updateChecker: UpdateChecker
    private let cleanup: MenuBarCleanupController

    init(preferences: AppPreferences, updateChecker: UpdateChecker, cleanup: MenuBarCleanupController) {
        self.preferences = preferences
        self.updateChecker = updateChecker
        self.cleanup = cleanup
    }

    func show() {
        preferences.dismissLaunchAtLoginError()

        if let window, window.isVisible {
            present(window)
            return
        }

        let newWindow = makeWindow()
        self.window = newWindow
        present(newWindow)
    }

    func showMenuBarCleanup() {
        if let window {
            window.contentView = NSHostingView(rootView: SettingsContentView(
                preferences: preferences, updateChecker: updateChecker, cleanup: cleanup, initialPane: .menuBar
            ))
            present(window)
            return
        }
        let newWindow = makeWindow(initialPane: .menuBar)
        self.window = newWindow
        present(newWindow)
    }

    private func present(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func makeWindow(initialPane: SettingsPane = .overview) -> NSWindow {
        let settingsView = SettingsContentView(preferences: preferences, updateChecker: updateChecker,
                                              cleanup: cleanup, initialPane: initialPane)
        let hostingView = NSHostingView(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsPanelStyle.windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = SettingsPanelStyle.windowTitle
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = false
        window.contentView = hostingView
        window.contentMinSize = SettingsPanelStyle.windowSize
        window.center()
        window.isReleasedWhenClosed = false
        return window
    }
}
