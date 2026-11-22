import AppKit
import Foundation
import Testing
@testable import MenuWatt
@testable import MenuWattCore

@MainActor
private final class CleanupTestSession: MenuBarCleanupSession {
    var invalidations = 0
    func invalidate() { invalidations += 1 }
}

@MainActor
private final class CleanupTestRuntime {
    var sessions: [CleanupTestSession] = []
    var completions: [@MainActor (Error?) -> Void] = []
    var plans: [MenuBarVisibilityPlan] = []
    var hotKeyHandler: (@MainActor (UInt) -> Void)?
    var apps: [MenuBarCleanupApp] = []
    var supported = true
    var returnsNil = false
    var synchronousError: Error?
    let workspace = NotificationCenter()
    let application = NotificationCenter()
    let domain = "MenuWatt.CleanupLifecycleTests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() { defaults = UserDefaults(suiteName: domain)! }

    var persistentDomain: NSDictionary {
        (defaults.persistentDomain(forName: domain) ?? [:]) as NSDictionary
    }

    func controller(timeout: Duration = .seconds(1), rehide: Duration = .seconds(1),
                    refresh: Duration = .milliseconds(10)) -> MenuBarCleanupController {
        MenuBarCleanupController(defaults: defaults, runtime: .init(
            isSupported: supported,
            makeSession: { [self] plan, completion in
                plans.append(plan)
                completions.append(completion)
                if let synchronousError { completion(synchronousError) }
                if returnsNil { return nil }
                let session = CleanupTestSession()
                sessions.append(session)
                return session
            },
            makeHotKeys: { [self] handler in hotKeyHandler = handler; return NSObject() },
            runningApps: { [self] in apps },
            workspaceNotifications: workspace, applicationNotifications: application,
            refreshDelay: refresh, activationTimeout: timeout, rehideDelay: rehide
        ))
    }

    func cleanup(_ controller: MenuBarCleanupController) {
        controller.stop()
        defaults.removePersistentDomain(forName: domain)
    }
}

private let cleanupFailure = NSError(domain: "MenuWatt.Test", code: 1,
                                     userInfo: [NSLocalizedDescriptionKey: "Activation failed"])

@Test @MainActor
func cleanupRefreshDoesNotClaimPendingActivationSucceeded() {
    let fake = CleanupTestRuntime()
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.enabled = true
    controller.start()
    controller.start()
    controller.refresh()
    #expect(fake.sessions.count == 1)
    #expect(controller.status == "Updating menu bar…")
    fake.completions[0](nil)
    #expect(controller.status == "Menu bar cleanup is active.")
}

@Test @MainActor
func cleanupStaleCompletionCannotAffectReplacementOrRestore() {
    let fake = CleanupTestRuntime()
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.enabled = true
    controller.start()
    controller.setSection(.hidden, for: "system:5")
    #expect(fake.sessions.count == 2)
    #expect(fake.sessions[0].invalidations == 1)
    fake.completions[0](cleanupFailure)
    #expect(controller.errorMessage == nil)
    #expect(controller.status == "Updating menu bar…")
    fake.completions[1](nil)
    controller.restoreSystemMenuBar()
    fake.completions[1](cleanupFailure)
    #expect(fake.sessions[1].invalidations == 1)
    #expect(!controller.enabled)
    #expect(controller.errorMessage == nil)
    #expect(controller.status == "Menu bar cleanup is off.")
    #expect(controller.section(for: "system:5") == .hidden)
}

@Test @MainActor
func cleanupAppLaunchKeepsExistingRestrictionUntilReplacementIsActive() async throws {
    let fake = CleanupTestRuntime()
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    let newApp = MenuBarCleanupApp(bundleID: "com.example.new", title: "New",
        bundleURL: URL(fileURLWithPath: "/Applications/New.app"), isProhibited: false)
    controller.setSection(.alwaysHidden, for: "system:5")
    controller.enabled = true
    controller.start()
    fake.completions[0](nil)
    fake.apps.append(newApp)
    fake.workspace.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
    try await Task.sleep(for: .milliseconds(80))

    try #require(fake.sessions.count == 2)
    #expect(fake.sessions[0].invalidations == 0)
    #expect(fake.plans[1].allowedBundles.contains(newApp.bundleID))
    #expect(!fake.plans[1].allowedSystemItems.contains(5))
    fake.completions[1](nil)
    #expect(fake.sessions[0].invalidations == 1)
    #expect(fake.sessions[1].invalidations == 0)

    // A quit and relaunch of an already allowed app can reuse the restriction.
    fake.apps.removeAll()
    fake.workspace.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    try await Task.sleep(for: .milliseconds(80))
    #expect(!controller.entries.contains { $0.bundleID == newApp.bundleID })
    fake.apps.append(newApp)
    fake.workspace.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
    try await Task.sleep(for: .milliseconds(80))
    #expect(controller.entries.contains { $0.bundleID == newApp.bundleID })
    #expect(fake.sessions.count == 2)
    #expect(fake.sessions[1].invalidations == 0)
}

