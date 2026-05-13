import Foundation
import SwiftData

enum TaskPriority: String, Codable, CaseIterable {
    case urgent
    case high
    case medium
    case low

    var rank: Int {
        switch self {
        case .urgent: return 0
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        }
    }
}

enum TaskScheduleType: String, Codable, CaseIterable {
    case oneTime
    case daily
}

enum TaskReminderFrequency: String, Codable, CaseIterable {
    case none
    case atDueTime
    case fiveSeconds
    case hourly
    case daily
    case weekly
}

@Model
final class TaskItem {
    var id: UUID
    var title: String
    var isCompleted: Bool
    var dueDate: Date
    var createdAt: Date
    var completedAt: Date?
    var reminderDate: Date?
    var isReminderSent: Bool
    var notes: String
    var priorityRaw: String
    var scheduleTypeRaw: String
    var reminderFrequencyRaw: String

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        dueDate: Date = Date(),
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        reminderDate: Date? = nil,
        isReminderSent: Bool = false,
        notes: String = "",
        priority: TaskPriority = .medium,
        scheduleType: TaskScheduleType = .oneTime,
        reminderFrequency: TaskReminderFrequency = .atDueTime
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.reminderDate = reminderDate
        self.isReminderSent = isReminderSent
        self.notes = notes
        self.priorityRaw = priority.rawValue
        self.scheduleTypeRaw = scheduleType.rawValue
        self.reminderFrequencyRaw = reminderFrequency.rawValue
    }
}

extension TaskItem {
    private static let dueDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var isOverdue: Bool {
        !isCompleted && dueDate < Date()
    }

    var formattedDueDate: String {
        Self.dueDateFormatter.string(from: dueDate)
    }

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }

    var scheduleType: TaskScheduleType {
        get { TaskScheduleType(rawValue: scheduleTypeRaw) ?? .oneTime }
        set { scheduleTypeRaw = newValue.rawValue }
    }

    var reminderFrequency: TaskReminderFrequency {
        get { TaskReminderFrequency(rawValue: reminderFrequencyRaw) ?? .atDueTime }
        set { reminderFrequencyRaw = newValue.rawValue }
    }
}
