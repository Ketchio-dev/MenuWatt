import Foundation
import MenuWattCore

/// Owns one native visibility assertion: creation, completion routing and
/// timeout handling.
///
/// Extracted from the controller following Thaw's split between the menu bar
/// manager and its item-transaction code. The controller still decides *when*
/// to apply; this type only guards *which* completion is current and reports
/// structured failures instead of raw strings.
@MainActor
final class MenuBarCleanupSessionManager {
    private let makeSession: (
        MenuBarVisibilityPlan, @escaping @MainActor (Error?) -> Void
    ) -> (any MenuBarCleanupSession)?
    private let activationTimeout: Duration

    private var session: (any MenuBarCleanupSession)?
    private var appliedPlan: MenuBarVisibilityPlan?
    private var isActivating = false
    private var activationSequence: UInt64 = 0
    private var timeoutTask: Task<Void, Never>?

    init(
        makeSession: @escaping (
            MenuBarVisibilityPlan, @escaping @MainActor (Error?) -> Void
        ) -> (any MenuBarCleanupSession)?,
        activationTimeout: Duration
    ) {
        self.makeSession = makeSession
        self.activationTimeout = activationTimeout
    }

    var currentPlan: MenuBarVisibilityPlan? { appliedPlan }
    var activating: Bool { isActivating }

    func retire() {
        activationSequence &+= 1
        timeoutTask?.cancel()
        session?.invalidate()
        session = nil
        appliedPlan = nil
        isActivating = false
    }

    /// Applies a plan. The completion reports a structured failure, or nil on success.
    /// A nil factory result maps to `.unavailableOnBuild`; a late completion maps
    /// to `.activationTimedOut` via the timeout path taken by the caller's task.
    func apply(
        _ plan: MenuBarVisibilityPlan,
        isLive: @escaping () -> Bool,
        completion: @escaping @MainActor (MenuBarCleanupFailure?) -> Void
    ) {
        retire()
        let sequence = activationSequence
        appliedPlan = plan
        isActivating = true
        let candidate = makeSession(plan) { [weak self] error in
            guard let self, isLive(), self.activationSequence == sequence,
                  self.isActivating else { return }
            self.timeoutTask?.cancel()
            self.isActivating = false
            if let error {
                self.retire()
                completion(.activationFailed(underlying: error))
            } else {
                MenuBarCleanupDiagnostics.activated(plan: plan)
                completion(nil)
            }
        }
        // A factory may fail synchronously. Never retain that failed session.
        guard activationSequence == sequence else {
            candidate?.invalidate()
            return
        }
        guard let candidate else {
            retire()
            let failure = MenuBarCleanupFailure.unavailableOnBuild
            MenuBarCleanupDiagnostics.failed(failure)
            completion(failure)
            return
        }
        session = candidate
        guard isActivating else { return }
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: self?.activationTimeout ?? .seconds(5))
            guard !Task.isCancelled, let self, isLive(),
                  self.activationSequence == sequence, self.isActivating else { return }
            self.retire()
            let failure = MenuBarCleanupFailure.activationTimedOut
            MenuBarCleanupDiagnostics.failed(failure)
            completion(failure)
        }
    }
}

/// Owns Carbon hotkey registration and generation guarding.
///
/// One manager per controller run: `retire()` bumps the generation so stale
/// callbacks from a previous start/pause can never drive the new run.
@MainActor
final class MenuBarCleanupHotKeyManager {
    private let makeHotKeys: (@escaping @MainActor (UInt) -> Void) -> AnyObject?

    private var hotKeys: AnyObject?
    private var generation: UInt64 = 0
    private(set) var isAvailable = false

    init(makeHotKeys: @escaping (@escaping @MainActor (UInt) -> Void) -> AnyObject?) {
        self.makeHotKeys = makeHotKeys
    }

    func retire() {
        generation &+= 1
        hotKeys = nil
        isAvailable = false
    }

    func ensureRegistered(handler: @escaping @MainActor (UInt) -> Void) {
        guard hotKeys == nil else { return }
        generation &+= 1
        let sequence = generation
        hotKeys = makeHotKeys { [weak self] action in
            guard let self, self.generation == sequence else { return }
            handler(action)
        }
        isAvailable = hotKeys != nil
    }
}