@Test @MainActor
func cleanupFailedReplacementPreservesConfirmedRestrictionAndCanRetry() {
    let fake = CleanupTestRuntime()
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.enabled = true
    controller.start()
    fake.completions[0](nil)
    controller.setSection(.alwaysHidden, for: "system:5")
    fake.completions[1](cleanupFailure)
    #expect(fake.sessions[0].invalidations == 0)
    #expect(fake.sessions[1].invalidations == 1)
    #expect(controller.errorMessage == "Activation failed")
    #expect(controller.status == "Previous menu bar cleanup is still active.")

    controller.refresh()
    #expect(fake.sessions.count == 3)
    fake.completions[2](nil)
    #expect(controller.errorMessage == nil)
    #expect(fake.sessions[0].invalidations == 1)
    #expect(fake.sessions[2].invalidations == 0)

    controller.setSection(.hidden, for: "system:6")
    #expect(fake.sessions[2].invalidations == 0)
    controller.pauseCleanup()
    fake.completions[3](nil)
    #expect(controller.isPaused)
    #expect(fake.sessions.allSatisfy { $0.invalidations == 1 })
    #expect(controller.errorMessage == nil)
}

@Test @MainActor
func cleanupCanRevertToConfirmedPlanWhileReplacementIsPending() {
    let fake = CleanupTestRuntime()
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.enabled = true
    controller.start()
    fake.completions[0](nil)
    controller.setSection(.hidden, for: "system:5")
    controller.setSection(.visible, for: "system:5")
    fake.completions[1](nil)

    #expect(fake.sessions.count == 2)
    #expect(fake.sessions[0].invalidations == 0)
    #expect(fake.sessions[1].invalidations == 1)
    #expect(controller.status == "Menu bar cleanup is active.")
}

@Test @MainActor
func cleanupActivationFailureAndNilFactoryRestoreOriginalMenuBar() {
    let fake = CleanupTestRuntime()
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.enabled = true
    controller.start()
    fake.completions[0](cleanupFailure)
    #expect(fake.sessions[0].invalidations == 1)
    #expect(controller.errorMessage == "Activation failed")
    fake.returnsNil = true
    controller.refresh()
    #expect(controller.errorMessage?.contains("unavailable") == true)
    fake.completions[1](nil)
    #expect(controller.status == "The original menu bar has been restored.")
    #expect(controller.errorMessage != nil)
}

@Test @MainActor
func cleanupSynchronousFailureDoesNotRetainFailedSession() {
    let fake = CleanupTestRuntime()
    fake.synchronousError = cleanupFailure
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.enabled = true
    controller.start()
    #expect(fake.sessions[0].invalidations == 1)
    #expect(controller.errorMessage == "Activation failed")
}

@Test @MainActor
func cleanupActivationTimeoutIgnoresLateSuccessAndAllowsRetry() async throws {
    let fake = CleanupTestRuntime()
    let controller = fake.controller(timeout: .milliseconds(20))
    defer { fake.cleanup(controller) }
    controller.enabled = true
    controller.start()
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while controller.errorMessage == nil, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    try #require(controller.errorMessage?.contains("did not finish") == true)
    #expect(fake.sessions[0].invalidations == 1)
    fake.completions[0](nil)
    #expect(controller.status == "The original menu bar has been restored.")
    controller.refresh()
    try #require(fake.completions.count == 2)
    fake.completions[1](nil)
    #expect(controller.errorMessage == nil)
    #expect(controller.status == "Menu bar cleanup is active.")
}

