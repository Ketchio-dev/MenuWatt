import AppKit
import Foundation

/// Polls the global mouse location and reports menu bar enter/exit.
///
/// Thaw tracks the cursor with a HID event tap; this polls
/// `NSEvent.mouseLocation` on a timer instead, which needs no Accessibility
/// permission. The location is valid process-wide even when another app is
/// active. Tests inject locations directly.
@MainActor
final class MenuBarHoverMonitor {
    /// Height of the menu bar strip from the top of a screen.
    static let menuBarStripHeight: CGFloat = 30

    private let pollInterval: Duration
    private let locationProvider: () -> NSPoint
    private let screensProvider: () -> [NSRect]
    private var pollTask: Task<Void, Never>?
    private var isInside = false
    private var onEnter: (() -> Void)?
    private var onExit: (() -> Void)?

    init(
        pollInterval: Duration = .milliseconds(250),
        locationProvider: @escaping () -> NSPoint = { NSEvent.mouseLocation },
        screensProvider: @escaping () -> [NSRect] = {
            NSScreen.screens.map(\.frame)
        }
    ) {
        self.pollInterval = pollInterval
        self.locationProvider = locationProvider
        self.screensProvider = screensProvider
    }

    var running: Bool { pollTask != nil }

    func start(onEnter: @escaping () -> Void, onExit: @escaping () -> Void) {
        guard pollTask == nil else { return }
        self.onEnter = onEnter
        self.onExit = onExit
        isInside = isInMenuBar(locationProvider())
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: self.pollInterval)
                guard !Task.isCancelled else { return }
                self.check()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        onEnter = nil
        onExit = nil
        isInside = false
    }

    /// Test hook: feed a location through the enter/exit logic synchronously.
    func testFeed(_ location: NSPoint) {
        check(location: location)
    }

    private func check(location: NSPoint? = nil) {
        let point = location ?? locationProvider()
        let inside = isInMenuBar(point)
        guard inside != isInside else { return }
        isInside = inside
        if inside {
            onEnter?()
        } else {
            onExit?()
        }
    }

    private func isInMenuBar(_ point: NSPoint) -> Bool {
        for frame in screensProvider() {
            // AppKit screen frames use a bottom-left origin.
            if point.x >= frame.minX && point.x <= frame.maxX
                && point.y >= frame.maxY - Self.menuBarStripHeight && point.y <= frame.maxY {
                return true
            }
        }
        return false
    }
}
