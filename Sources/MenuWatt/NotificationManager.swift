import AppKit
import Foundation
import UserNotifications
import MenuWattCore

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    enum Kind: String {
        case chargeComplete = "menuwatt.charge.complete"
        case lowBattery = "menuwatt.battery.low"
        case updateAvailable = "menuwatt.update.available"
    }

    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let logger = MenuWattDiagnostics.preferences

    private var lastFiredAt: [Kind: Date] = [:]
    private let coalescingInterval: TimeInterval = 5 * 60

    private override init() {
        super.init()
        center.delegate = self
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(NotificationInteraction.presentationOptions)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let url = NotificationInteraction.releaseURL(from: response.notification.request.content.userInfo) {
            Task { @MainActor in NSWorkspace.shared.open(url) }
        }
        completionHandler()
    }

    func requestAuthorizationIfNeeded() {
        Task { @MainActor in
            do {
                let settings = await center.notificationSettings()
                guard settings.authorizationStatus == .notDetermined else { return }
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                logger.info("Notification permission granted: \(granted, privacy: .public)")
            } catch {
                logger.error("Notification auth error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func notify(kind: Kind, title: String, body: String, userInfo: [String: String] = [:]) {
        if let last = lastFiredAt[kind], Date().timeIntervalSince(last) < coalescingInterval {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo

        let request = UNNotificationRequest(
            identifier: "\(kind.rawValue).\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        center.add(request) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.logger.error("Failed to post notification: \(error.localizedDescription, privacy: .public)")
            }
        }

        lastFiredAt[kind] = Date()
    }
}

/// Foreground presentation and the update alert's existing link payload.
enum NotificationInteraction {
    static var presentationOptions: UNNotificationPresentationOptions { [.banner, .list, .sound] }

    static func releaseURL(from userInfo: [AnyHashable: Any]) -> URL? {
        guard let raw = userInfo["url"] as? String, let url = URL(string: raw),
              url.scheme == "https", url.host == "github.com", url.user == nil, url.password == nil,
              url.path == "/Ketchio-dev/MenuWatt/releases"
                || url.path.hasPrefix("/Ketchio-dev/MenuWatt/releases/") else { return nil }
        return url
    }
}
