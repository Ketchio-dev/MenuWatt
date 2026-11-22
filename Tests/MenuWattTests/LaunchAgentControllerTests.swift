import Foundation
import Testing
@testable import MenuWatt

@Test
func setEnabledWritesAndRemovesLaunchAgentPlist() throws {
    let tempDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let plistURL = tempDirectory.appendingPathComponent("com.menuwatt.launcher.plist")
    let controller = makeController(
        plistURL: plistURL,
        currentExecutablePath: "/Applications/MenuWatt.app/Contents/MacOS/MenuWatt",
        currentBundlePath: "/Applications/MenuWatt.app"
    )

    try controller.setEnabled(true)

    #expect(controller.isEnabled)
    #expect(try readProgramArguments(from: plistURL) == ["/usr/bin/open", "-a", "/Applications/MenuWatt.app"])

    try controller.setEnabled(false)

    #expect(!controller.isEnabled)
    #expect(!FileManager.default.fileExists(atPath: plistURL.path))
}

@Test
func derivedDataBuildsPreferInstalledAppBundleWhenAvailable() throws {
    let tempDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let plistURL = tempDirectory.appendingPathComponent("com.menuwatt.launcher.plist")
    let controller = makeController(
        plistURL: plistURL,
        currentExecutablePath: "/tmp/MenuWatt/.build/debug/MenuWatt",
        currentBundlePath: "/tmp/MenuWatt/.build/debug/MenuWatt.app",
        installedAppBundlePath: "/Applications/MenuWatt.app"
    )

    try controller.setEnabled(true)

    #expect(try readProgramArguments(from: plistURL) == ["/usr/bin/open", "-a", "/Applications/MenuWatt.app"])
}

@Test
func refreshConfigurationRewritesStaleProgramArguments() throws {
    let tempDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let plistURL = tempDirectory.appendingPathComponent("com.menuwatt.launcher.plist")
    try writeLaunchAgentPlist(
        programArguments: ["/usr/bin/open", "-a", "/Applications/OldMenuWatt.app"],
        to: plistURL
    )

    let controller = makeController(
        plistURL: plistURL,
        currentExecutablePath: "/Applications/MenuWatt.app/Contents/MacOS/MenuWatt",
        currentBundlePath: "/Applications/MenuWatt.app"
    )

    try controller.refreshConfigurationIfNeeded()

    #expect(try readProgramArguments(from: plistURL) == ["/usr/bin/open", "-a", "/Applications/MenuWatt.app"])
}

@Test
func previewLoginAgentUsesSeparateIdentityAndNeverRewritesRegularAgent() throws {
    let tempDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: tempDirectory) }
    let regular = LaunchAgentController.Identity(bundleIdentifier: "com.junsu.menuwatt")
    let preview = LaunchAgentController.Identity(bundleIdentifier: "com.junsu.menuwatt.cleanup-preview")
    #expect(regular.label == "com.menuwatt.launcher")
    #expect(preview.label == "com.menuwatt.cleanup-preview.launcher")
    #expect(preview.appName == "MenuWattPreview")
    #expect(preview.bundleIdentifier == "com.junsu.menuwatt.cleanup-preview")
    let regularURL = tempDirectory.appendingPathComponent("\(regular.label).plist")
    let previewURL = tempDirectory.appendingPathComponent("\(preview.label).plist")
    try writeLaunchAgentPlist(programArguments: ["/usr/bin/open", "-a", "/Applications/MenuWatt.app"], to: regularURL)
    let savedRegular = try Data(contentsOf: regularURL)
    let controller = makeController(plistURL: previewURL,
        currentExecutablePath: "/tmp/MenuWatt/.build-app-preview/MenuWattPreview.app/Contents/MacOS/MenuWattPreview",
        currentBundlePath: "/tmp/MenuWatt/.build-app-preview/MenuWattPreview.app",
        installedAppBundlePath: "/Applications/MenuWattPreview.app", legacyPreviewPlistURL: regularURL)
    #expect(!controller.isEnabled)
    try controller.refreshConfigurationIfNeeded()
    #expect(!FileManager.default.fileExists(atPath: previewURL.path))
    try controller.setEnabled(true)
    #expect(try readProgramArguments(from: previewURL) == ["/usr/bin/open", "-a", "/Applications/MenuWattPreview.app"])
    let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: previewURL), format: nil) as! [String: Any]
    #expect(plist["Label"] as? String == preview.label)
    try controller.setEnabled(false)
    #expect(try Data(contentsOf: regularURL) == savedRegular)
}

