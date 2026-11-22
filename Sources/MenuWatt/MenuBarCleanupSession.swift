import Foundation
import MenuWattCore

/// Replaces native visibility assertions without releasing a confirmed
/// restriction while its successor is still activating.
@MainActor
final class MenuBarCleanupSessionManager {
    private struct Activation {
        let plan: MenuBarVisibilityPlan
        let session: any MenuBarCleanupSession
    }

    @MainActor
    private final class FactoryReply {
        var returned = false
        var result: Result<Void, MenuBarCleanupFailure>?
    }

    private let makeSession: (
        MenuBarVisibilityPlan, @escaping @MainActor (Error?) -> Void
    ) -> (any MenuBarCleanupSession)?
    private let activationTimeout: Duration

    private var active: Activation?
    private var pending: Activation?
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

    var currentPlan: MenuBarVisibilityPlan? { pending?.plan ?? active?.plan }
    var activating: Bool { pending != nil }
    var hasActiveSession: Bool { active != nil }
    var retainedAllowedBundles: Set<String> {
        Set(active?.plan.allowedBundles ?? []).union(pending?.plan.allowedBundles ?? [])
    }

    func retire() {
        cancelPending()
        active?.session.invalidate()
        active = nil
    }

    private func cancelPending() {
        activationSequence &+= 1
        timeoutTask?.cancel()
        timeoutTask = nil
        pending?.session.invalidate()
        pending = nil
    }

    func apply(
        _ plan: MenuBarVisibilityPlan,
        forceReapply: Bool = false,
        isLive: @escaping () -> Bool,
        completion: @escaping @MainActor (MenuBarCleanupFailure?) -> Void
    ) {
        cancelPending()
        if !forceReapply, active?.plan == plan {
            completion(nil)
            return
        }
        let sequence = activationSequence
        let finish: @MainActor (MenuBarCleanupFailure?) -> Void = { [weak self] failure in
            guard let self, isLive(), self.activationSequence == sequence,
                  let pending = self.pending else { return }
            self.timeoutTask?.cancel()
            self.timeoutTask = nil
            self.pending = nil
            if let failure {
                pending.session.invalidate()
                MenuBarCleanupDiagnostics.failed(failure)
            } else {
                let previous = self.active
                self.active = pending
                previous?.session.invalidate()
                MenuBarCleanupDiagnostics.activated(plan: plan)
            }
            completion(failure)
        }

        // Wait for the factory to return the handle before processing a reply.
        let earlyReply = FactoryReply()
        let candidate = makeSession(plan) { error in
            let failure = error.map { MenuBarCleanupFailure.activationFailed(underlying: $0) }
            if earlyReply.returned {
                finish(failure)
            } else if earlyReply.result == nil {
                earlyReply.result = failure.map(Result.failure) ?? .success(())
            }
        }
        earlyReply.returned = true
        guard let candidate else {
            let failure = switch earlyReply.result {
            case .failure(let error): error
            default: MenuBarCleanupFailure.unavailableOnBuild
            }
            MenuBarCleanupDiagnostics.failed(failure)
            completion(failure)
            return
        }
        pending = Activation(plan: plan, session: candidate)
        switch earlyReply.result {
        case .success: finish(nil)
        case .failure(let failure): finish(failure)
        case nil:
            let delay = activationTimeout
            timeoutTask = Task {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                finish(.activationTimedOut)
            }
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
