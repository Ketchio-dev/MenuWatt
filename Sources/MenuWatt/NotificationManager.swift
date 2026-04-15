import Foundation
import UserNotifications
import MenuWattCore

@MainActor
final class NotificationManager {
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

    private init() {}

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