@Test @MainActor
func cleanupStopAndDisabledStateRejectQueuedRevealAndHotKeys() {
    let fake = CleanupTestRuntime()
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.enabled = true
    controller.start()
    let hotkey = fake.hotKeyHandler!
    controller.stop()
    fake.completions[0](nil)
    hotkey(1)
    hotkey(2)
    controller.showAllItems()
    #expect(controller.enabled) // stop does not change saved opt-in
    #expect(!controller.isExpanded)
    #expect(!controller.hotKeysAvailable)
    #expect(controller.status == "Menu bar cleanup is stopped.")
    controller.start()
    controller.restoreSystemMenuBar()
    hotkey(1)
    controller.toggleHiddenItems()
    #expect(!controller.isExpanded)
    #expect(fake.sessions.count == 2)
}

@Test @MainActor
func cleanupAutoCollapseAndRestoreCancelRevealTimer() async throws {
    let fake = CleanupTestRuntime()
    let controller = fake.controller(rehide: .milliseconds(20))
    defer { fake.cleanup(controller) }
    controller.setSection(.alwaysHidden, for: "system:5")
    controller.enabled = true
    controller.start()
    controller.showAllItems()
    fake.completions.last!(nil)
    #expect(controller.status == "All app icons are revealed.")
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while controller.isExpanded, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(!controller.isExpanded)
    #expect(!fake.plans.last!.allowedSystemItems.contains(5))
    controller.showAllItems()
    controller.restoreSystemMenuBar()
    let count = fake.sessions.count
    try await Task.sleep(for: .milliseconds(80))
    #expect(fake.sessions.count == count)
    #expect(controller.status == "Menu bar cleanup is off.")
}

@Test @MainActor
func cleanupSleepReleasesSessionAndWakeReappliesCollapsedOnce() async throws {
    let fake = CleanupTestRuntime()
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.enabled = true
    controller.start()
    controller.showAllItems()
    fake.workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
    try await Task.sleep(for: .milliseconds(30))
    #expect(!controller.isExpanded)
    #expect(fake.sessions.last!.invalidations == 1)
    let count = fake.sessions.count
    controller.refresh()
    #expect(fake.sessions.count == count)
    fake.workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
    fake.workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
    try await Task.sleep(for: .milliseconds(80))
    #expect(fake.sessions.count == count + 1)
    fake.completions[count - 1](cleanupFailure)
    #expect(controller.errorMessage == nil)
    fake.completions.last!(nil)
    #expect(controller.status == "Menu bar cleanup is active.")
    #expect(controller.enabled)
}

@Test @MainActor
func cleanupDisplayChangesForceReapplyButStopCancelsQueuedRefresh() async throws {
    let fake = CleanupTestRuntime()
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.enabled = true
    controller.start()
    fake.completions[0](nil)
    fake.application.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
    try await Task.sleep(for: .milliseconds(80))
    #expect(fake.sessions.count == 2)
    #expect(fake.sessions[0].invalidations == 1)
    fake.workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
    controller.stop()
    try await Task.sleep(for: .milliseconds(80))
    #expect(fake.sessions.count == 2)
    #expect(controller.status == "Menu bar cleanup is stopped.")
}

@Test @MainActor
func cleanupUnsupportedRuntimeNeverCreatesSessionsOrHotKeys() {
    let fake = CleanupTestRuntime()
    fake.supported = false
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.enabled = true
    controller.start()
    controller.showAllItems()
    #expect(fake.sessions.isEmpty)
    #expect(fake.hotKeyHandler == nil)
    #expect(!controller.isExpanded)
}

