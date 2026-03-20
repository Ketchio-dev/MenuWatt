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

@MainActor
final class AppPreferences: ObservableObject {
    @Published private(set) var launchesAtLogin: Bool
    @Published private(set) var launchAtLoginError: String?

    private let launchAtLoginController: any LaunchAtLoginControlling
    private let logger = MenuWattDiagnostics.preferences

    init(
        launchAtLoginController: any LaunchAtLoginControlling = LaunchAgentController()
    ) {
        self.launchAtLoginController = launchAtLoginController

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
