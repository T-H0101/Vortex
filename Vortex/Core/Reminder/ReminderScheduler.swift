import Foundation
import UserNotifications

extension Notification.Name {
    static let vortexReminderDelivered = Notification.Name("vortex.reminderDelivered")
}

final class ReminderScheduler: NSObject, @unchecked Sendable {
    static let shared = ReminderScheduler()

    private var pendingNotifications: [UUID: Date] = [:]
    private var testReminderTimers: [UUID: Timer] = [:]

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error)")
            }
            if !granted {
                print("Notification authorization was not granted. Vortex will still show in-app reminders while running.")
            }
        }
    }

    func scheduleReminder(for task: TaskItem) {
        guard let reminderDate = task.reminderDate else { return }
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

        let content = UNMutableNotificationContent()
        content.title = "Task Reminder"
        content.body = task.title
        content.sound = .default

        let trigger: UNNotificationTrigger
        switch task.reminderFrequency {
        case .fiveSeconds:
            return
        case .hourly:
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: true)
        case .daily:
            let components = Calendar.current.dateComponents([.hour, .minute], from: reminderDate)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        case .weekly:
            let components = Calendar.current.dateComponents([.weekday, .hour, .minute], from: reminderDate)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        case .none:
            return
        }

        let request = UNNotificationRequest(identifier: task.id.uuidString, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error)")
            }
        }

        pendingNotifications[task.id] = reminderDate
    }

    func scheduleFollowUpReminder(for task: TaskItem, minutesAfter: Int = 30) {
        let followUpDate = Date().addingTimeInterval(TimeInterval(minutesAfter * 60))

        let content = UNMutableNotificationContent()
        content.title = "Task Follow-up"
        content.body = "You haven't completed: \(task.title)"
        content.sound = .default

        let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: followUpDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)

        let request = UNNotificationRequest(identifier: "\(task.id.uuidString)-followup", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request)
    }

    func cancelReminder(for taskId: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [taskId.uuidString, "\(taskId.uuidString)-followup"])
        testReminderTimers[taskId]?.invalidate()
        testReminderTimers.removeValue(forKey: taskId)
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

        deliverSystemNotification(taskId: taskId, taskTitle: taskTitle, isTestReminder: true)
    }

    private func deliverSystemNotification(taskId: UUID, taskTitle: String, isTestReminder: Bool = false) {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self?.addNotificationRequest(taskId: taskId, taskTitle: taskTitle, isTestReminder: isTestReminder)
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error = error {
                        print("Notification authorization error: \(error)")
                    }
                    if granted {
                        self?.addNotificationRequest(taskId: taskId, taskTitle: taskTitle, isTestReminder: isTestReminder)
                    } else {
                        print("Notification authorization denied. System notifications will not be shown.")
                    }
                }
            case .denied:
                print("Notification authorization denied. Enable notifications for Vortex in System Settings to receive system banners.")
            @unknown default:
                print("Unknown notification authorization status: \(settings.authorizationStatus.rawValue)")
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
}

extension ReminderScheduler: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}
