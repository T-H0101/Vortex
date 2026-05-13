import Foundation
import UserNotifications
import AppKit
import SwiftUI

extension Notification.Name {
    static let vortexReminderDelivered = Notification.Name("vortex.reminderDelivered")
}

final class ReminderScheduler: NSObject, @unchecked Sendable {
    static let shared = ReminderScheduler()

    private var pendingNotifications: [UUID: Date] = [:]
    private var testReminderTimers: [UUID: Timer] = [:]
    private var inAppReminderTimers: [UUID: Timer] = [:]

    private override init() {
        super.init()
        print("[Vortex] ReminderScheduler init start")
        UNUserNotificationCenter.current().delegate = self
        print("[Vortex] ReminderScheduler delegate set to self")

        // Check delegate assignment
        if UNUserNotificationCenter.current().delegate === self {
            print("[Vortex] Delegate correctly assigned to ReminderScheduler")
        } else {
            print("[Vortex] WARNING: Delegate may not be correctly assigned")
        }

        // Test immediate notification on startup to verify delivery works
        testImmediateNotification()
    }

    private func testImmediateNotification() {
        print("[Vortex] testImmediateNotification called")
        Task { @MainActor in
            let status = await NotificationPermissionManager.shared.currentStatus()
            print("[Vortex] testImmediateNotification: status = \(status.rawValue)")
            guard status == .authorized || status == .provisional else {
                print("[Vortex] Test notification skipped: status is \(status.rawValue)")
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "Vortex Test"
            content.body = "If you see this, system notifications are working!"
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2.0, repeats: false)
            let identifier = "vortex.immediate.test.\(UUID().uuidString)"
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )

            print("[Vortex] Scheduling immediate test notification with identifier: \(identifier)")
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("[Vortex] Immediate test notification failed: \(error)")
                } else {
                    print("[Vortex] Immediate test notification scheduled - check in 2 seconds")
                }
            }
        }
    }

    func requestAuthorization() {
        guard systemNotificationsEnabled else { return }

        Task { @MainActor in
            let status = await NotificationPermissionManager.shared.checkPermission()
            guard status == .notDetermined else { return }
            _ = await NotificationPermissionManager.shared.requestPermission()
        }
    }

    func updateSystemNotificationsEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: "systemNotificationsEnabled")

        if isEnabled {
            requestAuthorization()
        } else {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        }
    }

    func scheduleReminder(for task: TaskItem) {
        guard let reminderDate = task.reminderDate else {
            cancelReminder(for: task.id)
            return
        }

        if task.reminderFrequency == .none {
            cancelReminder(for: task.id)
            return
        }

        cancelReminder(for: task.id)

        if task.reminderFrequency == .fiveSeconds {
            scheduleFiveSecondTestReminder(for: task)
            pendingNotifications[task.id] = reminderDate
            return
        }

        // Schedule in-app reminder timer
        scheduleInAppReminder(for: task, reminderDate: reminderDate)

        // Always check and schedule system notification regardless of systemNotificationsEnabled
        Task { @MainActor in
            await self.scheduleSystemNotification(for: task, at: reminderDate, type: .reminder)
            // Also schedule due date notification
            await self.scheduleSystemNotification(for: task, at: task.dueDate, type: .due)
        }

        pendingNotifications[task.id] = reminderDate
    }

    enum NotificationType {
        case reminder
        case due

        var prefix: String {
            switch self {
            case .reminder: return "task-reminder"
            case .due: return "task-due"
            }
        }

        var title: String {
            switch self {
            case .reminder: return "Task Reminder"
            case .due: return "Task Due"
            }
        }
    }

    private func scheduleSystemNotification(for task: TaskItem, at date: Date, type: NotificationType) async {
        let status = await NotificationPermissionManager.shared.currentStatus()
        print("[Vortex] Notification permission status: \(status.rawValue) (\(String(describing: status))) for task \(task.id)")

        guard status == .authorized || status == .provisional else {
            print("[Vortex] Notification not scheduled: permission status is \(status.rawValue)")
            return
        }

        // Use timezone-aware comparison
        let now = Date()
        let timeZone = TimeZone.current
        print("[Vortex] Current timezone: \(timeZone.identifier), offset: \(timeZone.secondsFromGMT())")
        print("[Vortex] Scheduling \(type) notification for task '\(task.title)' at \(date), now: \(now)")

        // Check if date is in the past
        if date <= now {
            print("[Vortex] Notification not scheduled: \(type) date \(date) is in the past")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = type.title
        content.body = task.title
        content.sound = .default
        content.userInfo = ["taskId": task.id.uuidString]

        // Calculate interval instead of using calendar components
        let interval = date.timeIntervalSinceNow
        print("[Vortex] \(type) interval from now: \(interval) seconds")

        // Use time interval trigger for reliability
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)

        let identifier = "\(type.prefix)-\(task.id.uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        print("[Vortex] \(type) requesting notification add with identifier: \(identifier)")

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[Vortex] Failed to schedule \(type) notification: \(error)")
            } else {
                print("[Vortex] Successfully scheduled \(type) notification with identifier: \(identifier)")
            }

            // Print pending notifications count
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                print("[Vortex] Total pending notifications after \(type): \(requests.count)")
                for req in requests.prefix(10) {
                    print("[Vortex]   Pending: \(req.identifier)")
                }
            }
        }
    }

    func scheduleFollowUpReminder(for task: TaskItem, minutesAfter: Int = 30) {
        let followUpDate = Date().addingTimeInterval(TimeInterval(minutesAfter * 60))
        let delay = max(1, followUpDate.timeIntervalSinceNow)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, taskId = task.id, taskTitle = task.title] in
            self?.postInAppReminder(taskId: taskId, taskTitle: "You haven't completed: \(taskTitle)")
        }

        guard systemNotificationsEnabled else { return }

        Task { @MainActor in
            let status = await NotificationPermissionManager.shared.currentStatus()
            guard status == .authorized || status == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = "Task Follow-up"
            content.body = "You haven't completed: \(task.title)"
            content.sound = .default

            let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: followUpDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)

            let request = UNNotificationRequest(identifier: "\(task.id.uuidString)-followup", content: content, trigger: trigger)

            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Failed to schedule follow-up notification: \(error)")
                }
            }
        }
    }

    func cancelReminder(for taskId: UUID) {
        let identifiers = [
            "task-reminder-\(taskId.uuidString)",
            "task-due-\(taskId.uuidString)",
            "\(taskId.uuidString)-followup"
        ]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        testReminderTimers[taskId]?.invalidate()
        testReminderTimers.removeValue(forKey: taskId)
        inAppReminderTimers[taskId]?.invalidate()
        inAppReminderTimers.removeValue(forKey: taskId)
        pendingNotifications.removeValue(forKey: taskId)
    }

    func rescheduleForTomorrow(task: TaskItem) {
        guard let currentDueDate = task.reminderDate else { return }

        var components = Calendar.current.dateComponents([.year, .month, .day], from: currentDueDate)
        components.day! += 1

        if let newDate = Calendar.current.date(from: components) {
            let calendar = Calendar.current
            let newReminderDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: newDate) ?? newDate

            task.reminderDate = newReminderDate
            task.dueDate = newReminderDate

            cancelReminder(for: task.id)
            scheduleReminder(for: task)
        }
    }

    private func scheduleFiveSecondTestReminder(for task: TaskItem) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self, taskId = task.id, taskTitle = task.title] _ in
                self?.deliverTestReminder(taskId: taskId, taskTitle: taskTitle)
            }
            timer.tolerance = 0.2
            self.testReminderTimers[task.id] = timer
            timer.fire()
        }
    }

    private func deliverTestReminder(taskId: UUID, taskTitle: String) {
        if systemNotificationsEnabled {
            deliverSystemNotification(taskId: taskId, taskTitle: taskTitle, isTestReminder: true)
        } else {
            postInAppReminder(taskId: taskId, taskTitle: taskTitle)
        }
    }

    private func scheduleInAppReminder(for task: TaskItem, reminderDate: Date) {
        guard task.reminderFrequency != .none else { return }

        DispatchQueue.main.async { [weak self, taskId = task.id, taskTitle = task.title, frequency = task.reminderFrequency] in
            self?.scheduleNextInAppReminder(
                taskId: taskId,
                taskTitle: taskTitle,
                frequency: frequency,
                after: reminderDate
            )
        }
    }

    private func scheduleNextInAppReminder(
        taskId: UUID,
        taskTitle: String,
        frequency: TaskReminderFrequency,
        after date: Date
    ) {
        inAppReminderTimers[taskId]?.invalidate()

        let nextDate = nextFireDate(for: frequency, from: date)
        let interval = max(1, nextDate.timeIntervalSinceNow)
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.postInAppReminder(taskId: taskId, taskTitle: taskTitle)

            if let followingDate = self.nextRepeatingDate(for: frequency, after: nextDate) {
                self.scheduleNextInAppReminder(
                    taskId: taskId,
                    taskTitle: taskTitle,
                    frequency: frequency,
                    after: followingDate
                )
            }
        }
        timer.tolerance = min(30, interval * 0.1)
        inAppReminderTimers[taskId] = timer
    }

    private func nextFireDate(for frequency: TaskReminderFrequency, from date: Date) -> Date {
        guard date <= Date() else { return date }

        switch frequency {
        case .atDueTime:
            return date
        case .hourly:
            return Date().addingTimeInterval(3600)
        case .daily:
            return Calendar.current.nextDate(
                after: Date(),
                matching: Calendar.current.dateComponents([.hour, .minute], from: date),
                matchingPolicy: .nextTime
            ) ?? Date().addingTimeInterval(86400)
        case .weekly:
            return Calendar.current.nextDate(
                after: Date(),
                matching: Calendar.current.dateComponents([.weekday, .hour, .minute], from: date),
                matchingPolicy: .nextTime
            ) ?? Date().addingTimeInterval(604800)
        case .fiveSeconds:
            return Date().addingTimeInterval(5)
        case .none:
            return date
        }
    }

    private func nextRepeatingDate(for frequency: TaskReminderFrequency, after date: Date) -> Date? {
        switch frequency {
        case .atDueTime:
            return nil
        case .hourly:
            return date.addingTimeInterval(3600)
        case .daily:
            return Calendar.current.date(byAdding: .day, value: 1, to: date)
        case .weekly:
            return Calendar.current.date(byAdding: .weekOfYear, value: 1, to: date)
        case .fiveSeconds:
            return date.addingTimeInterval(5)
        case .none:
            return nil
        }
    }

    private func postInAppReminder(taskId: UUID, taskTitle: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .vortexReminderDelivered,
                object: nil,
                userInfo: [
                    "taskId": taskId,
                    "title": taskTitle
                ]
            )
        }
    }

    private func deliverSystemNotification(taskId: UUID, taskTitle: String, isTestReminder: Bool = false) {
        guard systemNotificationsEnabled else { return }

        Task { @MainActor in
            let status = await NotificationPermissionManager.shared.checkPermission()
            switch status {
            case .authorized, .provisional:
                self.addNotificationRequest(taskId: taskId, taskTitle: taskTitle, isTestReminder: isTestReminder)
            case .notDetermined:
                let granted = await NotificationPermissionManager.shared.requestPermission()
                if granted {
                    self.addNotificationRequest(taskId: taskId, taskTitle: taskTitle, isTestReminder: isTestReminder)
                } else if isTestReminder {
                    self.postInAppReminder(taskId: taskId, taskTitle: taskTitle)
                }
            case .denied:
                print("Notification authorization denied. Enable notifications for Vortex in System Settings to receive system banners.")
                if isTestReminder {
                    self.postInAppReminder(taskId: taskId, taskTitle: taskTitle)
                }
            @unknown default:
                print("Unknown notification authorization status: \(status.rawValue)")
                if isTestReminder {
                    self.postInAppReminder(taskId: taskId, taskTitle: taskTitle)
                }
            }
        }
    }

    private func addNotificationRequest(taskId: UUID, taskTitle: String, isTestReminder: Bool) {
        let content = UNMutableNotificationContent()
        content.title = isTestReminder ? "Task Reminder (Test)" : "Task Reminder"
        content.body = taskTitle
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(taskId.uuidString)-\(isTestReminder ? "test" : "reminder")-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to deliver notification: \(error)")
            }
        }
    }

    private var systemNotificationsEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "systemNotificationsEnabled") == nil {
            return true
        }
        return defaults.bool(forKey: "systemNotificationsEnabled")
    }
}

// Lightweight NotificationPermissionManager embedded here so the class is compiled into the same target
@MainActor
final class NotificationPermissionManager: ObservableObject {
    static let shared = NotificationPermissionManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private init() {
        // Ensure delegate is set when NotificationPermissionManager is first accessed
        UNUserNotificationCenter.current().delegate = ReminderScheduler.shared
    }

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

extension ReminderScheduler: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("[Vortex] willPresent called for notification: \(notification.request.identifier)")
        print("[Vortex] Notification content: title='\(notification.request.content.title)', body='\(notification.request.content.body)'")
        let taskId = UUID(uuidString: notification.request.identifier.components(separatedBy: "-").last ?? "") ?? UUID()
        postInAppReminder(taskId: taskId, taskTitle: notification.request.content.body)
        print("[Vortex] willPresent completionHandler called with [.banner, .sound, .badge]")
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        print("[Vortex] didReceive called for notification: \(response.notification.request.identifier)")
        let taskId = UUID(uuidString: response.notification.request.identifier.components(separatedBy: "-").last ?? "") ?? UUID()
        postInAppReminder(taskId: taskId, taskTitle: response.notification.request.content.body)
        completionHandler()
    }
}
