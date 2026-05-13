import Foundation
import UserNotifications

final class ReminderScheduler: NSObject, @unchecked Sendable {
    static let shared = ReminderScheduler()

    private var pendingNotifications: [UUID: Date] = [:]

    private override init() {
        super.init()
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error)")
            }
        }
    }

    func scheduleReminder(for task: TaskItem) {
        guard let reminderDate = task.reminderDate else { return }
        if task.reminderFrequency == .none {
            cancelReminder(for: task.id)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Task Reminder"
        content.body = task.title
        content.sound = .default

        let trigger: UNNotificationTrigger
        switch task.reminderFrequency {
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
}