@Test @MainActor
func cleanupCatalogIncludesLoginItemOwnersAndPreservesMissingSavedApps() {
    let fake = CleanupTestRuntime()
    let helperID = "com.apple.Passwords.MenuBarExtra"
    fake.apps = [
        .init(bundleID: helperID, title: "PasswordsMenuBarExtra", bundleURL: URL(fileURLWithPath:
            "/System/Applications/Passwords.app/Contents/Library/LoginItems/PasswordsMenuBarExtra.app"),
            isProhibited: false, isAccessory: true),
        .init(bundleID: "com.apple.Passwords", title: "Passwords", bundleURL: URL(fileURLWithPath:
            "/System/Applications/Passwords.app"), isProhibited: false),
        .init(bundleID: "com.example.launcher", title: "Launcher", bundleURL: URL(fileURLWithPath:
            "/Applications/Other.app/Contents/Library/LoginItems/Launcher.app"), isProhibited: true),
        .init(bundleID: "com.example.renderer", title: "Renderer", bundleURL: URL(fileURLWithPath:
            "/Applications/Browser.app/Contents/Frameworks/Helper.app"), isProhibited: false),
        .init(bundleID: "com.apple.controlcenter", title: "Control Center", bundleURL: URL(fileURLWithPath:
            "/System/Library/CoreServices/ControlCenter.app"), isProhibited: false)
    ]
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.setSection(.alwaysHidden, for: "app:com.example.absent")
    controller.setSection(.hidden, for: MenuBarCleanupPolicy.appKey(helperID))
    controller.enabled = true
    controller.start()
    let helper = controller.entries.first { $0.bundleID == helperID }
    #expect(helper?.isMenuBarHelper == true)
    #expect(helper?.isRunning == true)
    #expect(helper?.title == "Passwords")
    #expect(!controller.entries.contains { $0.bundleID == "com.example.launcher" })
    #expect(!controller.entries.contains { $0.bundleID == "com.example.renderer" })
    #expect(!controller.entries.contains { $0.bundleID == "com.apple.controlcenter" })
    #expect(controller.entries.first { $0.bundleID == "com.example.absent" }?.isRunning == false)
    #expect(controller.section(for: "app:com.example.absent") == .alwaysHidden)
    #expect(!fake.plans.last!.allowedBundles.contains(helperID))
    #expect(fake.plans.last!.allowedBundles.contains("com.apple.Passwords"))
    controller.showAllItems()
    #expect(fake.plans.last!.allowedBundles.contains(helperID))
    fake.apps.removeAll { $0.bundleID == helperID }
    controller.refresh()
    #expect(controller.entries.filter { $0.bundleID == helperID }.count == 1)
    #expect(controller.entries.first { $0.bundleID == helperID }?.isRunning == false)
    #expect(controller.section(for: MenuBarCleanupPolicy.appKey(helperID)) == .hidden)
}

@Test @MainActor
func cleanupRetiredHotKeysCannotAffectRestartOrReenable() {
    let fake = CleanupTestRuntime()
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.enabled = true
    controller.start()
    let firstHandler = fake.hotKeyHandler!
    controller.stop()
    controller.start()
    firstHandler(1)
    firstHandler(2)
    #expect(controller.enabled)
    #expect(!controller.isExpanded)
    let secondHandler = fake.hotKeyHandler!
    controller.restoreSystemMenuBar()
    controller.enabled = true
    secondHandler(1)
    secondHandler(2)
    #expect(controller.enabled)
    #expect(!controller.isExpanded)
    fake.hotKeyHandler!(1)
    #expect(controller.isExpanded)
    fake.hotKeyHandler!(2)
    #expect(!controller.enabled)
}

@Test @MainActor
func cleanupQueuedNotificationsCannotCrossRunBoundaries() async throws {
    let fake = CleanupTestRuntime()
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.enabled = true
    controller.start()
    fake.workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
    controller.stop()
    controller.start()
    try await Task.sleep(for: .milliseconds(80))
    #expect(fake.sessions.count == 2)
    #expect(fake.sessions.last!.invalidations == 0)
    #expect(controller.status == "Updating menu bar…")
    fake.workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
    controller.stop()
    controller.start()
    controller.showAllItems()
    try await Task.sleep(for: .milliseconds(80))
    #expect(controller.isExpanded)
    #expect(fake.sessions.count == 3)
    #expect(fake.sessions.last!.invalidations == 0)
}

