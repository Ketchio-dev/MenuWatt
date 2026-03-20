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

private func makeController(
    plistURL: URL,
    currentExecutablePath: String,
    currentBundlePath: String,
    installedAppBundlePath: String? = nil
) -> LaunchAgentController {
    LaunchAgentController(
        environment: .init(
            plistURL: plistURL,
            currentExecutablePath: { currentExecutablePath },
            currentBundlePath: { currentBundlePath },
            installedAppBundleURL: {
                installedAppBundlePath.map(URL.init(fileURLWithPath:))
            }
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
