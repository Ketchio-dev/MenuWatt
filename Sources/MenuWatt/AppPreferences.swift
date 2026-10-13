import Foundation
import MenuWattCore

enum MenuBarIndicator: String, CaseIterable, Identifiable, Sendable {
    case power
    case battery
    case cpu
    case temperature
    case gpu
    case network
    case fan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .power: return "Power (W)"
        case .battery: return "Battery (%)"
        case .cpu: return "CPU (%)"
        case .temperature: return "Temperature (°C)"
        case .gpu: return "GPU (%)"
        case .network: return "Network (B/s)"
        case .fan: return "Fan (RPM)"
        }
    }
}

enum DashboardSection: String, CaseIterable, Identifiable, Sendable {
    case battery
    case cpu
    case memory
    case gpu
    case fan
    case network
    case storage
    case processes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .battery: return "Battery"
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .gpu: return "GPU"
        case .fan: return "Fans"
        case .network: return "Network"
        case .storage: return "Storage"
        case .processes: return "Top Energy Processes"
        }
    }

    var symbolName: String {
        switch self {
        case .battery: return "battery.100"
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .gpu: return "display"
        case .fan: return "fan"
        case .network: return "network"
        case .storage: return "internaldrive"
        case .processes: return "bolt"
        }
    }
}

enum MenuBarRefreshInterval: Int, CaseIterable, Identifiable, Sendable {
    case oneSecond = 1
    case threeSeconds = 3
    case tenSeconds = 10

    var id: Int { rawValue }

    var seconds: TimeInterval { TimeInterval(rawValue) }

