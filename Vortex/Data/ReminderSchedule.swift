import Foundation
import SwiftData

@Model
final class ReminderSchedule {
    var id: UUID
    var taskId: UUID
    var scheduledDate: Date
    var reminderType: ReminderType
    var isCompleted: Bool

    enum ReminderType: String, Codable {
        case initial
        case followUp
        case rescheduled
    }

    init(
        id: UUID = UUID(),
        taskId: UUID,
        scheduledDate: Date,
        reminderType: ReminderType = .initial,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.taskId = taskId
        self.scheduledDate = scheduledDate
        self.reminderType = reminderType
        self.isCompleted = isCompleted
    }
}