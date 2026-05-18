import SwiftUI
import SwiftData
import AppKit

struct MainTabView: View {
    private enum MainTab: Int {
        case tasks = 0
        case activity = 1
        case settings = 2
    }

    @AppStorage("selectedTab") private var selectedTabRaw: Int = 0
    @ObservedObject var edgeDocking: EdgeDockingController
    @StateObject private var taskViewModel = TaskSupervisorViewModel()
    @StateObject private var activityViewModel = ActivityMonitorViewModel()
    @State private var visibleReminder: InAppReminder?

    @AppStorage("dockPreference") private var dockPreferenceRaw = DockSide.right.rawValue
    @AppStorage("launchDocked") private var launchDocked = true
    @AppStorage("autoExpandOnHover") private var autoExpandOnHover = true
    @AppStorage("autoReturnToDock") private var autoReturnToDock = true
    @AppStorage("compactPreviewEnabled") private var compactPreviewEnabled = true
    @AppStorage("collapseDelaySeconds") private var collapseDelaySeconds = 0.9
    @AppStorage("returnToDockDelaySeconds") private var returnToDockDelaySeconds = 1.2
    @AppStorage("dockAnimationDuration") private var dockAnimationDuration = 0.24
    @AppStorage("activityRefreshInterval") private var activityRefreshInterval = 8.0
    @AppStorage("recentAppsLimit") private var recentAppsLimit = 100
    @AppStorage("recentWebPagesLimit") private var recentWebPagesLimit = 100
    @AppStorage("capsuleOpacity") private var capsuleOpacity = 0.76
    @AppStorage("glassTintHex") private var glassTintHex = "#F4F7FF"
    @AppStorage("glassTintOpacity") private var glassTintOpacity = 0.26
    @AppStorage("systemNotificationsEnabled") private var systemNotificationsEnabled = true
    @AppStorage("appLanguage") private var appLanguage = "zh-Hans"

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if edgeDocking.expansionState == .expanded {
                VStack(spacing: 0) {
                    headerBar
                    tabContent
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                collapsedPreview
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(width: edgeDocking.contentSize.width, height: edgeDocking.contentSize.height)
        .background(backgroundView)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if edgeDocking.expansionState == .expanded {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
            }
        }
        .overlay {
            if let visibleReminder {
                reminderOverlay(for: visibleReminder)
            }
        }
        .shadow(
            color: edgeDocking.expansionState == .expanded ? .black.opacity(0.18) : .clear,
            radius: 12,
            x: 0,
            y: 5
        )
        .opacity(edgeDocking.expansionState == .collapsed ? 0.94 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: edgeDocking.expansionState)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: edgeDocking.dockedSide)
        .onHover { hovering in
            edgeDocking.handleHoverChange(isHovering: hovering)
        }
        .onAppear {
            taskViewModel.setup(modelContext: modelContext)
            activityViewModel.startTracking()
            activityViewModel.updateRecentLimits(appLimit: recentAppsLimit, webLimit: recentWebPagesLimit)
            applySettingsToDocking()
        }
        .onDisappear {
            activityViewModel.stopTracking()
        }
        .onReceive(NotificationCenter.default.publisher(for: .vortexShowSettings)) { _ in
            selectedTabRaw = MainTab.settings.rawValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .vortexReminderDelivered)) { notification in
            showInAppReminder(from: notification)
        }
        .onChange(of: dockPreferenceRaw) { _, _ in
            applySettingsToDocking()
        }
        .onChange(of: autoExpandOnHover) { _, _ in
            applySettingsToDocking()
        }
        .onChange(of: autoReturnToDock) { _, _ in
            applySettingsToDocking()
        }
        .onChange(of: returnToDockDelaySeconds) { _, _ in
            applySettingsToDocking()
        }
        .onChange(of: collapseDelaySeconds) { _, _ in
            applySettingsToDocking()
        }
        .onChange(of: dockAnimationDuration) { _, _ in
            applySettingsToDocking()
        }
        .onChange(of: activityRefreshInterval) { _, newValue in
            activityViewModel.updateActivityRefreshInterval(newValue)
        }
        .onChange(of: recentAppsLimit) { _, newValue in
            activityViewModel.updateRecentLimits(appLimit: newValue, webLimit: recentWebPagesLimit)
        }
        .onChange(of: recentWebPagesLimit) { _, newValue in
            activityViewModel.updateRecentLimits(appLimit: recentAppsLimit, webLimit: newValue)
        }
        .onChange(of: systemNotificationsEnabled) { _, newValue in
            ReminderScheduler.shared.updateSystemNotificationsEnabled(newValue)
            if newValue {
                Task {
                    let status = await NotificationPermissionManager.shared.currentStatus()
                    if status == .notDetermined {
                        _ = await NotificationPermissionManager.shared.requestPermission()
                    }
                }
            }
            taskViewModel.fetchTasks()
        }
    }

    private func glassBackground(material: NSVisualEffectView.Material, tintOpacity: Double) -> some View {
        ZStack {
            VisualEffectView(material: material, blendingMode: .behindWindow)
            Color(hex: glassTintHex)
                .opacity(tintOpacity)
            LinearGradient(
                colors: [
                    .white.opacity(0.16),
                    .white.opacity(0.04),
                    .black.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        if edgeDocking.expansionState == .expanded {
            glassBackground(material: .underWindowBackground, tintOpacity: glassTintOpacity)
        } else {
            glassBackground(material: .hudWindow, tintOpacity: max(0.12, glassTintOpacity * 0.8))
                .opacity(capsuleOpacity)
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            tabSelector
                .layoutPriority(1)

            Spacer()

            Button(action: { edgeDocking.toggleExpansion() }) {
                Image(systemName: "rectangle.compress.vertical")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 46)
    }

    private var tabSelector: some View {
        HStack(spacing: 4) {
            tabButton(L("任务", "Tasks"), icon: "checklist", tab: .tasks)
            tabButton(L("活动", "Activity"), icon: "waveform", tab: .activity)
            tabButton(L("设置", "Settings"), icon: "slider.horizontal.3", tab: .settings)
        }
    }

    private func tabButton(_ title: String, icon: String, tab: MainTab) -> some View {
        let isCompactChinese = appLanguage != "en"
        return Button(action: { selectedTabRaw = tab.rawValue }) {
            HStack(spacing: 6) {
                if !isCompactChinese {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                }
                Text(title)
                    .font(.system(size: isCompactChinese ? 11 : 12, weight: .medium))
            }
            .foregroundColor(selectedTabRaw == tab.rawValue ? .primary : .secondary)
            .padding(.horizontal, isCompactChinese ? 8 : 10)
            .padding(.vertical, 6)
            .background(selectedTabRaw == tab.rawValue ? Color.primary.opacity(0.15) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var tabContent: some View {
        VStack(spacing: 0) {
            switch MainTab(rawValue: selectedTabRaw) {
            case .tasks:
                TaskTabView(viewModel: taskViewModel, appLanguage: appLanguage)
            case .activity:
                ActivityTabView(viewModel: activityViewModel, appLanguage: appLanguage)
            case .settings:
                SettingsTabView(
                    appLanguage: $appLanguage,
                    dockPreferenceRaw: $dockPreferenceRaw,
                    launchDocked: $launchDocked,
                    autoExpandOnHover: $autoExpandOnHover,
                    autoReturnToDock: $autoReturnToDock,
                    compactPreviewEnabled: $compactPreviewEnabled,
                    collapseDelaySeconds: $collapseDelaySeconds,
                    returnToDockDelaySeconds: $returnToDockDelaySeconds,
                    dockAnimationDuration: $dockAnimationDuration,
                    activityRefreshInterval: $activityRefreshInterval,
                    recentAppsLimit: $recentAppsLimit,
                    recentWebPagesLimit: $recentWebPagesLimit,
                    capsuleOpacity: $capsuleOpacity,
                    glassTintHex: $glassTintHex,
                    glassTintOpacity: $glassTintOpacity,
                    systemNotificationsEnabled: $systemNotificationsEnabled
                )
            case .none:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var collapsedPreview: some View {
        if let visibleReminder {
            collapsedReminderPreview(visibleReminder)
        } else if edgeDocking.dockedSide == .top {
            topCollapsedPreview
        } else {
            sideCollapsedPreview
        }
    }

    private var topCollapsedPreview: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(pendingTaskCount) \(L("个待办", "pending"))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                Text("\(L("当前：", "Active: "))\(latestActivityName)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: {
                selectedTabRaw = MainTab.settings.rawValue
                edgeDocking.expandWindow()
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var sideCollapsedPreview: some View {
        VStack(spacing: 10) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.accentColor)

            Capsule()
                .fill(Color.primary.opacity(0.15))
                .frame(width: 2, height: 54)

            if compactPreviewEnabled {
                Circle()
                    .fill(pendingTaskCount > 0 ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: 8, height: 8)
            }

            Button(action: {
                selectedTabRaw = MainTab.settings.rawValue
                edgeDocking.expandWindow()
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 10)
    }

    private var pendingTaskCount: Int {
        taskViewModel.tasks.filter { !$0.isCompleted }.count
    }

    private var latestActivityName: String {
        activityViewModel.activities.first?.appName ?? "Idle"
    }

    private var cornerRadius: CGFloat {
        if edgeDocking.expansionState == .expanded {
            return 14
        }
        return edgeDocking.dockedSide == .top ? 24 : 30
    }

    private func applySettingsToDocking() {
        let side = DockSide(rawValue: dockPreferenceRaw) ?? .right
        edgeDocking.configure(
            preferredSide: side,
            autoExpandOnHover: autoExpandOnHover,
            autoReturnToDock: autoReturnToDock,
            collapseDelay: collapseDelaySeconds,
            returnToDockDelay: returnToDockDelaySeconds,
            animationDuration: dockAnimationDuration
        )
        activityViewModel.updateActivityRefreshInterval(activityRefreshInterval)
    }

    private func L(_ zh: String, _ en: String) -> String {
        appLanguage == "en" ? en : zh
    }

    private func showInAppReminder(from notification: Notification) {
        let title = notification.userInfo?["title"] as? String ?? L("任务提醒", "Task Reminder")
        let reminder = InAppReminder(title: title, message: L("该处理这个任务了", "Time to handle this task"))

        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            visibleReminder = reminder
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) {
            guard visibleReminder?.id == reminder.id else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                visibleReminder = nil
            }
        }
    }

    @ViewBuilder
    private func reminderOverlay(for reminder: InAppReminder) -> some View {
        if edgeDocking.expansionState == .expanded {
            InAppReminderView(reminder: reminder)
                .padding(24)
                .transition(.scale(scale: 0.94).combined(with: .opacity))
                .onTapGesture {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        visibleReminder = nil
                    }
                }
        }
    }

    @ViewBuilder
    private func collapsedReminderPreview(_ reminder: InAppReminder) -> some View {
        if edgeDocking.dockedSide == .top {
            HStack(spacing: 8) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.yellow)

                VStack(alignment: .leading, spacing: 1) {
                    Text(L("任务提醒", "Reminder"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(reminder.title)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .onTapGesture {
                edgeDocking.expandWindow()
            }
        } else {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.yellow)
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                        .offset(x: 3, y: -2)
                }

                Text(L("提醒", "Alert"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.primary)

                Text(reminder.title)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .frame(width: 44)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 10)
            .onTapGesture {
                edgeDocking.expandWindow()
            }
        }
    }
}

private struct InAppReminder: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

private struct InAppReminderView: View {
    let reminder: InAppReminder

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.yellow)

            Text("Task Reminder")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            Text(reminder.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(reminder.message)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(maxWidth: 320)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.32), radius: 18, x: 0, y: 8)
    }
}

struct TaskTabView: View {
    @ObservedObject var viewModel: TaskSupervisorViewModel
    let appLanguage: String

    @State private var isPresentingComposer = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack {
                    Text(L("任务", "Tasks"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: { withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { isPresentingComposer = true } }) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.accentColor))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                if !viewModel.overdueTasks.isEmpty {
                    overdueWarningBanner
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        if viewModel.tasks.isEmpty {
                            emptyTaskState
                        } else {
                            ForEach(viewModel.tasks, id: \.id) { task in
                                TaskRowCompact(
                                    task: task,
                                    appLanguage: appLanguage,
                                    onToggle: { viewModel.toggleTaskCompletion(task) },
                                    onDelete: { viewModel.deleteTask(task) }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }

            if isPresentingComposer {
                Color.black.opacity(0.24)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { isPresentingComposer = false }
                    }

                TaskComposerView(
                    appLanguage: appLanguage,
                    onCancel: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { isPresentingComposer = false }
                    },
                    onCreate: { title, dueDate, scheduleType, priority, reminderFrequency, notes in
                        viewModel.createTask(
                            title: title,
                            dueDate: dueDate,
                            scheduleType: scheduleType,
                            priority: priority,
                            reminderFrequency: reminderFrequency,
                            notes: notes
                        )
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { isPresentingComposer = false }
                    }
                )
                .background(
                    VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isPresentingComposer)
    }

    private var overdueWarningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.red)

            Text(L("有任务已超时", "Tasks overdue"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.red)

            Spacer()

            Text("\(viewModel.overdueTasks.count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.red))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.red.opacity(0.35), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var emptyTaskState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 30))
                .foregroundColor(.secondary.opacity(0.5))
            Text(L("暂无任务", "No tasks"))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func L(_ zh: String, _ en: String) -> String {
        appLanguage == "en" ? en : zh
    }
}

struct TaskRowCompact: View {
    let task: TaskItem
    let appLanguage: String
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(task.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if task.isOverdue {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.red)
                    }
                    Image(systemName: priorityIcon(task.priority))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(task.isOverdue ? .red : priorityColor(task.priority))
                    Text(task.title)
                        .font(.system(size: 13))
                        .foregroundColor(task.isOverdue ? .red : (task.isCompleted ? .secondary : .primary))
                        .strikethrough(task.isCompleted)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(task.formattedDueDate)
                        .font(.system(size: 10))
                        .foregroundColor(task.isOverdue ? .red.opacity(0.85) : .secondary)
                    Text(scheduleLabel(task.scheduleType, appLanguage: appLanguage))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(reminderLabel(task.reminderFrequency, appLanguage: appLanguage))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(priorityLabel(task.priority, appLanguage: appLanguage))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(priorityColor(task.priority))
                }
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(task.isOverdue ? Color.red.opacity(0.12) : Color.primary.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(task.isOverdue ? Color.red.opacity(0.35) : Color.clear, lineWidth: 0.8)
        )
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func priorityLabel(_ priority: TaskPriority, appLanguage: String) -> String {
        switch priority {
        case .urgent: return appLanguage == "en" ? "Urgent" : "紧急"
        case .high: return appLanguage == "en" ? "High" : "高"
        case .medium: return appLanguage == "en" ? "Medium" : "中"
        case .low: return appLanguage == "en" ? "Low" : "低"
        }
    }

    private func scheduleLabel(_ type: TaskScheduleType, appLanguage: String) -> String {
        switch type {
        case .oneTime: return appLanguage == "en" ? "Deadline" : "截止"
        case .daily: return appLanguage == "en" ? "Daily" : "每日"
        }
    }

    private func reminderLabel(_ frequency: TaskReminderFrequency, appLanguage: String) -> String {
        switch frequency {
        case .none: return appLanguage == "en" ? "No reminder" : "不提醒"
        case .atDueTime: return appLanguage == "en" ? "Due time" : "到期时"
        case .fiveSeconds: return appLanguage == "en" ? "Every 5s" : "每5秒"
        case .hourly: return appLanguage == "en" ? "Hourly" : "每小时"
        case .daily: return appLanguage == "en" ? "Daily" : "每天"
        case .weekly: return appLanguage == "en" ? "Weekly" : "每周"
        }
    }
}

struct TaskComposerView: View {
    let appLanguage: String
    let onCancel: () -> Void
    let onCreate: (String, Date, TaskScheduleType, TaskPriority, TaskReminderFrequency, String) -> Void

    @State private var title = ""
    @State private var selectedYear = Calendar.current.component(.year, from: Date())
    @State private var selectedMonth = Calendar.current.component(.month, from: Date())
    @State private var selectedDay = Calendar.current.component(.day, from: Date())
    @State private var selectedHour = Calendar.current.component(.hour, from: Date())
    @State private var selectedMinute = Calendar.current.component(.minute, from: Date())
    @State private var scheduleType: TaskScheduleType = .oneTime
    @State private var priority: TaskPriority = .medium
    @State private var reminderFrequency: TaskReminderFrequency = .atDueTime
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("新增任务", "New Task"))
                .font(.system(size: 18, weight: .semibold))

            TextField(L("任务标题", "Task title"), text: $title)
                .textFieldStyle(.roundedBorder)
                .focusable()
                .onKeyPress(.return) {
                    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        onCreate(title, selectedDueDate, scheduleType, priority, reminderFrequency, notes)
                    }
                    return .handled
                }

            deadlinePickerGrid

            Picker(L("任务类型", "Task schedule"), selection: $scheduleType) {
                Text(L("单次截止", "Deadline")).tag(TaskScheduleType.oneTime)
                Text(L("每日任务", "Daily")).tag(TaskScheduleType.daily)
            }
            .pickerStyle(.segmented)

            Picker(L("优先级", "Priority"), selection: $priority) {
                ForEach(TaskPriority.allCases, id: \.rawValue) { level in
                    Text(priorityLabel(level)).tag(level)
                }
            }
            .pickerStyle(.segmented)

            Picker(L("提醒方式", "Reminder"), selection: $reminderFrequency) {
                Text(L("无", "None")).tag(TaskReminderFrequency.none)
                Text(L("到期时", "Due time")).tag(TaskReminderFrequency.atDueTime)
                Text(L("每小时", "Hourly")).tag(TaskReminderFrequency.hourly)
                Text(L("每天", "Daily")).tag(TaskReminderFrequency.daily)
                Text(L("每周", "Weekly")).tag(TaskReminderFrequency.weekly)
            }
            .pickerStyle(.menu)

            TextField(L("备注（可选）", "Notes (optional)"), text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            HStack {
                Spacer()
                Button(L("取消", "Cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                Button(L("添加", "Add")) {
                    onCreate(title, selectedDueDate, scheduleType, priority, reminderFrequency, notes)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 420)
        .onKeyPress(.escape) {
            onCancel()
            return .handled
        }
    }

    private func priorityLabel(_ level: TaskPriority) -> String {
        switch level {
        case .urgent: return L("紧急", "Urgent")
        case .high: return L("高", "High")
        case .medium: return L("中", "Medium")
        case .low: return L("低", "Low")
        }
    }

    private func L(_ zh: String, _ en: String) -> String {
        appLanguage == "en" ? en : zh
    }

    private var deadlinePickerGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("截止时间", "Due time"))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                componentPicker(L("年", "Year"), selection: $selectedYear, values: yearOptions) { "\($0)" }
                componentPicker(L("月", "Month"), selection: $selectedMonth, values: Array(1...12)) { "\($0)" }
                componentPicker(L("日", "Day"), selection: $selectedDay, values: Array(1...daysInSelectedMonth)) { "\($0)" }
            }

            HStack(spacing: 8) {
                componentPicker(L("时", "Hour"), selection: $selectedHour, values: Array(0...23)) { String(format: "%02d", $0) }
                componentPicker(L("分", "Minute"), selection: $selectedMinute, values: Array(0...59)) { String(format: "%02d", $0) }
            }
        }
        .onChange(of: selectedYear) { _, _ in
            clampSelectedDay()
        }
        .onChange(of: selectedMonth) { _, _ in
            clampSelectedDay()
        }
    }

    private func componentPicker(
        _ title: String,
        selection: Binding<Int>,
        values: [Int],
        label: @escaping (Int) -> String
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(values, id: \.self) { value in
                Text(label(value)).tag(value)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity)
    }

    private var selectedDueDate: Date {
        var components = DateComponents()
        components.calendar = Calendar.current
        components.timeZone = TimeZone.current
        components.year = selectedYear
        components.month = selectedMonth
        components.day = min(selectedDay, daysInSelectedMonth)
        components.hour = selectedHour
        components.minute = selectedMinute
        return Calendar.current.date(from: components) ?? Date()
    }

    private var yearOptions: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array(currentYear...(currentYear + 10))
    }

    private var daysInSelectedMonth: Int {
        var components = DateComponents()
        components.calendar = Calendar.current
        components.timeZone = TimeZone.current
        components.year = selectedYear
        components.month = selectedMonth

        guard let date = Calendar.current.date(from: components),
              let range = Calendar.current.range(of: .day, in: .month, for: date) else {
            return 31
        }

        return range.count
    }

    private func clampSelectedDay() {
        selectedDay = min(selectedDay, daysInSelectedMonth)
    }
}

