import Foundation
import UserNotifications
import AppKit
import SwiftUI

@MainActor
final class NotificationPermissionManager: ObservableObject {
    static let shared = NotificationPermissionManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private init() {}

    func checkPermission() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        let settings: UNNotificationSettings = await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
        authorizationStatus = settings.authorizationStatus
        return authorizationStatus
    }

    func currentStatus() async -> UNAuthorizationStatus {
        return await checkPermission()
    }

    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await checkPermission()
            return granted
        } catch {
            print("Notification request failed: \(error)")
            return false
        }
    }

    var canSendSystemNotification: Bool {
        switch authorizationStatus {
        case .authorized, .provisional:
            return true
        default:
            return false
        }
    }

    func sendTestNotification(title: String = "Vortex Test", body: String = "This is a test notification from Vortex.") {
        Task { @MainActor in
            let status = await self.currentStatus()
            guard status == .authorized || status == .provisional else {
                NotificationCenter.default.post(
                    name: .vortexReminderDelivered,
                    object: nil,
                    userInfo: [
                        "taskId": UUID(),
                        "title": title
                    ]
                )
                return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.0, repeats: false)
            let req = UNNotificationRequest(identifier: "vortex.test.notification.\(UUID().uuidString)", content: content, trigger: trigger)

            UNUserNotificationCenter.current().add(req) { error in
                if let error = error {
                    print("Failed to schedule test notification: \(error)")
                }
            }
        }
    }

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }

    func validateBundleIdentifier(expected: String) {
        let current = Bundle.main.bundleIdentifier ?? "(none)"
        if current != expected {
            print("[Vortex] Warning: bundle identifier mismatch. Expected: \(expected) actual: \(current)")
        }
    }
}
