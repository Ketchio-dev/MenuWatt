import AppKit
import Foundation
import Testing
@testable import MenuWatt
@testable import MenuWattCore

@MainActor
private final class HoverTestSession: MenuBarCleanupSession {
    var invalidations = 0
    func invalidate() { invalidations += 1 }
}

@MainActor
private final class HoverSnapshotBox {
    var value = MenuBarHoverSnapshot(
        location: NSPoint(x: 720, y: 450),
        screenFrames: [NSRect(x: 0, y: 0, width: 1440, height: 900)],
        windows: [.init(frame: NSRect(x: 0, y: 876, width: 1440, height: 24),
                        level: NSWindow.Level.mainMenu.rawValue)]
    )
}

@MainActor
private final class HoverTestRuntime {
    let domain = "MenuWatt.HoverTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let workspace = NotificationCenter()
    let application = NotificationCenter()
    let monitor: MenuBarHoverMonitor
    private let snapshotBox: HoverSnapshotBox
    var mouseLocation: NSPoint {
        get { snapshotBox.value.location }
        set { snapshotBox.value.location = newValue }
    }
    var menuOpen: Bool {
        get { snapshotBox.value.windows.contains { $0.level == NSWindow.Level.popUpMenu.rawValue } }
        set {
            snapshotBox.value.windows.removeAll { $0.level == NSWindow.Level.popUpMenu.rawValue }
            if newValue {
                snapshotBox.value.windows.append(.init(
                    frame: NSRect(x: 680, y: 600, width: 220, height: 276),
                    level: NSWindow.Level.popUpMenu.rawValue))
            }
        }
    }
    var sessions: [HoverTestSession] = []
    var plans: [MenuBarVisibilityPlan] = []
    var completions: [@MainActor (Error?) -> Void] = []
    var apps: [MenuBarCleanupApp] = []

    init() {
        defaults = UserDefaults(suiteName: domain)!
        let box = HoverSnapshotBox()
        snapshotBox = box
        monitor = MenuBarHoverMonitor(pollInterval: .milliseconds(10),
                                      snapshotProvider: { box.value })
    }

    func controller(rehide: Duration = .seconds(30)) -> MenuBarCleanupController {
        MenuBarCleanupController(defaults: defaults, runtime: .init(
            isSupported: true,
            makeSession: { [self] plan, completion in
                plans.append(plan)
                completions.append(completion)
                let session = HoverTestSession()
                sessions.append(session)
                return session
            },
            makeHotKeys: { _ in NSObject() },
            runningApps: { [self] in apps },
            workspaceNotifications: workspace, applicationNotifications: application,
            refreshDelay: .milliseconds(10), activationTimeout: .seconds(2),
            rehideDelay: rehide
        ), hoverMonitor: monitor)
    }

    func inside() -> NSPoint { NSPoint(x: 720, y: 890) }
    func outside() -> NSPoint { NSPoint(x: 720, y: 450) }

    func feed(_ point: NSPoint) {
        mouseLocation = point
        monitor.check()
    }

    func cleanup(_ controller: MenuBarCleanupController) {
        controller.stop()
        defaults.removePersistentDomain(forName: domain)
    }
}

@Test @MainActor
func hoverRevealOpensHiddenItemsAndExitCollapsesAfterGrace() async throws {
    let fake = HoverTestRuntime()
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.setSection(.hidden, for: "system:5")
    controller.revealOnHover = true
    controller.enabled = true
    controller.start()
    fake.completions[0](nil)
    #expect(!controller.isExpanded)
    #expect(controller.hoverRevealed == false)

    fake.feed(fake.inside())
    #expect(controller.isExpanded)
    #expect(controller.hoverRevealed)
    #expect(controller.revealMode == .hidden)
    fake.completions.last!(nil)
    #expect(controller.status == "Hidden icons are revealed.")

    // Exit starts a 1s grace period; still expanded immediately after.
    fake.feed(fake.outside())
    #expect(controller.isExpanded)
    try await Task.sleep(for: .milliseconds(1200))
    #expect(!controller.isExpanded)
    #expect(!controller.hoverRevealed)
}

@Test @MainActor
func hoverRevealReenterDuringGraceCancelsCollapse() async throws {
    let fake = HoverTestRuntime()
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.setSection(.hidden, for: "system:5")
    controller.revealOnHover = true
    controller.enabled = true
    controller.start()
    fake.completions[0](nil)

    fake.feed(fake.inside())
    #expect(controller.isExpanded)
    fake.feed(fake.outside())
    try await Task.sleep(for: .milliseconds(300))
    fake.feed(fake.inside())
    try await Task.sleep(for: .milliseconds(1000))
    #expect(controller.isExpanded)
    #expect(controller.hoverRevealed)
}

@Test @MainActor
func manualRevealWinsOverHoverExit() async throws {
    let fake = HoverTestRuntime()
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.setSection(.hidden, for: "system:5")
    controller.revealOnHover = true
    controller.enabled = true
    controller.start()
    fake.completions[0](nil)

    fake.feed(fake.inside())
    #expect(controller.hoverRevealed)
    // Manual action takes over: hover exit must not collapse it.
    controller.showAllItems()
    #expect(!controller.hoverRevealed)
    #expect(controller.revealMode == .all)
    fake.feed(fake.outside())
    try await Task.sleep(for: .milliseconds(1200))
    #expect(controller.isExpanded)
    #expect(controller.revealMode == .all)
}

