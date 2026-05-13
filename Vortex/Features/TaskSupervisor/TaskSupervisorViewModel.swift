import Foundation
import SwiftUI
import SwiftData

@MainActor
final class TaskSupervisorViewModel: ObservableObject {
    @Published var tasks: [TaskItem] = []
    @Published var newTaskTitle: String = ""
    @Published var selectedDate: Date = Date()
    @Published var isAddingTask: Bool = false
    @Published var editingTask: TaskItem?

    private var modelContext: ModelContext?

    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchTasks()
    }

    func fetchTasks() {
        guard let modelContext = modelContext else { return }

        let descriptor = FetchDescriptor<TaskItem>(
            sortBy: [SortDescriptor(\.dueDate, order: .forward)]
        )

        do {
            tasks = sortTasks(try modelContext.fetch(descriptor))
        } catch {
            print("Failed to fetch tasks: \(error)")
        }
    }

    func addTask() {
        guard let modelContext = modelContext else { return }
        let trimmedTitle = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let task = TaskItem(
            title: trimmedTitle,
            dueDate: selectedDate,
            reminderDate: selectedDate.addingTimeInterval(-3600)
        )

        modelContext.insert(task)

        do {
            try modelContext.save()
            ReminderScheduler.shared.scheduleReminder(for: task)
            fetchTasks()
            newTaskTitle = ""
            isAddingTask = false
        } catch {
            print("Failed to save task: \(error)")
        }
    }

    func createTask(
        title: String,
        dueDate: Date,
        scheduleType: TaskScheduleType,
        priority: TaskPriority,
        reminderFrequency: TaskReminderFrequency,
        notes: String = ""
    ) {
        guard let modelContext = modelContext else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let reminderDate: Date?
        switch reminderFrequency {
        case .none:
            reminderDate = nil
        case .hourly:
            reminderDate = Date().addingTimeInterval(3600)
        case .daily, .weekly:
            reminderDate = dueDate
        }

        let task = TaskItem(
            title: trimmedTitle,
            dueDate: dueDate,
            reminderDate: reminderDate,
            notes: notes,
            priority: priority,
            scheduleType: scheduleType,
            reminderFrequency: reminderFrequency
        )

        modelContext.insert(task)

        do {
            try modelContext.save()
            ReminderScheduler.shared.scheduleReminder(for: task)
            fetchTasks()
        } catch {
            print("Failed to create task: \(error)")
        }
    }

    func toggleTaskCompletion(_ task: TaskItem) {
        task.isCompleted.toggle()
        task.completedAt = task.isCompleted ? Date() : nil

        if task.isCompleted {
            ReminderScheduler.shared.cancelReminder(for: task.id)
            modelContext?.delete(task)
        } else {
            ReminderScheduler.shared.scheduleReminder(for: task)
        }

        do {
            try modelContext?.save()
            fetchTasks()
        } catch {
            print("Failed to update task completion: \(error)")
        }
    }

    func deleteTask(_ task: TaskItem) {
        guard let modelContext = modelContext else { return }

        ReminderScheduler.shared.cancelReminder(for: task.id)
        modelContext.delete(task)

        do {
            try modelContext.save()
            fetchTasks()
        } catch {
            print("Failed to delete task: \(error)")
        }
    }

    func rescheduleTask(_ task: TaskItem) {
        ReminderScheduler.shared.rescheduleForTomorrow(task: task)
        do {
            try modelContext?.save()
            fetchTasks()
        } catch {
            print("Failed to reschedule task: \(error)")
        }
    }

    var todayTasks: [TaskItem] {
        let calendar = Calendar.current
        return tasks.filter { calendar.isDateInToday($0.dueDate) }
    }

    var overdueTasks: [TaskItem] {
        tasks.filter { $0.isOverdue }
    }

    var completedTasks: [TaskItem] {
        sortTasks(tasks.filter { $0.isCompleted })
    }

    private func sortTasks(_ items: [TaskItem]) -> [TaskItem] {
        items.sorted { lhs, rhs in
            if lhs.priority.rank != rhs.priority.rank {
                return lhs.priority.rank < rhs.priority.rank
            }
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted
            }
            return lhs.dueDate < rhs.dueDate
        }
    }
}