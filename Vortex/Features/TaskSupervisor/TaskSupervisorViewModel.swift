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
    @Published var isSaving: Bool = false

    private var modelContext: ModelContext?
    private var modelContainerObserver: NSObjectProtocol?
    private var cachedTodayTasks: [TaskItem]?
    private var cachedOverdueTasks: [TaskItem]?
    private var cachedCompletedTasks: [TaskItem]?
    private var tasksCacheDate: Date?

    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
        setupModelContainerObserver()
        fetchTasks()
    }

    private func setupModelContainerObserver() {
        modelContainerObserver.map(NotificationCenter.default.removeObserver)
        modelContainerObserver = NotificationCenter.default.addObserver(
            forName: .vortexTasksChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.fetchTasks()
            }
        }
    }

    func fetchTasks() {
        guard let modelContext = modelContext else { return }

        let descriptor = FetchDescriptor<TaskItem>(
            sortBy: [SortDescriptor(\.dueDate, order: .forward)]
        )

        do {
            tasks = sortTasks(try modelContext.fetch(descriptor))
            invalidateCache()
            rescheduleActiveReminders()
        } catch {
            print("Failed to fetch tasks: \(error)")
        }
    }

    private func invalidateCache() {
        cachedTodayTasks = nil
        cachedOverdueTasks = nil
        cachedCompletedTasks = nil
        tasksCacheDate = nil
    }

    func addTask() {
        guard let modelContext = modelContext else { return }
        let trimmedTitle = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        isSaving = true
        let task = TaskItem(
            title: trimmedTitle,
            dueDate: selectedDate,
            reminderDate: selectedDate.addingTimeInterval(-3600)
        )

        modelContext.insert(task)

        do {
            try modelContext.save()
            fetchTasks()
            NotificationCenter.default.post(name: .vortexTasksChanged, object: nil)
            newTaskTitle = ""
            isAddingTask = false
        } catch {
            print("Failed to save task: \(error)")
        }
        isSaving = false
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

        isSaving = true
        let reminderDate: Date?
        switch reminderFrequency {
        case .none:
            reminderDate = nil
        case .atDueTime:
            reminderDate = dueDate
        case .fiveSeconds:
            reminderDate = Date().addingTimeInterval(5)
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
            fetchTasks()
            NotificationCenter.default.post(name: .vortexTasksChanged, object: nil)
        } catch {
            print("Failed to create task: \(error)")
        }
        isSaving = false
    }

    func toggleTaskCompletion(_ task: TaskItem) {
        if task.isCompleted {
            task.isCompleted = false
            task.completedAt = nil
            ReminderScheduler.shared.scheduleReminder(for: task)
        } else {
            task.isCompleted = true
            task.completedAt = Date()
            ReminderScheduler.shared.cancelReminder(for: task.id)
            scheduleDeletionAfterCompletion(for: task)
        }

        do {
            try modelContext?.save()
            fetchTasks()
            NotificationCenter.default.post(name: .vortexTasksChanged, object: nil)
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
            NotificationCenter.default.post(name: .vortexTasksChanged, object: nil)
        } catch {
            print("Failed to delete task: \(error)")
        }
    }

    func rescheduleTask(_ task: TaskItem) {
        ReminderScheduler.shared.rescheduleForTomorrow(task: task)
        do {
            try modelContext?.save()
            fetchTasks()
            NotificationCenter.default.post(name: .vortexTasksChanged, object: nil)
        } catch {
            print("Failed to reschedule task: \(error)")
        }
    }

    var todayTasks: [TaskItem] {
        let now = Date()
        if cachedTodayTasks == nil || tasksCacheDate == nil || now.timeIntervalSince(tasksCacheDate!) > 1.0 {
            let calendar = Calendar.current
            cachedTodayTasks = tasks.filter { calendar.isDateInToday($0.dueDate) }
            tasksCacheDate = now
        }
        return cachedTodayTasks!
    }

    var overdueTasks: [TaskItem] {
        let now = Date()
        if cachedOverdueTasks == nil || tasksCacheDate == nil || now.timeIntervalSince(tasksCacheDate!) > 1.0 {
            cachedOverdueTasks = tasks.filter { $0.isOverdue }
            tasksCacheDate = now
        }
        return cachedOverdueTasks!
    }

    var completedTasks: [TaskItem] {
        let now = Date()
        if cachedCompletedTasks == nil || tasksCacheDate == nil || now.timeIntervalSince(tasksCacheDate!) > 1.0 {
            cachedCompletedTasks = sortTasks(tasks.filter { $0.isCompleted })
            tasksCacheDate = now
        }
        return cachedCompletedTasks!
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

    private func rescheduleActiveReminders() {
        for task in tasks where !task.isCompleted {
            ReminderScheduler.shared.scheduleReminder(for: task)
        }
    }

    private func scheduleDeletionAfterCompletion(for task: TaskItem) {
        let taskId = task.id

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self, let modelContext = self.modelContext else { return }

            let descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { item in
                    item.id == taskId
                }
            )

            do {
                guard let taskToDelete = try modelContext.fetch(descriptor).first,
                      taskToDelete.isCompleted else {
                    return
                }

                modelContext.delete(taskToDelete)
                try modelContext.save()
                self.fetchTasks()
                NotificationCenter.default.post(name: .vortexTasksChanged, object: nil)
            } catch {
                print("Failed to delete completed task after delay: \(error)")
            }
        }
    }

    deinit {
        if let modelContainerObserver {
            NotificationCenter.default.removeObserver(modelContainerObserver)
        }
    }
}