private func priorityIcon(_ priority: TaskPriority) -> String {
    switch priority {
    case .urgent: return "exclamationmark.triangle.fill"
    case .high: return "flag.fill"
    case .medium: return "flag"
    case .low: return "minus.circle"
    }
}

private func priorityColor(_ priority: TaskPriority) -> Color {
    switch priority {
    case .urgent: return .red
    case .high: return .orange
    case .medium: return .blue
    case .low: return .secondary
    }
}

struct ActivityTabView: View {
    @ObservedObject var viewModel: ActivityMonitorViewModel
    let appLanguage: String
    @State private var selectedSection = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $selectedSection) {
                    Text(L("最近应用", "Recent apps")).tag(0)
                    Text(L("最近网页", "Recent web pages")).tag(1)
                    Text(L("最近终端", "Recent terminals")).tag(2)
                }
                .pickerStyle(.segmented)

                Spacer(minLength: 8)

                Button(action: refreshCurrentSection) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            ScrollView {
                LazyVStack(spacing: 4) {
                    switch selectedSection {
                    case 0:
                        ForEach(viewModel.activities, id: \.id) { activity in
                            ActivityRowCompact(activity: activity) {
                                viewModel.activateActivity(activity)
                            }
                        }
                    case 1:
                        if viewModel.isLoadingBrowser {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.8)
                                Spacer()
                            }
                            .padding(.vertical, 20)
                        } else if viewModel.recentWebPages.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "globe")
                                    .font(.system(size: 26))
                                    .foregroundColor(.secondary.opacity(0.5))
                                Text(L("暂无最近网页", "No recent web pages"))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        } else {
                            ForEach(viewModel.recentWebPages) { page in
                                WebPageRow(tab: page) {
                                    viewModel.activateWebPage(page)
                                }
                            }
                        }
                    case 2:
                        terminalSection
                    default:
                        EmptyView()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .onAppear {
            refreshCurrentSection()
        }
        .onChange(of: selectedSection) { _, newValue in
            if newValue == 1 {
                viewModel.selectedBrowser = "Safari"
            } else if newValue == 2 {
                viewModel.selectedBrowser = "Terminal"
            }
            refreshCurrentSection()
        }
    }

    private var terminalSection: some View {
        VStack(spacing: 0) {
            if viewModel.isLoadingBrowser {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if viewModel.browserTabs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 26))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(L("暂无最近终端", "No recent terminals"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Button(action: {
                        viewModel.selectedBrowser = "Terminal"
                        viewModel.refreshBrowserTabs()
                    }) {
                        Text(L("刷新", "Refresh"))
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(viewModel.browserTabs) { tab in
                    BrowserTabRow(tab: tab) {
                        viewModel.activateWebPage(tab)
                    }
                }
            }
        }
    }

    private func refreshCurrentSection() {
        switch selectedSection {
        case 0:
            viewModel.refreshActivities()
        case 1:
            viewModel.selectedBrowser = "Safari"
            viewModel.refreshRecentWebPages()
        case 2:
            viewModel.selectedBrowser = "Terminal"
            viewModel.refreshBrowserTabs()
        default:
            break
        }
    }

    private func L(_ zh: String, _ en: String) -> String {
        appLanguage == "en" ? en : zh
    }
}

