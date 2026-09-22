import Foundation
import UserNotifications

/// Delivers threshold alerts via the system notification center.
/// Works only inside a proper app bundle (guarded so `swift run` dev
/// builds don't crash).
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private var authorized: Bool?

    override private init() {
        super.init()
        if isAvailable {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    private var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    /// Ask once, on first launch; remembers the answer.
    func requestAuthorizationIfNeeded() {
        guard isAvailable, AppSettings.shouldRequestNotificationPermission else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { [weak self] granted, _ in
            self?.authorized = granted
        }
    }

    func deliver(message: String) {
        deliver(title: "CodexMeter", body: message)
    }

    func deliver(title: String, body: String) {
        guard isAvailable, authorized != false else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: "codexmeter.\(UUID().uuidString)",
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
