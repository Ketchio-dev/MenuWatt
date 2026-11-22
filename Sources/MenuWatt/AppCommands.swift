import SwiftUI

/// The app menu commands: settings entry points plus pause/reveal/restore.
///
/// Extracted from BoochiApp.swift; titles, shortcuts and enablement unchanged.
struct AppCommands: Commands {
    @ObservedObject var cleanup: MenuBarCleanupController

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Button("Settings…") {
                AppDelegate.sharedSettingsPanel?.show()
            }
            .keyboardShortcut(",", modifiers: .command)
            Button("Menu Bar Cleanup…") {
                AppDelegate.sharedSettingsPanel?.showMenuBarCleanup()
            }
            Button(cleanup.isPaused ? "Resume Menu Bar Cleanup" : "Pause Menu Bar Cleanup") {
                if cleanup.isPaused { cleanup.resumeCleanup() } else { cleanup.pauseCleanup() }
            }
            .disabled(!cleanup.enabled || !cleanup.isSupported)
            .help("Pausing may reveal Always Hidden and activity controls. Saved choices are kept; resume manually.")
            Button("Show / Collapse Menu Bar Icons") { cleanup.toggleHiddenItems() }
                .keyboardShortcut("m", modifiers: [.control, .option, .command])
                .disabled(!cleanup.canRevealItems)
            Button("Restore System Menu Bar") { cleanup.restoreSystemMenuBar() }
                .keyboardShortcut("r", modifiers: [.control, .option, .command])
                .disabled(!cleanup.enabled)
        }
    }
}
