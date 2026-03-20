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

/// Uses ~/Library/LaunchAgents/ plist to register login item.
/// Works without code signing.
struct LaunchAgentController: LaunchAtLoginControlling {
    private let label = "com.menuwatt.launcher"
    private let bundleIdentifier = "com.junsu.menuwatt"
    private let openCommand = "/usr/bin/open"

    private var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
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

    private var installedAppExecutablePath: String? {
        let appURL = URL(fileURLWithPath: "/Applications/MenuWatt.app")
        guard
            let bundle = Bundle(url: appURL),
            bundle.bundleIdentifier == bundleIdentifier,
            let executablePath = bundle.executablePath
        else {
            return nil
        }

        return executablePath
    }

    private func shouldPreferInstalledApp(for path: String) -> Bool {
        path.contains("/DerivedData/") || path.contains("/.build")
    }

    private var appBundlePath: String {
        let currentExecutablePath = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments.first ?? ""

        if shouldPreferInstalledApp(for: currentExecutablePath), let installedAppExecutablePath {
            return URL(fileURLWithPath: installedAppExecutablePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .path
        }

        return Bundle.main.bundlePath
    }

    private var programArguments: [String] {
        [openCommand, "-a", appBundlePath]
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
                "Label": label,
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

@MainActor
final class AppPreferences: ObservableObject {
    @Published private(set) var launchesAtLogin: Bool
    @Published private(set) var launchAtLoginError: String?

    private let launchAtLoginController: any LaunchAtLoginControlling
    private let logger = MenuWattDiagnostics.preferences

    init(
        launchAtLoginController: any LaunchAtLoginControlling = LaunchAgentController(),
        userDefaults: UserDefaults = .standard
    ) {
        self.launchAtLoginController = launchAtLoginController
        try? self.launchAtLoginController.refreshConfigurationIfNeeded()
        self.launchesAtLogin = launchAtLoginController.isEnabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginController.setEnabled(enabled)
            launchesAtLogin = launchAtLoginController.isEnabled
            launchAtLoginError = nil
            logger.info("Launch at Login set to \(self.launchesAtLogin, privacy: .public)")
        } catch {
            launchesAtLogin = launchAtLoginController.isEnabled
            launchAtLoginError = "Failed to update Launch at Login: \(error.localizedDescription)"
            logger.error("Failed to update Launch at Login: \(error.localizedDescription, privacy: .public)")
        }
    }

    func dismissLaunchAtLoginError() {
        launchAtLoginError = nil
    }
}
