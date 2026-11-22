import AppKit
import Foundation
import Testing
@testable import MenuWatt
@testable import MenuWattCore

@Suite(.serialized)
@MainActor
struct MenuBarCleanupStartupTests {
    @Test
    func onlyExactOptInStartsPaused() {
        #expect(!MenuBarCleanupStartupOptions(environment: [:]).startsPaused)
        #expect(!MenuBarCleanupStartupOptions(environment: ["menuwatt_start_cleanup_paused": "1"]).startsPaused)
        for value in ["1", "0", "", "true", " 1", "1 "] {
            #expect(MenuBarCleanupStartupOptions(environment: ["MENUWATT_START_CLEANUP_PAUSED": value])
                .startsPaused == (value == "1"))
        }
    }

    @Test
    func ordinaryStartupStillAppliesSavedChoicesWithoutWrites() throws {
        let fake = StartupRuntime()
        let cleanup = fake.controller()
        defer { fake.dispose(cleanup) }
        let saved = fake.domainValue
        let writes = fake.defaults.writes
        MenuBarCleanupStartupOptions(environment: [:]).startCleanup(cleanup)
        #expect(!cleanup.isPaused)
        #expect(cleanup.canRevealItems)
        #expect(fake.sessions.count == 1)
        let plan = try #require(fake.plans.last)
        #expect(!plan.allowedSystemItems.contains(5))
        #expect(!plan.allowedBundles.contains("com.example.startup.hidden"))
        #expect(plan.allowedBundles.contains("com.example.startup.visible"))
        let completion = try #require(fake.completions.last)
        completion(nil)
        #expect(cleanup.status == "Menu bar cleanup is active.")
        cleanup.start(paused: true) // Launch options never affect an existing run.
        #expect(!cleanup.isPaused)
        #expect(fake.sessions.count == 1)
        #expect(fake.domainValue == saved)
        #expect(fake.defaults.writes == writes)
    }

    @Test
    func pausedStartupPrecedesFirstRefreshAndDuplicateStartCannotResume() {
        let fake = StartupRuntime()
        let cleanup = fake.controller()
        defer { fake.dispose(cleanup) }
        let saved = fake.domainValue
        let writes = fake.defaults.writes
        var pauseAtRefresh: [Bool] = []
        fake.onRead = { [weak cleanup] in pauseAtRefresh.append(cleanup?.isPaused == true) }
        MenuBarCleanupStartupOptions(environment: ["MENUWATT_START_CLEANUP_PAUSED": "1"])
            .startCleanup(cleanup)
        #expect(pauseAtRefresh == [true])
        #expect(cleanup.isPaused && cleanup.enabled)
        #expect(!cleanup.canRevealItems)
        #expect(cleanup.hotKeysAvailable) // Restore shortcut remains available.
        #expect(!cleanup.entries.isEmpty)
        #expect(fake.sessions.isEmpty)
        cleanup.start()
        cleanup.start(paused: true)
        #expect(pauseAtRefresh == [true])
        #expect(cleanup.isPaused)
        #expect(fake.sessions.isEmpty)
        #expect(fake.domainValue == saved)
        #expect(fake.defaults.writes == writes)
    }

    @Test
    func editsRefreshAndWakeRemainPausedUntilExplicitResume() async throws {
        let fake = StartupRuntime()
        let cleanup = fake.controller()
        defer { fake.dispose(cleanup) }
        cleanup.start(paused: true)
        cleanup.keepActivityControlsHidden = false
        cleanup.setSection(.alwaysHidden, for: "app:com.example.startup.hidden")
        cleanup.setSection(.hidden, for: "system:0")
        let choices = cleanup.configuration
        let saved = fake.domainValue
        let writes = fake.defaults.writes
        cleanup.refresh()
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            let reads = fake.reads
            fake.workspace.post(name: name, object: nil)
            try await waitFor { fake.reads > reads }
        }
        let reads = fake.reads
        fake.application.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        try await waitFor { fake.reads > reads }
        fake.workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await waitFor { !cleanup.hotKeysAvailable }
        cleanup.resumeCleanup() // Cannot apply while asleep.
        #expect(cleanup.isPaused)
        fake.workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await waitFor { cleanup.hotKeysAvailable && fake.reads > reads + 1 }
        cleanup.toggleHiddenItems()
        cleanup.showAllItems()
        let keys = try #require(fake.hotKeys.last)
        keys(1)
        #expect(cleanup.isPaused)
        #expect(cleanup.revealMode == .collapsed)
        #expect(fake.sessions.isEmpty)
        #expect(fake.domainValue == saved)
        #expect(fake.defaults.writes == writes)

        fake.apps.append(.init(bundleID: "com.example.startup.latest", title: "Latest",
            bundleURL: URL(fileURLWithPath: "/StartupFixtures/Latest.app"), isProhibited: false))
        cleanup.resumeCleanup()
        #expect(!cleanup.isPaused)
        #expect(fake.sessions.count == 1)
        let expected = MenuBarCleanupPolicy.plan(configuration: choices,
            runningBundleIDs: Set(fake.apps.map(\.bundleID)),
            ownBundleID: Bundle.main.bundleIdentifier ?? "com.junsu.menuwatt", reveal: .collapsed)
        #expect(fake.plans.last == expected)
        #expect(fake.plans.last?.allowedBundles.contains("com.example.startup.latest") == true)
        #expect(fake.domainValue == saved)
        #expect(fake.defaults.writes == writes)
        cleanup.resumeCleanup()
        #expect(fake.sessions.count == 1)
    }

    @Test
    func restoreFromPausedStartupDisablesOnlySavedOptIn() throws {
        let fake = StartupRuntime()
        let cleanup = fake.controller()
        defer { fake.dispose(cleanup) }
        var saved = fake.defaults.persistentDomain(forName: fake.domain)!
        cleanup.start(paused: true)
        let keys = try #require(fake.hotKeys.last)
        keys(2)
        saved["menuBarCleanup.enabled"] = false
        #expect(!cleanup.enabled && !cleanup.isPaused)
        #expect(fake.sessions.isEmpty)
        #expect(fake.domainValue == saved as NSDictionary)
        let writes = fake.defaults.writes
        keys(1)
        keys(2)
        cleanup.resumeCleanup()
        #expect(fake.sessions.isEmpty)
        #expect(fake.defaults.writes == writes)
    }

    @Test
    func stopClearsPauseAndNormalRestartOrRelaunchUsesSavedOptIn() {
        let fake = StartupRuntime()
        let cleanup = fake.controller()
        defer { fake.dispose(cleanup) }
        let saved = fake.domainValue
        let writes = fake.defaults.writes
        cleanup.start(paused: true)
        cleanup.stop()
        #expect(!cleanup.isPaused && cleanup.enabled)
        cleanup.start()
        #expect(!cleanup.isPaused)
        #expect(fake.sessions.count == 1)
        cleanup.stop()
        let relaunched = fake.controller()
        defer { relaunched.stop() }
        relaunched.start()
        #expect(!relaunched.isPaused)
        #expect(fake.sessions.count == 2)
        #expect(fake.domainValue == saved)
        #expect(fake.defaults.writes == writes)
    }

    @Test
    func disabledAndUnsupportedStartupDoNotLatchPauseOrWrite() {
        for (enabled, supported) in [(false, true), (true, false)] {
            let fake = StartupRuntime(enabled: enabled, supported: supported)
            let cleanup = fake.controller()
            defer { fake.dispose(cleanup) }
            let saved = fake.domainValue
            let writes = fake.defaults.writes
            cleanup.start(paused: true)
            cleanup.refresh()
            cleanup.resumeCleanup()
            #expect(!cleanup.isPaused)
            #expect(fake.sessions.isEmpty)
            #expect(fake.hotKeys.isEmpty)
            #expect(fake.domainValue == saved)
            #expect(fake.defaults.writes == writes)
            if supported {
                cleanup.enabled = true
                #expect(!cleanup.isPaused)
                #expect(fake.sessions.count == 1)
            }
        }
    }

    @Test
    func retiredActivationAndHotKeysCannotChangePausedRestart() throws {
        let fake = StartupRuntime()
        let cleanup = fake.controller()
        defer { fake.dispose(cleanup) }
        cleanup.start()
        let completion = try #require(fake.completions.last)
        let keys = try #require(fake.hotKeys.last)
        cleanup.stop()
        cleanup.start(paused: true)
        let saved = fake.domainValue
        completion(nil)
        completion(NSError(domain: "StartupTest", code: 1))
        keys(1)
        keys(2)
        #expect(cleanup.isPaused && cleanup.enabled)
        #expect(cleanup.errorMessage == nil)
        #expect(cleanup.revealMode == .collapsed)
        #expect(fake.sessions.count == 1)
        #expect(fake.sessions[0].invalidations == 1)
        #expect(fake.domainValue == saved)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while !condition(), clock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(condition(), "Fake notification was not processed within the bound")
    }
}