struct ActivityRowCompact: View {
    let activity: ActivityItem
    let onActivate: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let iconData = activity.appIcon, let nsImage = NSImage(data: iconData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(activity.appName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(activity.timeSinceActive)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if activity.isActive {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            onActivate()
        }
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

struct WebPageRow: View {
    let tab: BrowserActivityAdapter.BrowserTab
    let onActivate: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tab.browserName == "Safari" ? "safari" : "globe")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(tab.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(tab.url)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(tab.browserName)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.08))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            onActivate()
        }
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

struct SettingsTabView: View {
    @Binding var appLanguage: String
    @Binding var dockPreferenceRaw: String
    @Binding var launchDocked: Bool
    @Binding var autoExpandOnHover: Bool
    @Binding var autoReturnToDock: Bool
    @Binding var compactPreviewEnabled: Bool
    @Binding var collapseDelaySeconds: Double
    @Binding var returnToDockDelaySeconds: Double
    @Binding var dockAnimationDuration: Double
    @Binding var activityRefreshInterval: Double
    @Binding var recentAppsLimit: Int
    @Binding var recentWebPagesLimit: Int
    @Binding var capsuleOpacity: Double
    @Binding var glassTintHex: String
    @Binding var glassTintOpacity: Double
    @Binding var systemNotificationsEnabled: Bool
    @ObservedObject private var notificationPermission = NotificationPermissionManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsSection(L("窗口与吸附", "Window & Dock")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker(L("默认吸附方向", "Preferred dock side"), selection: $dockPreferenceRaw) {
                            Text(L("左侧", "Left")).tag(DockSide.left.rawValue)
                            Text(L("右侧", "Right")).tag(DockSide.right.rawValue)
                            Text(L("顶部", "Top")).tag(DockSide.top.rawValue)
                        }
                        .pickerStyle(.segmented)

                        Toggle(L("启动时贴边收纳", "Launch docked to edge"), isOn: $launchDocked)
                        Toggle(L("悬停自动展开", "Expand on hover"), isOn: $autoExpandOnHover)
                        Toggle(L("鼠标移开后自动回边栏", "Auto return to edge after mouse leaves"), isOn: $autoReturnToDock)
                        Toggle(L("收纳态显示预览信息", "Show compact preview when collapsed"), isOn: $compactPreviewEnabled)

                        HStack {
                            Text(L("收纳延时", "Collapse delay"))
                            Spacer()
                            Text(String(format: "%.1fs", collapseDelaySeconds))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $collapseDelaySeconds, in: 0.3...2.5, step: 0.1)

                        HStack {
                            Text(L("回边栏延时", "Return-to-edge delay"))
                            Spacer()
                            Text(String(format: "%.1fs", returnToDockDelaySeconds))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $returnToDockDelaySeconds, in: 0.3...3.0, step: 0.1)

                        HStack {
                            Text(L("动画时长", "Animation duration"))
                            Spacer()
                            Text(String(format: "%.2fs", dockAnimationDuration))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $dockAnimationDuration, in: 0.12...0.45, step: 0.01)
                    }
                }

