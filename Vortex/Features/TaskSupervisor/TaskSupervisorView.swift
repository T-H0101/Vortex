import SwiftUI
import SwiftData

struct TaskSupervisorView: View {
    @StateObject private var viewModel = TaskSupervisorViewModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            headerView

            if viewModel.isAddingTask {
                addTaskView
            }

            taskListView

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vortexMaterial)
        .onAppear {
            viewModel.setup(modelContext: modelContext)
        }
    }

    private var headerView: some View {
        HStack {
            Text("Tasks")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.vortexText)

            Spacer()

            Button(action: { viewModel.isAddingTask.toggle() }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.vortexAccent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.vortexMaterialSecondary)
    }

    private var addTaskView: some View {
        VStack(spacing: 12) {
            TextField("Task title...", text: $viewModel.newTaskTitle)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)

            HStack {
                DatePicker("", selection: $viewModel.selectedDate, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()

                Spacer()

                Button("Cancel") {
                    viewModel.isAddingTask = false
                    viewModel.newTaskTitle = ""
                }
                .buttonStyle(.bordered)

                Button("Add") {
                    viewModel.addTask()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .background(Color.vortexMaterialSecondary.opacity(0.5))
    }

    private var taskListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if !viewModel.overdueTasks.isEmpty {
                    sectionHeader("Overdue")
                    ForEach(viewModel.overdueTasks, id: \.id) { task in
                        TaskRowView(task: task, onToggle: { viewModel.toggleTaskCompletion(task) }, onDelete: { viewModel.deleteTask(task) }, onReschedule: { viewModel.rescheduleTask(task) })
                            .background(Color.red.opacity(0.1))
                    }
                }

                if !viewModel.todayTasks.isEmpty {
                    sectionHeader("Today")
                    ForEach(viewModel.todayTasks, id: \.id) { task in
                        TaskRowView(task: task, onToggle: { viewModel.toggleTaskCompletion(task) }, onDelete: { viewModel.deleteTask(task) }, onReschedule: { viewModel.rescheduleTask(task) })
                    }
                }

                if !viewModel.completedTasks.isEmpty {
                    sectionHeader("Completed")
                    ForEach(viewModel.completedTasks, id: \.id) { task in
                        TaskRowView(task: task, onToggle: { viewModel.toggleTaskCompletion(task) }, onDelete: { viewModel.deleteTask(task) }, onReschedule: { viewModel.rescheduleTask(task) })
                            .opacity(0.6)
                    }
                }

                if viewModel.tasks.isEmpty && !viewModel.isAddingTask {
                    emptyStateView
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.vortexTextSecondary)
            Spacer()
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundColor(.vortexTextSecondary.opacity(0.5))

            Text("No tasks yet")
                .font(.system(size: 15))
                .foregroundColor(.vortexTextSecondary)

            Text("Tap + to add a task")
                .font(.system(size: 13))
                .foregroundColor(.vortexTextSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

struct TaskRowView: View {
    let task: TaskItem
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onReschedule: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(task.isCompleted ? .green : .vortexTextSecondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 14))
                    .foregroundColor(task.isCompleted ? .vortexTextSecondary : .vortexText)
                    .strikethrough(task.isCompleted)

                Text(task.formattedDueDate)
                    .font(.system(size: 11))
                    .foregroundColor(.vortexTextSecondary)
            }

            Spacer()

            if isHovered {
                HStack(spacing: 8) {
                    if task.isOverdue && !task.isCompleted {
                        Button(action: onReschedule) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 14))
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(.plain)
                        .help("Reschedule to tomorrow")
                    }

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isHovered ? Color.vortexMaterialSecondary : Color.clear)
        .cornerRadius(8)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}