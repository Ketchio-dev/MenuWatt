import Foundation

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
        var legacyPreviewPlistURL: URL? = nil

        static var live: Environment {
            let identity = Identity(bundleIdentifier: Bundle.main.bundleIdentifier ?? Constants.bundleIdentifier)
            return Environment(
                plistURL: FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/LaunchAgents/\(identity.label).plist"),
                currentExecutablePath: {
                    Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments.first ?? ""
                },
                currentBundlePath: { Bundle.main.bundlePath },
                installedAppBundleURL: {
                    let appURL = URL(fileURLWithPath: "/Applications/\(identity.appName).app")
                    guard let bundle = Bundle(url: appURL),
                          bundle.bundleIdentifier == identity.bundleIdentifier else { return nil }
                    return appURL
                },
                legacyPreviewPlistURL: identity.appName == "MenuWattPreview"
                    ? FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Library/LaunchAgents/com.menuwatt.launcher.plist")
                    : nil
            )
        }
    }

    struct Identity: Sendable {
        let label: String
        let bundleIdentifier: String
        let appName: String

        init(bundleIdentifier: String) {
            let preview = bundleIdentifier == "com.junsu.menuwatt.cleanup-preview"
            self.bundleIdentifier = preview ? bundleIdentifier : Constants.bundleIdentifier
            label = preview ? "com.menuwatt.cleanup-preview.launcher" : "com.menuwatt.launcher"
            appName = preview ? "MenuWattPreview" : "MenuWatt"
        }
    }

    private enum Constants {
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

    /// Older Preview builds used the regular label. Preserve that saved opt-in
    /// only when the old file explicitly launches this Preview, never MenuWatt.
    private var matchingLegacyPreviewURL: URL? {
        guard let url = environment.legacyPreviewPlistURL,
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["Label"] as? String == "com.menuwatt.launcher",
              plist["ProgramArguments"] as? [String] == programArguments else { return nil }
        return url
    }

    var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path) || matchingLegacyPreviewURL != nil
    }

    func refreshConfigurationIfNeeded() throws {
        guard isEnabled else { return }
        if matchingLegacyPreviewURL != nil {
            try setEnabled(true)
            return
        }

        let desiredProgramArguments = programArguments
        let registeredProgramArguments = currentRegisteredProgramArguments

        guard registeredProgramArguments != desiredProgramArguments else { return }

        try setEnabled(true)
    }

    func setEnabled(_ enabled: Bool) throws {
        let legacyPreviewURL = matchingLegacyPreviewURL
        if enabled {
            let plist: [String: Any] = [
                "Label": plistURL.deletingPathExtension().lastPathComponent,
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
        if let legacyPreviewURL {
            // Write the replacement first, so a failed write cannot lose opt-in.
            try FileManager.default.removeItem(at: legacyPreviewURL)
        }
    }
}
