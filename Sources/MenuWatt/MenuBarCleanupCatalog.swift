import AppKit
import MenuWattCore

/// A single row in the Menu Bar settings catalog.
struct MenuBarCleanupEntry: Identifiable {
    let id: String
    let title: String
    let bundleID: String?
    let symbol: String
    var isRunning = true
    var isMenuBarHelper = false
    var bundleURL: URL?
}

/// Builds the settings catalog: system icons, running app candidates and
/// saved choices for apps that are not running.
///
/// Extracted from the controller so catalog rules can be read and tested in
/// isolation. Behavior is unchanged: the list contains running app candidates
/// and saved choices, not detected icons.
enum MenuBarCleanupCatalog {
    static let systemItems: [(identifier: Int, title: String, symbol: String)] = [
        (0, "Battery", "battery.100"), (1, "Bluetooth", "bluetooth"),
        (3, "Displays", "display"), (4, "Input Source", "character.cursor.ibeam"),
        (5, "Sound", "speaker.wave.2"), (6, "Wi-Fi", "wifi"),
        (7, "Screen Mirroring", "rectangle.on.rectangle")
    ]

    static func buildEntries(
        apps: [MenuBarCleanupApp],
        sections: [String: MenuBarItemSection],
        runningBundleIDs: Set<String>,
        ownBundleID: String
    ) -> [MenuBarCleanupEntry] {
        var nextEntries = systemItems.map {
            MenuBarCleanupEntry(
                id: MenuBarCleanupPolicy.systemKey($0.identifier),
                title: $0.title, bundleID: nil, symbol: $0.symbol
            )
        }
        var seen: Set<String> = []
        for app in apps {
            let bundleID = app.bundleID
            guard bundleID != ownBundleID, app.isCatalogCandidate,
                  seen.insert(bundleID).inserted else { continue }
            nextEntries.append(MenuBarCleanupEntry(
                id: MenuBarCleanupPolicy.appKey(bundleID),
                title: app.catalogTitle, bundleID: bundleID, symbol: "app",
                isMenuBarHelper: app.isMenuBarHelper, bundleURL: app.bundleURL
            ))
        }
        // Preserve an app's saved assignment even when it isn't running.
        for key in sections.keys where key.hasPrefix("app:") {
            let bundleID = String(key.dropFirst(4))
            guard bundleID != ownBundleID, seen.insert(bundleID).inserted else { continue }
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            let name = url?.deletingPathExtension().lastPathComponent ?? bundleID
            nextEntries.append(MenuBarCleanupEntry(
                id: key, title: name, bundleID: bundleID, symbol: "app",
                isRunning: runningBundleIDs.contains(bundleID), bundleURL: url
            ))
        }
        return nextEntries.sorted {
            if ($0.bundleID == nil) != ($1.bundleID == nil) { return $0.bundleID == nil }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }
}