                settingsSection(L("语言", "Language")) {
                    Picker(L("界面语言", "UI language"), selection: $appLanguage) {
                        Text("中文").tag("zh-Hans")
                        Text("English").tag("en")
                    }
                    .pickerStyle(.segmented)
                }

                settingsSection(L("提醒", "Reminders")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(L("允许任务使用系统级通知", "Allow task system notifications"), isOn: $systemNotificationsEnabled)

                        HStack {
                            Text(L("当前状态", "Current status"))
                            Spacer()
                            Text(notificationStatusText)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(notificationPermission.authorizationStatus == .denied ? .red : .secondary)
                        }

                        if notificationPermission.authorizationStatus == .denied {
                            Text(L("已被系统拒绝，请手动到系统设置中打开。", "Denied by macOS. Open System Settings to enable it."))
                                .font(.system(size: 11))
                                .foregroundColor(.red.opacity(0.82))
                        }

                        HStack(spacing: 8) {
                            Button(L("刷新状态", "Refresh status")) {
                                Task {
                                    _ = await notificationPermission.currentStatus()
                                }
                            }
                            .buttonStyle(.bordered)

                            Button(L("请求权限", "Request access")) {
                                Task {
                                    _ = await notificationPermission.requestPermission()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(notificationPermission.authorizationStatus == .authorized || notificationPermission.authorizationStatus == .provisional)

                            Button(L("测试通知", "Send test notification")) {
                                notificationPermission.sendTestNotification()
                            }
                            .buttonStyle(.bordered)
                        }

                        if notificationPermission.authorizationStatus == .denied {
                            Button(L("打开系统设置", "Open System Settings")) {
                                notificationPermission.openNotificationSettings()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                settingsSection(L("毛玻璃外观", "Glass Appearance")) {
                    VStack(alignment: .leading, spacing: 10) {
                        ColorPicker(L("玻璃颜色", "Glass tint"), selection: glassTintColor)

                        HStack {
                            Text(L("颜色透明度", "Tint opacity"))
                            Spacer()
                            Text(String(format: "%.0f%%", glassTintOpacity * 100))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $glassTintOpacity, in: 0.08...0.65, step: 0.01)

                        HStack {
                            Text(L("收纳态透明度", "Collapsed opacity"))
                            Spacer()
                            Text(String(format: "%.0f%%", capsuleOpacity * 100))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $capsuleOpacity, in: 0.35...1.0, step: 0.01)
                    }
                }

                settingsSection(L("性能与列表", "Performance & Lists")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(L("活动刷新间隔", "Activity refresh interval"))
                            Spacer()
                            Text(String(format: "%.0fs", activityRefreshInterval))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $activityRefreshInterval, in: 6...30, step: 1)

                        Stepper(L("最近应用数量: \(recentAppsLimit)", "Recent apps count: \(recentAppsLimit)"), value: $recentAppsLimit, in: 5...30)
                        Stepper(L("最近网页数量: \(recentWebPagesLimit)", "Recent web pages count: \(recentWebPagesLimit)"), value: $recentWebPagesLimit, in: 5...40)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .onAppear {
            Task {
                _ = await notificationPermission.currentStatus()
            }
        }
    }

    private var glassTintColor: Binding<Color> {
        Binding(
            get: { Color(hex: glassTintHex) },
            set: { newValue in
                if let hexString = newValue.hexString {
                    glassTintHex = hexString
                }
            }
        )
    }

    private var notificationStatusText: String {
        switch notificationPermission.authorizationStatus {
        case .authorized:
            return L("已授权", "Authorized")
        case .provisional:
            return L("临时授权", "Provisional")
        case .denied:
            return L("已拒绝", "Denied")
        case .notDetermined:
            return L("未决定", "Not determined")
        @unknown default:
            return L("未知", "Unknown")
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            content()
        }
        .padding(12)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func L(_ zh: String, _ en: String) -> String {
        appLanguage == "en" ? en : zh
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

private extension Color {
    init(hex: String) {
        let cleanedHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleanedHex).scanHexInt64(&value)

        let red: Double
        let green: Double
        let blue: Double

        if cleanedHex.count == 6 {
            red = Double((value & 0xFF0000) >> 16) / 255
            green = Double((value & 0x00FF00) >> 8) / 255
            blue = Double(value & 0x0000FF) / 255
        } else {
            red = 244 / 255
            green = 247 / 255
            blue = 255 / 255
        }

        self.init(red: red, green: green, blue: blue)
    }

    var hexString: String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else {
            return nil
        }

        return String(
            format: "#%02X%02X%02X",
            Int(round(color.redComponent * 255)),
            Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255))
        )
    }
}