@Test @MainActor
func cleanupManualPausePreservesDefaultsAndRetiresPendingWork() async throws {
    let fake = CleanupTestRuntime()
    let controller = fake.controller(timeout: .milliseconds(200), rehide: .milliseconds(200),
                                     refresh: .milliseconds(200))
    defer { fake.cleanup(controller) }
    fake.defaults.set("preserve me", forKey: "unrelated.preference")
    controller.setSection(.hidden, for: "system:5")
    controller.enabled = true
    let savedChoices = controller.configuration
    let savedDomain = fake.persistentDomain
    #expect(!controller.isPaused)
    controller.start()
    controller.showAllItems()
    #expect(controller.isExpanded)
    #expect(fake.sessions.count == 2)
    fake.workspace.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
    try await Task.sleep(for: .milliseconds(20))
    #expect(fake.sessions.last!.invalidations == 0)

    controller.pauseCleanup()
    let pausedStatus = controller.status
    #expect(controller.isPaused)
    #expect(controller.enabled)
    #expect(controller.revealMode == .collapsed)
    #expect(fake.sessions.allSatisfy { $0.invalidations == 1 })
    #expect(controller.configuration == savedChoices)
    #expect(fake.persistentDomain == savedDomain)
    fake.completions[0](nil)
    fake.completions[1](cleanupFailure)
    fake.completions[1](nil)
    controller.pauseCleanup()
    #expect(controller.errorMessage == nil)
    #expect(controller.status == pausedStatus)
    #expect(fake.sessions.count == 2)
    #expect(fake.sessions.allSatisfy { $0.invalidations == 1 })
    try await Task.sleep(for: .milliseconds(260))
    #expect(controller.isPaused)
    #expect(controller.revealMode == .collapsed)
    #expect(controller.errorMessage == nil)
    #expect(controller.status == pausedStatus)
    #expect(fake.sessions.count == 2)
    #expect(fake.persistentDomain == savedDomain)

    controller.resumeCleanup()
    #expect(!controller.isPaused)
    #expect(fake.sessions.count == 3)
    #expect(fake.plans.last == fake.plans.first)
    fake.completions[1](cleanupFailure)
    #expect(controller.errorMessage == nil)
    #expect(controller.status == "Updating menu bar…")
    fake.completions.last!(nil)
    controller.resumeCleanup()
    #expect(fake.sessions.count == 3)
    #expect(controller.status == "Menu bar cleanup is active.")
    #expect(controller.configuration == savedChoices)
    #expect(fake.persistentDomain == savedDomain)
}

@Test @MainActor
func cleanupManualPauseCancelsQueuedRefreshAcrossResume() async throws {
    let fake = CleanupTestRuntime()
    fake.apps = [.init(bundleID: "com.example.current", title: "Current",
                       bundleURL: URL(fileURLWithPath: "/Applications/Current.app"), isProhibited: false)]
    let controller = fake.controller(refresh: .milliseconds(120))
    defer { fake.cleanup(controller) }
    controller.enabled = true
    controller.start()
    fake.completions[0](nil)
    fake.workspace.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
    try await Task.sleep(for: .milliseconds(20))
    #expect(fake.sessions.count == 1)
    controller.pauseCleanup()
    controller.resumeCleanup()
    #expect(fake.sessions.count == 2)
    fake.completions.last!(nil)
    // No new notification: only the pre-pause queued refresh could see this app.
    fake.apps.append(.init(bundleID: "com.example.later", title: "Later",
                          bundleURL: URL(fileURLWithPath: "/Applications/Later.app"), isProhibited: false))
    try await Task.sleep(for: .milliseconds(180))
    #expect(fake.sessions.count == 2)
    #expect(!fake.plans.last!.allowedBundles.contains("com.example.later"))
    #expect(controller.status == "Menu bar cleanup is active.")
    controller.refresh()
    #expect(fake.sessions.count == 3)
    #expect(fake.plans.last!.allowedBundles.contains("com.example.later"))
}

@Test @MainActor
func cleanupManualPauseClearsErrorsAndResumeFailuresRestoreNormally() {
    let fake = CleanupTestRuntime()
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.setSection(.hidden, for: "system:5")
    controller.enabled = true
    controller.start()
    fake.completions[0](cleanupFailure)
    #expect(controller.errorMessage == "Activation failed")
    let savedChoices = controller.configuration
    let savedDomain = fake.persistentDomain
    controller.pauseCleanup()
    #expect(controller.isPaused)
    #expect(controller.errorMessage == nil)
    controller.resumeCleanup()
    #expect(!controller.isPaused)
    #expect(fake.sessions.count == 2)
    fake.completions[1](cleanupFailure)
    #expect(fake.sessions[1].invalidations == 1)
    #expect(controller.enabled)
    #expect(controller.revealMode == .collapsed)
    #expect(controller.errorMessage == "Activation failed")
    #expect(controller.status == "The original menu bar has been restored.")
    fake.completions[1](nil)
    #expect(controller.errorMessage == "Activation failed")
    #expect(controller.status == "The original menu bar has been restored.")

    controller.pauseCleanup()
    fake.returnsNil = true
    controller.resumeCleanup()
    #expect(!controller.isPaused)
    #expect(controller.enabled)
    #expect(controller.errorMessage?.contains("unavailable") == true)
    #expect(controller.status == "The original menu bar has been restored.")
    fake.completions.last!(nil)
    #expect(controller.errorMessage != nil)
    #expect(controller.status == "The original menu bar has been restored.")
    #expect(controller.configuration == savedChoices)
    #expect(fake.persistentDomain == savedDomain)
}