@Test @MainActor
func hoverRevealRespectsPauseStopAndToggle() {
    let fake = HoverTestRuntime()
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.setSection(.hidden, for: "system:5")
    controller.enabled = true
    controller.start()
    fake.completions[0](nil)

    // Disabled by default: hover does nothing.
    fake.feed(fake.inside())
    #expect(!controller.isExpanded)

    controller.revealOnHover = true
    // Toggling the setting while running starts the monitor.
    // Re-enter: the previous inside-feed predates the monitor.
    fake.feed(fake.outside())
    fake.feed(fake.inside())
    #expect(controller.isExpanded)

    controller.pauseCleanup()
    #expect(!controller.isExpanded)
    #expect(!controller.hoverRevealed)
    fake.feed(fake.inside())
    #expect(!controller.isExpanded)

    controller.resumeCleanup()
    fake.feed(fake.outside())
    fake.feed(fake.inside())
    #expect(controller.isExpanded)

    controller.revealOnHover = false
    controller.refresh()
    #expect(!controller.hoverRevealed)
    fake.feed(fake.inside())
    #expect(!controller.isExpanded)
    controller.stop()
}

@Test @MainActor
func hoverKeepsIconsRevealedThroughoutNativeMenuInteraction() async throws {
    let fake = HoverTestRuntime()
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.revealOnHover = true
    controller.enabled = true
    controller.start()
    fake.feed(fake.inside())
    fake.menuOpen = true
    fake.feed(fake.outside())
    try await Task.sleep(for: .milliseconds(1200))
    #expect(controller.hoverRevealed)
    #expect(controller.isExpanded)
    fake.menuOpen = false
    fake.monitor.check()
    try await Task.sleep(for: .milliseconds(1200))
    #expect(!controller.isExpanded)
}

@Test @MainActor
func menuOpenedDuringExitGraceDefersHoverCollapse() async throws {
    let fake = HoverTestRuntime()
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.revealOnHover = true
    controller.enabled = true
    controller.start()
    fake.feed(fake.inside())
    fake.feed(fake.outside())
    fake.menuOpen = true // Opens after exit; no second enter transition is required.
    try await Task.sleep(for: .milliseconds(1200))
    #expect(controller.isExpanded)
    fake.menuOpen = false
    try await Task.sleep(for: .milliseconds(1200))
    #expect(!controller.isExpanded)
}

@Test @MainActor
func hoverGraceSurvivesUnrelatedConfigurationChangesWithoutCompetingRehideTimer() async throws {
    let fake = HoverTestRuntime()
    let controller = fake.controller(rehide: .milliseconds(30))
    defer { fake.cleanup(controller) }
    controller.setSection(.alwaysHidden, for: "system:5")
    controller.revealOnHover = true
    controller.enabled = true
    controller.start()
    fake.feed(fake.inside())
    #expect(!fake.plans.last!.allowedSystemItems.contains(5)) // Hover never reveals Always Hidden.
    controller.setSection(.hidden, for: "system:0")
    try await Task.sleep(for: .milliseconds(100))
    #expect(controller.hoverRevealed)
    #expect(controller.isExpanded) // No 15s timer (30ms in this fixture) takes over.
    fake.feed(fake.outside())
    controller.keepActivityControlsHidden = false
    try await Task.sleep(for: .milliseconds(1200))
    #expect(!controller.isExpanded) // Editing a choice does not cancel the pending exit.
}

@Test @MainActor
func manualAutoCollapseWaitsUntilMenuInteractionEndsEvenWithHoverOff() async throws {
    let fake = HoverTestRuntime()
    let controller = fake.controller(rehide: .milliseconds(30))
    defer { fake.cleanup(controller) }
    controller.enabled = true
    controller.start()
    controller.showAllItems()
    fake.menuOpen = true
    try await Task.sleep(for: .milliseconds(100))
    #expect(controller.isExpanded)
    fake.menuOpen = false
    try await Task.sleep(for: .milliseconds(100))
    #expect(!controller.isExpanded)
}

@Test @MainActor
func hoverExitWorkCannotCrossPauseSleepOrStopRestart() async throws {
    let fake = HoverTestRuntime()
    let controller = fake.controller()
    defer { fake.cleanup(controller) }
    controller.revealOnHover = true
    controller.enabled = true
    controller.start()
    fake.feed(fake.inside())
    fake.feed(fake.outside())
    controller.pauseCleanup()
    controller.resumeCleanup()
    fake.feed(fake.inside())
    try await Task.sleep(for: .milliseconds(1200))
    #expect(controller.isExpanded)

    fake.feed(fake.outside())
    fake.workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
    try await Task.sleep(for: .milliseconds(30))
    #expect(!controller.isExpanded)
    #expect(!fake.monitor.running)
    fake.workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
    try await Task.sleep(for: .milliseconds(60))
    fake.feed(fake.inside())
    try await Task.sleep(for: .milliseconds(1200))
    #expect(controller.hoverRevealed)

    fake.feed(fake.outside())
    controller.stop()
    controller.start()
    fake.feed(fake.inside())
    try await Task.sleep(for: .milliseconds(1200))
    #expect(controller.hoverRevealed)
    #expect(controller.isExpanded)
}
