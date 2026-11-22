import AppKit
import Testing
@testable import MenuWatt

@Test @MainActor
func hoverUsesActualVisibleBarHeightAndMultipleScreenOrigins() {
    let first = NSRect(x: 0, y: 0, width: 1800, height: 1169)
    let second = NSRect(x: -1440, y: -300, width: 1440, height: 900)
    let bars: [MenuBarHoverWindow] = [
        .init(frame: NSRect(x: 0, y: 1130, width: 1800, height: 39), level: 24),
        .init(frame: NSRect(x: -1440, y: 576, width: 1440, height: 24), level: 24)
    ]
    var snapshot = MenuBarHoverSnapshot(location: NSPoint(x: 900, y: 1131),
                                      screenFrames: [first, second], windows: bars)
    #expect(snapshot.isInMenuBar) // Below the old fixed 30pt strip on a notched display.
    snapshot.location = NSPoint(x: 900, y: 1129)
    #expect(!snapshot.isInMenuBar)
    snapshot.location = NSPoint(x: -900, y: 580)
    #expect(snapshot.isInMenuBar)
    snapshot.location = NSPoint(x: -900, y: 575)
    #expect(!snapshot.isInMenuBar)
    snapshot.location = NSPoint(x: -1500, y: 580)
    #expect(!snapshot.isInMenuBar)
}

@Test @MainActor
func hoverDoesNotInventBarAtHiddenOrFullscreenScreenEdge() {
    var snapshot = MenuBarHoverSnapshot(location: NSPoint(x: 900, y: 1168),
        screenFrames: [NSRect(x: 0, y: 0, width: 1800, height: 1169)], windows: [])
    #expect(!snapshot.isInMenuBar)
    // A status icon alone and a fullscreen-level window are not the visible bar.
    snapshot.windows = [
        .init(frame: NSRect(x: 1700, y: 1130, width: 22, height: 39), level: 25),
        .init(frame: NSRect(x: 0, y: 0, width: 1800, height: 1169), level: 24)
    ]
    #expect(!snapshot.isInMenuBar)
    snapshot.windows.append(.init(frame: NSRect(x: 0, y: 1130, width: 1800, height: 39), level: 24))
    #expect(snapshot.isInMenuBar)
}

@Test @MainActor
func hoverProtectsNativeMenusAttachedPanelsAndDraggingButNotUnrelatedWindows() {
    var snapshot = MenuBarHoverSnapshot(location: NSPoint(x: 900, y: 450),
        screenFrames: [NSRect(x: 0, y: 0, width: 1800, height: 1169)],
        windows: [.init(frame: NSRect(x: 0, y: 1130, width: 1800, height: 39), level: 24)])
    #expect(!snapshot.isInteracting)
    snapshot.windows.append(.init(frame: NSRect(x: 680, y: 700, width: 250, height: 430), level: 101))
    #expect(snapshot.isInteracting) // Whole menu, including movement into submenus.
    snapshot.windows.removeLast()
    snapshot.windows.append(.init(frame: NSRect(x: 680, y: 700, width: 250, height: 428), level: 3))
    #expect(snapshot.isInteracting)
    snapshot.windows.removeLast()
    snapshot.windows.append(.init(frame: NSRect(x: 680, y: 100, width: 250, height: 300), level: 3))
    #expect(!snapshot.isInteracting)
    snapshot.mouseButtonsDown = true
    #expect(snapshot.isInteracting)
}

@Test @MainActor
func hoverMonitorDoesNotRestartRevealWhileStoppedOrAtSamePosition() {
    var snapshot = MenuBarHoverSnapshot(location: NSPoint(x: 720, y: 450),
        screenFrames: [NSRect(x: 0, y: 0, width: 1440, height: 900)],
        windows: [.init(frame: NSRect(x: 0, y: 876, width: 1440, height: 24), level: 24)])
    let monitor = MenuBarHoverMonitor(pollInterval: .seconds(30), snapshotProvider: { snapshot })
    var enters = 0
    var exits = 0
    monitor.start(onEnter: { enters += 1 }, onExit: { exits += 1 })
    defer { monitor.stop() }
    snapshot.location = NSPoint(x: 720, y: 890)
    snapshot.mouseButtonsDown = true
    monitor.check()
    #expect(enters == 0) // A drag entering the bar must not rearrange its icons.
    snapshot.mouseButtonsDown = false
    monitor.check()
    monitor.check()
    #expect(enters == 1)
    snapshot.windows.append(.init(frame: NSRect(x: 680, y: 600, width: 220, height: 276), level: 101))
    snapshot.location = NSPoint(x: 720, y: 700)
    monitor.check()
    #expect(exits == 0)
    snapshot.windows.removeLast()
    monitor.check()
    #expect(exits == 1)
    monitor.stop()
    snapshot.location = NSPoint(x: 720, y: 890)
    monitor.check()
    #expect(enters == 1)
    monitor.start(onEnter: { enters += 1 }, onExit: { exits += 1 })
    monitor.check()
    #expect(enters == 1) // Resume requires a fresh entry.
}
