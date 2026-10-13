import Foundation

public enum MenuBarItemSection: String, CaseIterable, Sendable {
    case visible, hidden, alwaysHidden

    public var title: String {
        switch self {
        case .visible: "Visible"
        case .hidden: "Hidden"
        case .alwaysHidden: "Always Hidden"
        }
    }
}

public enum MenuBarRevealMode: Sendable {
    case collapsed, hidden, all
}

public struct MenuBarCleanupConfiguration: Equatable, Sendable {
    public var enabled: Bool
    public var keepActivityControlsHidden: Bool
    public var autoRehide: Bool
    public var revealOnHover: Bool
    public var sections: [String: MenuBarItemSection]

    public init(enabled: Bool = false, keepActivityControlsHidden: Bool = true,
                autoRehide: Bool = true, revealOnHover: Bool = false,
                sections: [String: MenuBarItemSection] = [:]) {
        self.enabled = enabled
        self.keepActivityControlsHidden = keepActivityControlsHidden
        self.autoRehide = autoRehide
        self.revealOnHover = revealOnHover
        self.sections = sections
    }
}

public struct MenuBarVisibilityPlan: Equatable, Sendable {
    public let allowedBundles: [String]
    public let allowedSystemItems: [Int]
    public let needsSession: Bool
}

/// Pure policy: revealing apps never restores the large activity pill when
/// keepActivityControlsHidden is enabled, and MenuWatt can never hide itself.
public enum MenuBarCleanupPolicy {
    public static func appKey(_ bundleID: String) -> String { "app:\(bundleID)" }
    public static func systemKey(_ identifier: Int) -> String { "system:\(identifier)" }

    public static func plan(configuration: MenuBarCleanupConfiguration,
                            runningBundleIDs: Set<String>, ownBundleID: String,
                            reveal: MenuBarRevealMode) -> MenuBarVisibilityPlan {
        func isVisible(_ key: String) -> Bool {
            switch configuration.sections[key] ?? .visible {
            case .visible: true
            case .hidden: reveal != .collapsed
            case .alwaysHidden: reveal == .all
            }
        }

        let allBundles = runningBundleIDs.union([ownBundleID])
        let allowed = allBundles.filter { $0 == ownBundleID || isVisible(appKey($0)) }.sorted()
        // Keep the clock and Control Center available as recovery paths.
        let system = (0...8).filter { $0 == 2 || $0 == 8 || isVisible(systemKey($0)) }
        let excludesItems = allowed.count < allBundles.count || system.count < 9
        return MenuBarVisibilityPlan(
            allowedBundles: allowed, allowedSystemItems: system,
            needsSession: configuration.enabled && (configuration.keepActivityControlsHidden || excludesItems)
        )
    }
}