@Test(arguments: [true, false])
func existingPreviewLoginOptInMovesToItsOwnAgentOrCanBeDisabled(enabled: Bool) throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let legacy = directory.appendingPathComponent("com.menuwatt.launcher.plist")
    let preview = directory.appendingPathComponent("com.menuwatt.cleanup-preview.launcher.plist")
    try writeLaunchAgentPlist(programArguments: ["/usr/bin/open", "-a", "/Applications/MenuWattPreview.app"], to: legacy)
    let controller = makeController(plistURL: preview,
        currentExecutablePath: "/Applications/MenuWattPreview.app/Contents/MacOS/MenuWattPreview",
        currentBundlePath: "/Applications/MenuWattPreview.app", legacyPreviewPlistURL: legacy)
    #expect(controller.isEnabled)
    if enabled { try controller.refreshConfigurationIfNeeded() } else { try controller.setEnabled(false) }
    #expect(controller.isEnabled == enabled)
    #expect(!FileManager.default.fileExists(atPath: legacy.path))
    #expect(FileManager.default.fileExists(atPath: preview.path) == enabled)
    if enabled {
        #expect(try readProgramArguments(from: preview) == ["/usr/bin/open", "-a", "/Applications/MenuWattPreview.app"])
    }
}

@Test
func failedPreviewAgentMigrationKeepsTheExistingOptIn() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let legacy = directory.appendingPathComponent("com.menuwatt.launcher.plist")
    let blocker = directory.appendingPathComponent("not-a-directory")
    try Data("keep".utf8).write(to: blocker)
    try writeLaunchAgentPlist(programArguments: ["/usr/bin/open", "-a", "/Applications/MenuWattPreview.app"], to: legacy)
    let original = try Data(contentsOf: legacy)
    let controller = makeController(plistURL: blocker.appendingPathComponent("preview.plist"),
        currentExecutablePath: "/Applications/MenuWattPreview.app/Contents/MacOS/MenuWattPreview",
        currentBundlePath: "/Applications/MenuWattPreview.app", legacyPreviewPlistURL: legacy)
    #expect(throws: (any Error).self) { try controller.refreshConfigurationIfNeeded() }
    #expect(controller.isEnabled)
    #expect(try Data(contentsOf: legacy) == original)
}

private func makeController(
    plistURL: URL,
    currentExecutablePath: String,
    currentBundlePath: String,
    installedAppBundlePath: String? = nil,
    legacyPreviewPlistURL: URL? = nil
) -> LaunchAgentController {
    LaunchAgentController(
        environment: .init(
            plistURL: plistURL,
            currentExecutablePath: { currentExecutablePath },
            currentBundlePath: { currentBundlePath },
            installedAppBundleURL: {
                installedAppBundlePath.map(URL.init(fileURLWithPath:))
            },
            legacyPreviewPlistURL: legacyPreviewPlistURL
        )
    )
}

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func writeLaunchAgentPlist(programArguments: [String], to plistURL: URL) throws {
    let plist: [String: Any] = [
        "Label": "com.menuwatt.launcher",
        "ProgramArguments": programArguments,
        "RunAtLoad": true,
        "KeepAlive": false,
    ]
    let data = try PropertyListSerialization.data(
        fromPropertyList: plist,
        format: .xml,
        options: 0
    )
    try data.write(to: plistURL, options: .atomic)
}

private func readProgramArguments(from plistURL: URL) throws -> [String]? {
    let data = try Data(contentsOf: plistURL)
    let plist = try #require(
        PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    )
    return plist["ProgramArguments"] as? [String]
}
