import SwiftUI
import SwiftData
import AppKit

struct MainTabView: View {
    private enum MainTab: Int {
        case tasks = 0
        case activity = 1
        case settings = 2
    }

    @State private var selectedTab: MainTab = .tasks
    @ObservedObject var edgeDocking: EdgeDockingController
    @StateObject private var taskViewModel = TaskSupervisorViewModel()
    @StateObject private var activityViewModel = ActivityMonitorViewModel()

    @AppStorage("dockPreference") private var dockPreferenceRaw = DockSide.right.rawValue
    @AppStorage("launchDocked") private var launchDocked = true
    @AppStorage("autoExpandOnHover") private var autoExpandOnHover = true
    @AppStorage("autoReturnToDock") private var autoReturnToDock = true
    @AppStorage("compactPreviewEnabled") private var compactPreviewEnabled = true
    @AppStorage("collapseDelaySeconds") private var collapseDelaySeconds = 0.9
    @AppStorage("returnToDockDelaySeconds") private var returnToDockDelaySeconds = 1.2
    @AppStorage("dockAnimationDuration") private var dockAnimationDuration = 0.24
    @AppStorage("activityRefreshInterval") private var activityRefreshInterval = 8.0
    @AppStorage("recentAppsLimit") private var recentAppsLimit = 12
    @AppStorage("recentWebPagesLimit") private var recentWebPagesLimit = 12
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
        .background {
            if edgeDocking.expansionState == .expanded {
                visualEffect
            } else {
                ZStack {
                    VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    Color.black.opacity(0.22)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if edgeDocking.expansionState == .expanded {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
            }
        }
        .shadow(
            color: edgeDocking.expansionState == .expanded ? .black.opacity(0.18) : .clear,
            radius: 12,
            x: 0,
            y: 5
        )
        .opacity(edgeDocking.expansionState == .collapsed ? 0.94 : 1.0)
        .animation(.easeInOut(duration: dockAnimationDuration), value: edgeDocking.expansionState)
        .animation(.easeInOut(duration: dockAnimationDuration), value: edgeDocking.dockedSide)
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
            selectedTab = .settings
            edgeDocking.expandWindow()
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
    }

    private var visualEffect: some View {
        VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
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
        return Button(action: { selectedTab = tab }) {
            HStack(spacing: 6) {
                if !isCompactChinese {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                }
                Text(title)
                    .font(.system(size: isCompactChinese ? 11 : 12, weight: .medium))
            }
            .foregroundColor(selectedTab == tab ? .primary : .secondary)
            .padding(.horizontal, isCompactChinese ? 8 : 10)
            .padding(.vertical, 6)
            .background(selectedTab == tab ? Color.primary.opacity(0.15) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var tabContent: some View {
        VStack(spacing: 0) {
            switch selectedTab {
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
                    onDockNow: { side in edgeDocking.dock(to: side) },
                    onExpandWindow: { edgeDocking.expandWindow() }
                )
            }
        }
    }

    @ViewBuilder
    private var collapsedPreview: some View {
        if edgeDocking.dockedSide == .top {
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
                selectedTab = .settings
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
                selectedTab = .settings
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
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isPresentingComposer = true } }) {
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
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isPresentingComposer = false
                        }
                    }

                TaskComposerView(
                    appLanguage: appLanguage,
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isPresentingComposer = false
                        }
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
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isPresentingComposer = false
                        }
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
        .animation(.easeInOut(duration: 0.2), value: isPresentingComposer)
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
                    Image(systemName: priorityIcon(task.priority))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(priorityColor(task.priority))
                    Text(task.title)
                        .font(.system(size: 13))
                        .foregroundColor(task.isCompleted ? .secondary : .primary)
                        .strikethrough(task.isCompleted)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(task.formattedDueDate)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
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
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
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
    @State private var dateInput = TaskComposerView.defaultDateText()
    @State private var timeInput = TaskComposerView.defaultTimeText()
    @State private var scheduleType: TaskScheduleType = .oneTime
    @State private var priority: TaskPriority = .medium
    @State private var reminderFrequency: TaskReminderFrequency = .daily
    @State private var notes = ""
    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("新增任务", "New Task"))
                .font(.system(size: 18, weight: .semibold))

            TextField(L("任务标题", "Task title"), text: $title)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 10) {
                TextField(L("日期 YYYY-MM-DD", "Date YYYY-MM-DD"), text: $dateInput)
                    .textFieldStyle(.roundedBorder)
                TextField(L("时间 HH:mm", "Time HH:mm"), text: $timeInput)
                    .textFieldStyle(.roundedBorder)
            }

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
                Text(L("每小时", "Hourly")).tag(TaskReminderFrequency.hourly)
                Text(L("每天", "Daily")).tag(TaskReminderFrequency.daily)
                Text(L("每周", "Weekly")).tag(TaskReminderFrequency.weekly)
            }
            .pickerStyle(.menu)

            TextField(L("备注（可选）", "Notes (optional)"), text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            if let validationError {
                Text(validationError)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button(L("取消", "Cancel")) {
                    onCancel()
                }
                Button(L("添加", "Add")) {
                    guard let dueDate = parsedDueDate else {
                        validationError = L("时间格式不正确，请使用 YYYY-MM-DD 和 HH:mm", "Invalid date format, use YYYY-MM-DD and HH:mm")
                        return
                    }

                    validationError = nil
                    onCreate(title, dueDate, scheduleType, priority, reminderFrequency, notes)
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 420)
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

    private var parsedDueDate: Date? {
        Self.dueDateFormatter.date(from: "\(dateInput) \(timeInput)")
    }

    private static let dueDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static let defaultDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let defaultTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static func defaultDateText() -> String {
        defaultDateFormatter.string(from: Date())
    }

    private static func defaultTimeText() -> String {
        defaultTimeFormatter.string(from: Date().addingTimeInterval(3600))
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
                    if selectedSection == 0 {
                        ForEach(viewModel.activities, id: \.id) { activity in
                            ActivityRowCompact(activity: activity) {
                                viewModel.activateActivity(activity)
                            }
                        }
                    } else if viewModel.isLoadingBrowser {
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
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .onAppear {
            refreshCurrentSection()
        }
        .onChange(of: selectedSection) { _, _ in
            refreshCurrentSection()
        }
    }

    private func refreshCurrentSection() {
        if selectedSection == 0 {
            viewModel.refreshActivities()
        } else {
            viewModel.refreshRecentWebPages()
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
        .onTapGesture {
            onActivate()
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
        .onTapGesture {
            onActivate()
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

    let onDockNow: (DockSide) -> Void
    let onExpandWindow: () -> Void

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

                HStack(spacing: 10) {
                    Button(L("立即收纳", "Dock now")) {
                        onDockNow(DockSide(rawValue: dockPreferenceRaw) ?? .right)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(L("立即展开", "Expand now")) {
                        onExpandWindow()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
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