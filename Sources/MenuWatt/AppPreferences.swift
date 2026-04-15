import Foundation
import MenuWattCore

protocol LaunchAtLoginControlling {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
    func refreshConfigurationIfNeeded() throws
}

extension LaunchAtLoginControlling {
    func refreshConfigurationIfNeeded() throws {}
}

/// Uses a per-user LaunchAgent plist for direct-distributed builds.
/// This keeps launch-at-login working without requiring an embedded helper app.
struct LaunchAgentController: LaunchAtLoginControlling {
    struct Environment: Sendable {
        let plistURL: URL
        let currentExecutablePath: @Sendable () -> String
        let currentBundlePath: @Sendable () -> String
        let installedAppBundleURL: @Sendable () -> URL?

        static let live = Environment(
            plistURL: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents/\(Constants.label).plist"),
            currentExecutablePath: {
                Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments.first ?? ""
            },
            currentBundlePath: {
                Bundle.main.bundlePath
            },
            installedAppBundleURL: {
                let appURL = URL(fileURLWithPath: "/Applications/MenuWatt.app")
                guard
                    let bundle = Bundle(url: appURL),
                    bundle.bundleIdentifier == Constants.bundleIdentifier
                else {
                    return nil
                }

                return appURL
            }
        )
    }

    private enum Constants {
        static let label = "com.menuwatt.launcher"
        static let bundleIdentifier = "com.junsu.menuwatt"
        static let openCommand = "/usr/bin/open"
    }

    private let environment: Environment

    init(environment: Environment = .live) {
        self.environment = environment
    }

    private var plistURL: URL {
        environment.plistURL
    }

    private var currentRegisteredProgramArguments: [String]? {
        guard
            let data = try? Data(contentsOf: plistURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let arguments = plist["ProgramArguments"] as? [String],
            !arguments.isEmpty
        else {
            return nil
        }

        return arguments
    }

    private var installedAppBundlePath: String? {
        environment.installedAppBundleURL()?.path
    }

    private func shouldPreferInstalledApp(for path: String) -> Bool {
        path.contains("/DerivedData/") || path.contains("/.build")
    }

    private var appBundlePath: String {
        let currentExecutablePath = environment.currentExecutablePath()

        if shouldPreferInstalledApp(for: currentExecutablePath), let installedAppBundlePath {
            return installedAppBundlePath
        }

        return environment.currentBundlePath()
    }

    private var programArguments: [String] {
        [Constants.openCommand, "-a", appBundlePath]
    }

    var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    func refreshConfigurationIfNeeded() throws {
        guard isEnabled else { return }

        let desiredProgramArguments = programArguments
        let registeredProgramArguments = currentRegisteredProgramArguments

        guard registeredProgramArguments != desiredProgramArguments else { return }

        try setEnabled(true)
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            let plist: [String: Any] = [
                "Label": Constants.label,
                "ProgramArguments": programArguments,
                "RunAtLoad": true,
                "KeepAlive": false,
            ]
            let dir = plistURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try data.write(to: plistURL, options: .atomic)
        } else {
            if FileManager.default.fileExists(atPath: plistURL.path) {
                try FileManager.default.removeItem(at: plistURL)
            }
        }
    }
}

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
        static let notifyChargeComplete = "notifyChargeComplete"
        static let notifyLowBattery = "notifyLowBattery"
        static let lowBatteryThreshold = "lowBatteryThreshold"
        static let autoCheckForUpdates = "autoCheckForUpdates"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let visibleDashboardSections = "visibleDashboardSections"
    }

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
            self.visibleDashboardSections = Set(stored.compactMap(DashboardSection.init(rawValue:)))
        } else {
            self.visibleDashboardSections = Set(DashboardSection.allCases)
        }

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