    var title: String {
        switch self {
        case .oneSecond: return "1 second"
        case .threeSeconds: return "3 seconds"
        case .tenSeconds: return "10 seconds"
        }
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    private enum Keys {
        static let menuBarIndicator = "menuBarIndicator"
        static let refreshInterval = "refreshIntervalSeconds"
        static let showsSprite = "showsSprite"
        static let showsGraphs = "showsGraphs"
        static let notifyChargeComplete = "notifyChargeComplete"
        static let notifyLowBattery = "notifyLowBattery"
        static let lowBatteryThreshold = "lowBatteryThreshold"
        static let autoCheckForUpdates = "autoCheckForUpdates"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let visibleDashboardSections = "visibleDashboardSections"
        static let knownDashboardSections = "knownDashboardSections"
    }

    /// Sections that shipped before per-section visibility tracking existed. Used
    /// as the migration baseline so sections added later default to visible.
    private static let legacyKnownSections: Set<DashboardSection> = [.battery, .cpu, .memory, .storage]

    @Published private(set) var launchesAtLogin: Bool
    @Published private(set) var launchAtLoginError: String?
    @Published var menuBarIndicator: MenuBarIndicator {
        didSet {
            guard oldValue != menuBarIndicator else { return }
            defaults.set(menuBarIndicator.rawValue, forKey: Keys.menuBarIndicator)
        }
    }
    @Published var refreshInterval: MenuBarRefreshInterval {
        didSet {
            guard oldValue != refreshInterval else { return }
            defaults.set(refreshInterval.rawValue, forKey: Keys.refreshInterval)
        }
    }
    @Published var showsSprite: Bool {
        didSet {
            guard oldValue != showsSprite else { return }
            defaults.set(showsSprite, forKey: Keys.showsSprite)
        }
    }
    @Published var showsGraphs: Bool {
        didSet {
            guard oldValue != showsGraphs else { return }
            defaults.set(showsGraphs, forKey: Keys.showsGraphs)
        }
    }
    @Published var notifyChargeComplete: Bool {
        didSet {
            guard oldValue != notifyChargeComplete else { return }
            defaults.set(notifyChargeComplete, forKey: Keys.notifyChargeComplete)
        }
    }
    @Published var notifyLowBattery: Bool {
        didSet {
            guard oldValue != notifyLowBattery else { return }
            defaults.set(notifyLowBattery, forKey: Keys.notifyLowBattery)
        }
    }
    @Published var lowBatteryThreshold: Int {
        didSet {
            guard oldValue != lowBatteryThreshold else { return }
            defaults.set(lowBatteryThreshold, forKey: Keys.lowBatteryThreshold)
        }
    }
    @Published var autoCheckForUpdates: Bool {
        didSet {
            guard oldValue != autoCheckForUpdates else { return }
            defaults.set(autoCheckForUpdates, forKey: Keys.autoCheckForUpdates)
        }
    }
    @Published var lastUpdateCheck: Date? {
        didSet {
            defaults.set(lastUpdateCheck, forKey: Keys.lastUpdateCheck)
        }
    }
    @Published var visibleDashboardSections: Set<DashboardSection> {
        didSet {
            guard oldValue != visibleDashboardSections else { return }
            defaults.set(visibleDashboardSections.map(\.rawValue), forKey: Keys.visibleDashboardSections)
        }
    }

    func isDashboardSectionVisible(_ section: DashboardSection) -> Bool {
        visibleDashboardSections.contains(section)
    }

    func setDashboardSection(_ section: DashboardSection, visible: Bool) {
        if visible {
            visibleDashboardSections.insert(section)
        } else {
            visibleDashboardSections.remove(section)
        }
    }

    private let launchAtLoginController: any LaunchAtLoginControlling
    private let defaults: UserDefaults
    private let logger = MenuWattDiagnostics.preferences

    init(
        launchAtLoginController: any LaunchAtLoginControlling = LaunchAgentController(),
        defaults: UserDefaults = .standard
    ) {
        self.launchAtLoginController = launchAtLoginController
        self.defaults = defaults

        var initialError: String?
        do {
            try self.launchAtLoginController.refreshConfigurationIfNeeded()
        } catch {
            initialError = Self.launchAtLoginErrorMessage(
                action: "Failed to refresh Launch at Login",
                error: error
            )
        }

        self.launchesAtLogin = launchAtLoginController.isEnabled
        self.launchAtLoginError = initialError

        let storedIndicator = defaults.string(forKey: Keys.menuBarIndicator)
            .flatMap(MenuBarIndicator.init(rawValue:)) ?? .power
        self.menuBarIndicator = storedIndicator

        let storedIntervalRaw = defaults.object(forKey: Keys.refreshInterval) as? Int
        self.refreshInterval = storedIntervalRaw
            .flatMap(MenuBarRefreshInterval.init(rawValue:)) ?? .oneSecond

        if defaults.object(forKey: Keys.showsSprite) == nil {
            self.showsSprite = true
        } else {
            self.showsSprite = defaults.bool(forKey: Keys.showsSprite)
        }

        self.showsGraphs = defaults.object(forKey: Keys.showsGraphs) == nil
            ? true
            : defaults.bool(forKey: Keys.showsGraphs)

        self.notifyChargeComplete = defaults.object(forKey: Keys.notifyChargeComplete) == nil
            ? false
            : defaults.bool(forKey: Keys.notifyChargeComplete)
        self.notifyLowBattery = defaults.object(forKey: Keys.notifyLowBattery) == nil
            ? false
            : defaults.bool(forKey: Keys.notifyLowBattery)
        self.lowBatteryThreshold = (defaults.object(forKey: Keys.lowBatteryThreshold) as? Int) ?? 20
        self.autoCheckForUpdates = defaults.object(forKey: Keys.autoCheckForUpdates) == nil
            ? true
            : defaults.bool(forKey: Keys.autoCheckForUpdates)
        self.lastUpdateCheck = defaults.object(forKey: Keys.lastUpdateCheck) as? Date

        if let stored = defaults.array(forKey: Keys.visibleDashboardSections) as? [String] {
            var visible = Set(stored.compactMap(DashboardSection.init(rawValue:)))

            // Sections introduced after the user's preference was last saved are
            // not in the stored set; without this they would stay hidden forever
            // (e.g. GPU/Fans/Network/Top Energy after upgrading an older install).
            let known: Set<DashboardSection>
            if let knownRaw = defaults.array(forKey: Keys.knownDashboardSections) as? [String] {
                known = Set(knownRaw.compactMap(DashboardSection.init(rawValue:)))
            } else {
                known = Self.legacyKnownSections
            }
            visible.formUnion(DashboardSection.allCases.filter { !known.contains($0) })
            self.visibleDashboardSections = visible
            defaults.set(visible.map(\.rawValue), forKey: Keys.visibleDashboardSections)
        } else {
            self.visibleDashboardSections = Set(DashboardSection.allCases)
        }
        defaults.set(DashboardSection.allCases.map(\.rawValue), forKey: Keys.knownDashboardSections)

        if let initialError {
            logger.error("\(initialError, privacy: .public)")
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginController.setEnabled(enabled)
            launchesAtLogin = launchAtLoginController.isEnabled
            launchAtLoginError = nil
            logger.info("Launch at Login set to \(self.launchesAtLogin, privacy: .public)")
        } catch {
            launchesAtLogin = launchAtLoginController.isEnabled
            launchAtLoginError = Self.launchAtLoginErrorMessage(
                action: "Failed to update Launch at Login",
                error: error
            )
            logger.error("\(self.launchAtLoginError ?? "", privacy: .public)")
        }
    }

    func dismissLaunchAtLoginError() {
        launchAtLoginError = nil
    }

    private static func launchAtLoginErrorMessage(action: String, error: any Error) -> String {
        "\(action): \(error.localizedDescription)"
    }
}
