import Testing
@testable import MenuWattCore

private let ownID = "com.junsu.menuwatt"
private let chatID = "com.example.chat"
private let musicID = "com.example.music"

@Test func cleanupNeverHidesItsOwnRecoveryControl() {
    let config = MenuBarCleanupConfiguration(enabled: true, sections: [
        MenuBarCleanupPolicy.appKey(ownID): .alwaysHidden,
        MenuBarCleanupPolicy.systemKey(2): .alwaysHidden,
        MenuBarCleanupPolicy.systemKey(8): .alwaysHidden
    ])
    let plan = MenuBarCleanupPolicy.plan(configuration: config, runningBundleIDs: [], ownBundleID: ownID, reveal: .collapsed)
    #expect(plan.allowedBundles.contains(ownID))
    #expect(plan.allowedSystemItems.contains(2))
    #expect(plan.allowedSystemItems.contains(8))
}

@Test func ordinaryRevealDoesNotExposeAlwaysHiddenApps() {
    let config = MenuBarCleanupConfiguration(enabled: true, sections: [
        MenuBarCleanupPolicy.appKey(chatID): .hidden,
        MenuBarCleanupPolicy.appKey(musicID): .alwaysHidden
    ])
    let plan = MenuBarCleanupPolicy.plan(configuration: config, runningBundleIDs: [chatID, musicID], ownBundleID: ownID, reveal: .hidden)
    #expect(plan.allowedBundles.contains(chatID))
    #expect(!plan.allowedBundles.contains(musicID))
}

@Test func revealingAllAppsKeepsActivityControlsSuppressed() {
    let config = MenuBarCleanupConfiguration(enabled: true, keepActivityControlsHidden: true,
        sections: [MenuBarCleanupPolicy.appKey(chatID): .alwaysHidden])
    let plan = MenuBarCleanupPolicy.plan(configuration: config, runningBundleIDs: [chatID], ownBundleID: ownID, reveal: .all)
    #expect(plan.allowedBundles.contains(chatID))
    #expect(plan.needsSession)
}

@Test func revealingAllCanRestoreNativeSystemControls() {
    let config = MenuBarCleanupConfiguration(enabled: true, keepActivityControlsHidden: false,
        sections: [MenuBarCleanupPolicy.appKey(chatID): .hidden])
    let plan = MenuBarCleanupPolicy.plan(configuration: config, runningBundleIDs: [chatID], ownBundleID: ownID, reveal: .all)
    #expect(!plan.needsSession)
}

@Test func newlyLaunchedAppsAreVisibleUnlessExplicitlyAssigned() {
    let config = MenuBarCleanupConfiguration(enabled: true,
        sections: [MenuBarCleanupPolicy.appKey(chatID): .hidden])
    let plan = MenuBarCleanupPolicy.plan(configuration: config, runningBundleIDs: [chatID, musicID], ownBundleID: ownID, reveal: .collapsed)
    #expect(!plan.allowedBundles.contains(chatID))
    #expect(plan.allowedBundles.contains(musicID))
}

@Test func disablingCleanupAlwaysReleasesTheSystemSession() {
    let config = MenuBarCleanupConfiguration(enabled: false,
        sections: [MenuBarCleanupPolicy.appKey(chatID): .alwaysHidden])
    let plan = MenuBarCleanupPolicy.plan(configuration: config, runningBundleIDs: [chatID], ownBundleID: ownID, reveal: .collapsed)
    #expect(!plan.needsSession)
}