@Test @MainActor
func cleanupManualPauseBlocksRevealsButRestoreHotKeyStillDisables() {
    let fake = CleanupTestRuntime()
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.setSection(.hidden, for: "system:5")
    controller.enabled = true
    controller.start()
    fake.completions[0](nil)
    let savedChoices = controller.configuration
    let savedDomain = fake.persistentDomain
    controller.pauseCleanup()
    let pausedHotKey = fake.hotKeyHandler!
    controller.toggleHiddenItems()
    controller.showAllItems()
    pausedHotKey(1)
    #expect(controller.isPaused)
    #expect(controller.revealMode == .collapsed)
    #expect(fake.sessions.count == 1)
    #expect(controller.configuration == savedChoices)
    #expect(fake.persistentDomain == savedDomain)

    pausedHotKey(2)
    #expect(!controller.isPaused)
    #expect(!controller.enabled)
    #expect(controller.revealMode == .collapsed)
    #expect(controller.errorMessage == nil)
    #expect(controller.status == "Menu bar cleanup is off.")
    #expect(fake.sessions.count == 1)
    #expect(!fake.defaults.bool(forKey: "menuBarCleanup.enabled"))
    var restoredChoices = savedChoices
    restoredChoices.enabled = false
    #expect(controller.configuration == restoredChoices)
    controller.pauseCleanup()
    controller.resumeCleanup()
    #expect(!controller.isPaused)
    #expect(!controller.enabled)
    #expect(fake.sessions.count == 1)
}

@Test @MainActor
func cleanupManualPauseRetiresHotKeysAcrossPauseAndResume() {
    let fake = CleanupTestRuntime()
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.setSection(.hidden, for: "system:5")
    controller.enabled = true
    controller.start()
    fake.completions[0](nil)
    let beforePause = fake.hotKeyHandler!
    controller.pauseCleanup()
    let duringPause = fake.hotKeyHandler!
    beforePause(1)
    beforePause(2)
    #expect(controller.isPaused)
    #expect(controller.enabled)
    #expect(controller.revealMode == .collapsed)
    #expect(fake.sessions.count == 1)

    controller.resumeCleanup()
    fake.completions.last!(nil)
    beforePause(1)
    beforePause(2)
    duringPause(1)
    duringPause(2)
    #expect(!controller.isPaused)
    #expect(controller.enabled)
    #expect(controller.revealMode == .collapsed)
    #expect(fake.sessions.count == 2)
    fake.hotKeyHandler!(1)
    #expect(controller.isExpanded)
    #expect(fake.sessions.count == 3)
    fake.hotKeyHandler!(2)
    #expect(!controller.enabled)
    #expect(!controller.isPaused)
    #expect(controller.revealMode == .collapsed)
}

