import Foundation
import MenuWattCore

/// Structured cleanup failures.
///
/// Thaw tracks menu bar failures in a dedicated ledger; this is the
/// lightweight equivalent. User-facing strings are intentionally unchanged:
/// `MenuBarCleanupController.errorMessage` still carries the same text, so
/// this type only adds categorization and logging, never new wording.
enum MenuBarCleanupFailure: Error, Sendable {
    case activationFailed(underlying: Error)
    case unavailableOnBuild
    case activationTimedOut

    var userMessage: String {
        switch self {
        case .activationFailed(let underlying):
            return underlying.localizedDescription
        case .unavailableOnBuild:
            return "Menu bar cleanup is unavailable on this macOS build."
        case .activationTimedOut:
            return "macOS did not finish updating the menu bar. Try enabling cleanup again."
        }
    }
}

@MainActor
enum MenuBarCleanupDiagnostics {
    private static let logger = MenuWattDiagnostics.cleanup

    static func activated(plan: MenuBarVisibilityPlan) {
        logger.info("Cleanup session active: \(plan.allowedBundles.count, privacy: .public) bundles, \(plan.allowedSystemItems.count, privacy: .public) system items")
    }

    static func failed(_ failure: MenuBarCleanupFailure) {
        logger.error("Cleanup session failed: \(failure.userMessage, privacy: .public)")
    }

    static func paused() {
        logger.info("Cleanup paused; visibility restriction released")
    }

    static func resumed() {
        logger.info("Cleanup resumed")
    }
}
