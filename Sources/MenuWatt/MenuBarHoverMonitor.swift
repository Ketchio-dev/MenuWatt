import AppKit
import Foundation

/// Polls pointer/window metadata without input interception or screen capture.
/// A hidden/full-screen bar has no visible bar window, so its screen edge alone
/// never triggers reveal. Keep hover-opened icons accessible during interaction.
@MainActor
final class MenuBarHoverMonitor {
    private let pollInterval: Duration
    private let snapshotProvider: () -> MenuBarHoverSnapshot
    private var pollTask: Task<Void, Never>?
    private var isActive = false
    private var onEnter: (() -> Void)?
    private var onExit: (() -> Void)?

    init(pollInterval: Duration = .milliseconds(250),
         snapshotProvider: @escaping () -> MenuBarHoverSnapshot = { .live() }) {
        self.pollInterval = pollInterval
        self.snapshotProvider = snapshotProvider
    }

    var running: Bool { pollTask != nil }

    /// Recheck at the actual deadline; a menu may have opened during the grace
    /// period, after the cursor had already left the bar.
    var preventsAutomaticCollapse: Bool {
        let snapshot = snapshotProvider()
        return snapshot.isInMenuBar || snapshot.isInteracting
    }

    func start(onEnter: @escaping () -> Void, onExit: @escaping () -> Void) {
        guard pollTask == nil else { return }
        self.onEnter = onEnter
        self.onExit = onExit
        // Activation needs a new entry, not whatever the cursor happened to
        // cover when the feature was enabled or cleanup was resumed.
        let snapshot = snapshotProvider()
        isActive = snapshot.isInMenuBar
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = self?.pollInterval else { return }
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.check()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        onEnter = nil
        onExit = nil
        isActive = false
    }

    /// Tests and the polling loop exercise the same snapshot transition logic.
    func check() {
        guard running else { return }
        let snapshot = snapshotProvider()
        // Never rearrange icons underneath a drag that enters the bar. Once
        // hover has opened them, dragging instead keeps the reveal alive.
        let active = isActive
            ? snapshot.isInMenuBar || snapshot.isInteracting
            : snapshot.isInMenuBar && !snapshot.mouseButtonsDown
        guard active != isActive else { return }
        isActive = active
        if active { onEnter?() } else { onExit?() }
    }
}