@Test @MainActor
func cleanupManualPauseDefersChangedChoicesAndNotificationsUntilResume() async throws {
    let fake = CleanupTestRuntime()
    fake.apps = [
        .init(bundleID: "com.example.previous", title: "Previous",
              bundleURL: URL(fileURLWithPath: "/Applications/Previous.app"), isProhibited: false),
        .init(bundleID: "com.example.hidden", title: "Hidden",
              bundleURL: URL(fileURLWithPath: "/Applications/Hidden.app"), isProhibited: false)
    ]
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.setSection(.hidden, for: "system:5")
    controller.setSection(.hidden, for: "app:com.example.hidden")
    controller.enabled = true
    controller.start()
    controller.showAllItems()
    fake.completions.last!(nil)
    controller.pauseCleanup()
    let count = fake.sessions.count
    controller.keepActivityControlsHidden = false
    controller.autoRehide = false
    controller.setSection(.alwaysHidden, for: "system:5")
    controller.setSection(.hidden, for: "system:0")
    controller.setSection(.alwaysHidden, for: "app:com.example.previous")
    controller.setSection(.alwaysHidden, for: "app:com.example.hidden")
    controller.setSection(.hidden, for: "app:com.example.current-hidden")
    fake.apps.removeFirst()
    controller.refresh()
    controller.start()
    fake.workspace.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
    fake.workspace.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    fake.application.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
    fake.workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
    fake.workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
    try await Task.sleep(for: .milliseconds(80))
    #expect(controller.isPaused)
    #expect(controller.revealMode == .collapsed)
    #expect(controller.errorMessage == nil)
    #expect(fake.sessions.count == count)
    #expect(fake.sessions.last!.invalidations == 1)
    let currentChoices = controller.configuration
    let currentDomain = fake.persistentDomain
    // Resume must take a fresh app snapshot, not reuse the last paused refresh.
    fake.apps.append(contentsOf: [
        .init(bundleID: "com.example.current-hidden", title: "Current Hidden",
              bundleURL: URL(fileURLWithPath: "/Applications/CurrentHidden.app"), isProhibited: false),
        .init(bundleID: "com.example.current-visible", title: "Current Visible",
              bundleURL: URL(fileURLWithPath: "/Applications/CurrentVisible.app"), isProhibited: false)
    ])
    controller.resumeCleanup()
    #expect(!controller.isPaused)
    #expect(controller.revealMode == .collapsed)
    #expect(fake.sessions.count == count + 1)
    #expect(fake.plans.last!.allowedBundles.contains("com.example.current-visible"))
    #expect(!fake.plans.last!.allowedBundles.contains("com.example.current-hidden"))
    #expect(!fake.plans.last!.allowedBundles.contains("com.example.hidden"))
    #expect(!fake.plans.last!.allowedBundles.contains("com.example.previous"))
    #expect(!fake.plans.last!.allowedSystemItems.contains(0))
    #expect(!fake.plans.last!.allowedSystemItems.contains(5))
    #expect(controller.entries.first { $0.bundleID == "com.example.current-visible" }?.isRunning == true)
    #expect(controller.entries.first { $0.bundleID == "com.example.previous" }?.isRunning == false)
    #expect(controller.configuration == currentChoices)
    #expect(fake.persistentDomain == currentDomain)
    controller.resumeCleanup()
    #expect(fake.sessions.count == count + 1)
    fake.completions.last!(nil)
    #expect(controller.status == "Menu bar cleanup is active.")
}

@Test @MainActor
func cleanupManualPauseSurvivesSleepAndWakeUntilExplicitResume() async throws {
    let fake = CleanupTestRuntime()
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.setSection(.hidden, for: "system:5")
    controller.enabled = true
    controller.start()
    fake.completions[0](nil)
    controller.pauseCleanup()
    let savedChoices = controller.configuration
    let savedDomain = fake.persistentDomain
    fake.workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
    try await Task.sleep(for: .milliseconds(30))
    controller.pauseCleanup()
    controller.refresh()
    controller.showAllItems()
    #expect(controller.isPaused)
    #expect(controller.revealMode == .collapsed)
    #expect(fake.sessions.count == 1)
    fake.workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
    fake.workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
    fake.application.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
    try await Task.sleep(for: .milliseconds(80))
    #expect(controller.isPaused)
    #expect(controller.revealMode == .collapsed)
    #expect(controller.errorMessage == nil)
    #expect(fake.sessions.count == 1)
    #expect(fake.sessions[0].invalidations == 1)
    #expect(controller.configuration == savedChoices)
    #expect(fake.persistentDomain == savedDomain)
    controller.resumeCleanup()
    #expect(!controller.isPaused)
    #expect(fake.sessions.count == 2)
    #expect(!fake.plans.last!.allowedSystemItems.contains(5))
    fake.completions.last!(nil)
    #expect(controller.status == "Menu bar cleanup is active.")
    #expect(fake.persistentDomain == savedDomain)
}

