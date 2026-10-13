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
private final class HoverTestRuntime {
    let domain = "MenuWatt.HoverTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let workspace = NotificationCenter()
    let application = NotificationCenter()
    let monitor: MenuBarHoverMonitor
    private let locationBox: NSBox
    var mouseLocation: NSPoint {
        get { locationBox.frame.origin }
        set { locationBox.setFrameOrigin(newValue) }
    }
    var sessions: [HoverTestSession] = []
    var plans: [MenuBarVisibilityPlan] = []
    var completions: [@MainActor (Error?) -> Void] = []
    var apps: [MenuBarCleanupApp] = []

    init() {
        defaults = UserDefaults(suiteName: domain)!
        // Deterministic geometry: one 1440x900 screen, menu bar strip on top.
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        // Box indirection: the closure cannot capture self before init completes.
        let locationBox = NSBox()
        locationBox.setFrameOrigin(NSPoint(x: 720, y: 450))
        // The poll loop reads this var, so testFeed and polling agree.
        monitor = MenuBarHoverMonitor(
            pollInterval: .milliseconds(10),
            locationProvider: { locationBox.frame.origin },
            screensProvider: { [frame] }
        )
        self.locationBox = locationBox
    }

    func controller() -> MenuBarCleanupController {
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
            rehideDelay: .seconds(30)
        ), hoverMonitor: monitor)
    }

    func inside() -> NSPoint { NSPoint(x: 720, y: 890) }
    func outside() -> NSPoint { NSPoint(x: 720, y: 450) }

    func feed(_ point: NSPoint) {
        mouseLocation = point
        monitor.testFeed(point)
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