private final class StartupDefaults: UserDefaults, @unchecked Sendable {
    private(set) var writes = 0
    override func set(_ value: Any?, forKey key: String) { writes += 1; super.set(value, forKey: key) }
    override func set(_ value: Bool, forKey key: String) { writes += 1; super.set(value, forKey: key) }
}

@MainActor
private final class StartupSession: MenuBarCleanupSession {
    var invalidations = 0
    func invalidate() { invalidations += 1 }
}

@MainActor
private final class StartupRuntime {
    let domain = "MenuWatt.StartupTests.\(UUID().uuidString)"
    let defaults: StartupDefaults
    let workspace = NotificationCenter()
    let application = NotificationCenter()
    let supported: Bool
    var reads = 0
    var onRead: (() -> Void)?
    var sessions: [StartupSession] = []
    var plans: [MenuBarVisibilityPlan] = []
    var completions: [@MainActor (Error?) -> Void] = []
    var hotKeys: [@MainActor (UInt) -> Void] = []
    var apps = ["hidden", "visible"].map {
        MenuBarCleanupApp(bundleID: "com.example.startup.\($0)", title: $0,
            bundleURL: URL(fileURLWithPath: "/StartupFixtures/\($0).app"), isProhibited: false)
    }

    init(enabled: Bool = true, supported: Bool = true) {
        self.supported = supported
        defaults = StartupDefaults(suiteName: domain)!
        defaults.setPersistentDomain([
            "menuBarCleanup.enabled": enabled, "menuBarCleanup.hideActivityControls": true,
            "menuBarCleanup.autoRehide": false, "menuBarCleanup.revealOnHover": false,
            "menuBarCleanup.sections": ["system:5": "hidden", "app:com.example.startup.hidden": "hidden"],
            "unrelated.setting": ["keep": "original"]
        ], forName: domain)
    }

    var domainValue: NSDictionary { (defaults.persistentDomain(forName: domain) ?? [:]) as NSDictionary }

    func controller() -> MenuBarCleanupController {
        MenuBarCleanupController(defaults: defaults, runtime: .init(isSupported: supported,
            makeSession: { [self] plan, completion in
                let session = StartupSession()
                sessions.append(session); plans.append(plan); completions.append(completion)
                return session
            }, makeHotKeys: { [self] handler in hotKeys.append(handler); return NSObject() },
            runningApps: { [self] in reads += 1; onRead?(); return apps },
            workspaceNotifications: workspace, applicationNotifications: application,
            refreshDelay: .milliseconds(10), activationTimeout: .seconds(2)))
    }

    func dispose(_ cleanup: MenuBarCleanupController) {
        cleanup.stop()
        onRead = nil
        defaults.removePersistentDomain(forName: domain)
    }
}