@Test @MainActor
func cleanupManualPauseIsRejectedWhileAsleep() async throws {
    let fake = CleanupTestRuntime()
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.setSection(.hidden, for: "system:5")
    controller.enabled = true
    controller.start()
    fake.completions[0](nil)
    let savedDomain = fake.persistentDomain
    fake.workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
    try await Task.sleep(for: .milliseconds(30))
    #expect(controller.status == "Menu bar cleanup is paused for sleep.")
    controller.pauseCleanup()
    controller.resumeCleanup()
    #expect(!controller.isPaused)
    #expect(fake.sessions.count == 1)
    #expect(controller.status == "Menu bar cleanup is paused for sleep.")
    #expect(fake.persistentDomain == savedDomain)
    fake.workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
    fake.workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
    try await Task.sleep(for: .milliseconds(80))
    #expect(!controller.isPaused)
    #expect(controller.revealMode == .collapsed)
    #expect(fake.sessions.count == 2)
    fake.completions.last!(nil)
    #expect(controller.status == "Menu bar cleanup is active.")
    #expect(fake.persistentDomain == savedDomain)
}

@Test @MainActor
func cleanupManualPauseStopClearsPauseAndRestartOrRelaunchUsesSavedChoices() {
    let fake = CleanupTestRuntime()
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.setSection(.alwaysHidden, for: "system:5")
    controller.autoRehide = false
    controller.enabled = true
    let savedChoices = controller.configuration
    let savedDomain = fake.persistentDomain
    controller.start()
    let collapsedPlan = fake.plans.last!
    controller.showAllItems()
    controller.pauseCleanup()
    controller.stop()
    #expect(!controller.isPaused)
    #expect(controller.enabled)
    #expect(controller.revealMode == .collapsed)
    #expect(controller.status == "Menu bar cleanup is stopped.")
    controller.pauseCleanup()
    controller.resumeCleanup()
    #expect(!controller.isPaused)
    #expect(fake.sessions.count == 2)
    #expect(controller.configuration == savedChoices)
    #expect(fake.persistentDomain == savedDomain)
    controller.start()
    #expect(!controller.isPaused)
    #expect(fake.sessions.count == 3)
    #expect(fake.plans.last == collapsedPlan)
    fake.completions.last!(nil)
    controller.pauseCleanup()
    controller.stop()

    let nextLaunch = fake.controller()
    defer { nextLaunch.stop() }
    #expect(!nextLaunch.isPaused)
    #expect(nextLaunch.configuration == savedChoices)
    nextLaunch.start()
    #expect(fake.sessions.count == 4)
    #expect(fake.plans.last == collapsedPlan)
    #expect(nextLaunch.revealMode == .collapsed)
    fake.completions.last!(nil)
    #expect(nextLaunch.status == "Menu bar cleanup is active.")
    #expect(fake.persistentDomain == savedDomain)
}

@Test @MainActor
func cleanupManualPauseAndResumeRequireStartedEnabledCleanup() {
    let fake = CleanupTestRuntime()
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    let initialDomain = fake.persistentDomain
    #expect(!controller.isPaused)
    controller.pauseCleanup()
    controller.resumeCleanup()
    #expect(!controller.isPaused)
    #expect(fake.sessions.isEmpty)
    #expect(fake.persistentDomain == initialDomain)
    controller.start()
    controller.pauseCleanup()
    controller.resumeCleanup()
    #expect(!controller.isPaused)
    #expect(!controller.enabled)
    #expect(fake.sessions.isEmpty)
    #expect(fake.hotKeyHandler == nil)
    #expect(fake.persistentDomain == initialDomain)
    controller.stop()
    controller.enabled = true
    let enabledDomain = fake.persistentDomain
    controller.pauseCleanup()
    controller.resumeCleanup()
    #expect(!controller.isPaused)
    #expect(controller.enabled)
    #expect(fake.sessions.isEmpty)
    #expect(controller.status == "Menu bar cleanup is stopped.")
    #expect(fake.persistentDomain == enabledDomain)
}

@Test @MainActor
func cleanupManualPauseAndResumeRejectUnsupportedRuntime() {
    let fake = CleanupTestRuntime()
    fake.supported = false
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.enabled = true
    controller.start()
    let originalStatus = controller.status
    let savedChoices = controller.configuration
    let savedDomain = fake.persistentDomain
    controller.pauseCleanup()
    controller.resumeCleanup()
    #expect(!controller.isPaused)
    #expect(controller.enabled)
    #expect(controller.revealMode == .collapsed)
    #expect(controller.errorMessage == nil)
    #expect(fake.sessions.isEmpty)
    #expect(fake.hotKeyHandler == nil)
    #expect(controller.status == originalStatus)
    #expect(controller.configuration == savedChoices)
    #expect(fake.persistentDomain == savedDomain)
}
