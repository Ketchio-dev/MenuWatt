import AppKit
import CMenuBar
import MenuWattCore

@MainActor
protocol MenuBarCleanupSession: AnyObject {
    func invalidate()
}

extension MWMenuBarVisibility: MenuBarCleanupSession {}

/// Keeps lifecycle tests away from the real menu bar, preferences and hotkeys.
@MainActor
struct MenuBarCleanupRuntime {
    var isSupported: Bool
    var makeSession: (MenuBarVisibilityPlan, @escaping @MainActor (Error?) -> Void) -> (any MenuBarCleanupSession)?
    var makeHotKeys: (@escaping @MainActor (UInt) -> Void) -> AnyObject?
    var runningApps: () -> [MenuBarCleanupApp]
    var workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter
    var applicationNotifications: NotificationCenter = .default
    var refreshDelay: Duration = .milliseconds(600)
    var activationTimeout: Duration = .seconds(5)
    var rehideDelay: Duration = .seconds(15)
    var hoverSnapshot: () -> MenuBarHoverSnapshot = {
        .init(location: .zero, screenFrames: [], windows: [])
    }

    static var live: Self {
        let supported: Bool
        if #available(macOS 27, *) {
            supported = MWMenuBarRuntimeAvailable()
        } else {
            supported = false
        }
        return Self(
            isSupported: supported,
            makeSession: { plan, completion in
                MWMenuBarVisibility(systemItems: plan.allowedSystemItems.map(NSNumber.init(value:)),
                                    bundleIdentifiers: plan.allowedBundles) { error in
                    // The bridge guarantees a main-queue callback; the task also
                    // lets initialization finish before a synchronous failure.
                    Task { @MainActor in completion(error) }
                }
            },
            makeHotKeys: { handler in
                MWMenuBarHotKeys { action in
                    Task { @MainActor in handler(action) }
                }
            },
            runningApps: {
                NSWorkspace.shared.runningApplications.compactMap { app in
                    guard let id = app.bundleIdentifier else { return nil }
                    return MenuBarCleanupApp(bundleID: id, title: app.localizedName ?? id,
                        bundleURL: app.bundleURL, isProhibited: app.activationPolicy == .prohibited,
                        isAccessory: app.activationPolicy == .accessory)
                }
            },
            hoverSnapshot: { .live() }
        )
    }
}

struct MenuBarCleanupApp {
    let bundleID: String
    let title: String
    let bundleURL: URL?
    let isProhibited: Bool
    var isAccessory = false

    var isMenuBarHelper: Bool {
        isAccessory && bundleURL?.path.contains(".app/Contents/Library/LoginItems/") == true
    }

    var catalogTitle: String {
        guard isMenuBarHelper, let path = bundleURL?.path,
              let range = path.range(of: ".app/Contents/Library/LoginItems/") else { return title }
        return URL(fileURLWithPath: String(path[..<range.lowerBound]) + ".app")
            .deletingPathExtension().lastPathComponent
    }

    var isCatalogCandidate: Bool {
        guard !isProhibited, let bundleURL, bundleURL.pathExtension == "app",
              !bundleURL.path.hasPrefix("/System/Library/") else { return false }
        // Login-item apps can own status items under their own bundle IDs
        // (e.g. Passwords). Other embedded helpers are usually renderers/XPC UI.
        return !bundleURL.path.contains("/Contents/") || isMenuBarHelper
    }
}
