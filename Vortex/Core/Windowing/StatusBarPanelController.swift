import AppKit
import SwiftUI
import SwiftData

private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private class PanelHostingView<Content: View>: NSHostingView<Content> {
    private var applyingDeferred = false

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var needsUpdateConstraints: Bool {
        get { super.needsUpdateConstraints }
        set {
            if applyingDeferred {
                super.needsUpdateConstraints = newValue
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.applySuperNeedsUpdateConstraints(newValue)
            }
        }
    }

    private func applySuperNeedsUpdateConstraints(_ value: Bool) {
        applyingDeferred = true
        super.needsUpdateConstraints = value
        applyingDeferred = false
    }

    override var needsLayout: Bool {
        get { super.needsLayout }
        set {
            if applyingDeferred {
                super.needsLayout = newValue
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.applySuperNeedsLayout(newValue)
            }
        }
    }

    private func applySuperNeedsLayout(_ value: Bool) {
        applyingDeferred = true
        super.needsLayout = value
        applyingDeferred = false
    }
}

@MainActor
class StatusBarPanelController: NSObject, NSWindowDelegate {
    private var taskComposerPanel: NSPanel?
    private var taskListPanel: NSPanel?
    private var activityPanel: NSPanel?

    private var modelContainer: ModelContainer?
    private var globalClickMonitor: Any?

    private let panelWidth: CGFloat = 340
    private let taskComposerHeight: CGFloat = 440
    private let taskListHeight: CGFloat = 400
    private let activityHeight: CGFloat = 380

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        super.init()
    }

    func showTaskComposer() {
        if let panel = taskComposerPanel {
            panel.orderFrontRegardless()
            return
        }

        let panel = createPanel(width: panelWidth, height: taskComposerHeight)
        self.taskComposerPanel = panel

        guard let container = modelContainer else { return }

        let rootView = TaskComposerStandaloneView(modelContainer: container) { [weak self] in
            self?.closeTaskComposer()
        }
        let contentView = PanelHostingView(rootView: rootView)

        panel.contentView = contentView
        positionPanel(panel, at: .center)
        panel.delegate = self
        panel.orderFrontRegardless()

        setupGlobalClickMonitor()
    }

    func showTaskList() {
        if let panel = taskListPanel {
            panel.orderFrontRegardless()
            return
        }

        let panel = createPanel(width: panelWidth, height: taskListHeight)
        self.taskListPanel = panel

        guard let container = modelContainer else { return }

        let rootView = TaskListStandaloneView { [weak self] in
            self?.closeTaskList()
        }
            .modelContainer(container)
        let contentView = PanelHostingView(rootView: rootView)

        panel.contentView = contentView
        positionPanel(panel, at: .center)
        panel.delegate = self
        panel.orderFrontRegardless()

        setupGlobalClickMonitor()
    }

    func showActivity() {
        if let panel = activityPanel {
            panel.orderFrontRegardless()
            return
        }

        let panel = createPanel(width: panelWidth, height: activityHeight)
        self.activityPanel = panel

        guard let container = modelContainer else { return }

        let rootView = ActivityStandaloneView { [weak self] in
            self?.closeActivity()
        }
            .modelContainer(container)
        let contentView = PanelHostingView(rootView: rootView)

        panel.contentView = contentView
        positionPanel(panel, at: .center)
        panel.delegate = self
        panel.orderFrontRegardless()

        setupGlobalClickMonitor()
    }

    private func closeTaskComposer() {
        taskComposerPanel?.orderOut(nil)
        taskComposerPanel = nil
    }

    private func closeTaskList() {
        taskListPanel?.orderOut(nil)
        taskListPanel = nil
    }

    private func closeActivity() {
        activityPanel?.orderOut(nil)
        activityPanel = nil
    }

    private func createPanel(width: CGFloat, height: CGFloat) -> NSPanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.acceptsMouseMovedEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.sharingType = .readOnly
        panel.isMovable = true
        return panel
    }

    private enum PanelPosition {
        case center
    }

    private func positionPanel(_ panel: NSPanel, at position: PanelPosition) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        let x = screenFrame.midX - panel.frame.width / 2
        let y = screenFrame.midY - panel.frame.height / 2

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func setupGlobalClickMonitor() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                self?.handleGlobalClick(event)
            }
        }
    }

    private func handleGlobalClick(_ event: NSEvent) {
        let clickLocation = NSEvent.mouseLocation

        if let panel = taskComposerPanel, panel.isVisible {
            if !panel.frame.contains(clickLocation) {
                closeTaskComposer()
            }
        }

        if let panel = taskListPanel, panel.isVisible {
            if !panel.frame.contains(clickLocation) {
                closeTaskList()
            }
        }

        if let panel = activityPanel, panel.isVisible {
            if !panel.frame.contains(clickLocation) {
                closeActivity()
            }
        }
    }

    func windowDidMove(_ notification: Notification) {}

    deinit {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// MARK: - Standalone Views

struct TaskComposerStandaloneView: View {
    let modelContainer: ModelContainer
    let onCancel: () -> Void

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
        VStack(spacing: 0) {
            headerView
            formContent
        }
        .frame(width: 340, height: 440)
        .panelSurface(cornerRadius: 18)
    }

    private var headerView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text(L("新增任务", "New Task"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(L("快速创建并设置提醒", "Quickly create and schedule"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()
                PanelCloseButton(action: onCancel)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(Color.white.opacity(0.06))
            Divider().opacity(0.35)
        }
    }

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TextField(L("任务标题", "Task title"), text: $title)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 8) {
                    Text(L("截止时间", "Due time"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        componentPicker(L("月", "Month"), selection: $selectedMonth, values: Array(1...12)) { String(format: "%02d", $0) }
                        componentPicker(L("日", "Day"), selection: $selectedDay, values: Array(1...daysInSelectedMonth)) { String(format: "%02d", $0) }
                    }
                    HStack(spacing: 8) {
                        componentPicker(L("时", "Hour"), selection: $selectedHour, values: Array(0...23)) { String(format: "%02d", $0) }
                        componentPicker(L("分", "Minute"), selection: $selectedMinute, values: Array(0...59)) { String(format: "%02d", $0) }
                    }
                }

                Picker(L("优先级", "Priority"), selection: $priority) {
                    Text("中").tag(TaskPriority.medium)
                    Text("高").tag(TaskPriority.high)
                    Text("紧急").tag(TaskPriority.urgent)
                    Text("低").tag(TaskPriority.low)
                }
                .pickerStyle(.segmented)

                Picker(L("提醒", "Reminder"), selection: $reminderFrequency) {
                    Text(L("无", "None")).tag(TaskReminderFrequency.none)
                    Text(L("到期时", "Due time")).tag(TaskReminderFrequency.atDueTime)
                    Text(L("每天", "Daily")).tag(TaskReminderFrequency.daily)
                }
                .pickerStyle(.menu)

                HStack {
                    Spacer()
                    Button(L("取消", "Cancel")) {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                    Button(L("添加", "Add")) {
                        createTask()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(16)
        }
    }

    private func L(_ zh: String, _ en: String) -> String {
        let language = UserDefaults.standard.string(forKey: "appLanguage") ?? "zh-Hans"
        return language == "en" ? en : zh
    }

    private var daysInSelectedMonth: Int {
        var components = DateComponents()
        components.year = selectedYear
        components.month = selectedMonth
        guard let date = Calendar.current.date(from: components),
              let range = Calendar.current.range(of: .day, in: .month, for: date) else {
            return 31
        }
        return range.count
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
        components.year = selectedYear
        components.month = selectedMonth
        components.day = min(selectedDay, daysInSelectedMonth)
        components.hour = selectedHour
        components.minute = selectedMinute
        return Calendar.current.date(from: components) ?? Date()
    }

    private func createTask() {
        let context = modelContainer.mainContext
        let reminderDate: Date?
        switch reminderFrequency {
        case .none:
            reminderDate = nil
        case .atDueTime, .daily, .weekly:
            reminderDate = selectedDueDate
        case .fiveSeconds:
            reminderDate = Date().addingTimeInterval(5)
        case .hourly:
            reminderDate = Date().addingTimeInterval(3600)
        }

        let task = TaskItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: selectedDueDate,
            reminderDate: reminderDate,
            notes: notes,
            priority: priority,
            scheduleType: scheduleType,
            reminderFrequency: reminderFrequency
        )
        context.insert(task)
        do {
            try context.save()
            ReminderScheduler.shared.scheduleReminder(for: task)
            NotificationCenter.default.post(name: .vortexTasksChanged, object: nil)
            title = ""
            notes = ""
            onCancel()
        } catch {
            print("Failed to save task: \(error)")
        }
    }
}

struct TaskListStandaloneView: View {
    @Query(sort: \TaskItem.dueDate) private var tasks: [TaskItem]
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerView
            taskList
        }
        .frame(width: 340, height: 400)
        .panelSurface(cornerRadius: 18)
    }

    private var headerView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "checklist")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text(L("任务", "Tasks"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(L("\(tasks.filter { !$0.isCompleted }.count) 个待办", "\(tasks.filter { !$0.isCompleted }.count) pending"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()
                PanelCloseButton(action: onClose)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(Color.white.opacity(0.06))
            Divider().opacity(0.35)
        }
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if tasks.isEmpty {
                    emptyState
                } else {
                    ForEach(tasks) { task in
                        TaskListRowView(task: task)
                    }
                }
            }
            .padding(12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.5))
            Text(L("暂无任务", "No tasks"))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func L(_ zh: String, _ en: String) -> String {
        let language = UserDefaults.standard.string(forKey: "appLanguage") ?? "zh-Hans"
        return language == "en" ? en : zh
    }
}

struct TaskListRowView: View {
    @Bindable var task: TaskItem

    var body: some View {
        HStack(spacing: 10) {
            Button(action: toggleCompletion) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(task.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 13))
                    .foregroundColor(task.isOverdue ? .red : (task.isCompleted ? .secondary : .primary))
                    .strikethrough(task.isCompleted)

                Text(task.formattedDueDate)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(task.isOverdue ? Color.red.opacity(0.12) : Color.primary.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(task.isOverdue ? Color.red.opacity(0.35) : Color.clear, lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            toggleCompletion()
        }
    }

    private func toggleCompletion() {
        task.isCompleted.toggle()
        task.completedAt = task.isCompleted ? Date() : nil
        if task.isCompleted {
            ReminderScheduler.shared.cancelReminder(for: task.id)
        } else {
            ReminderScheduler.shared.scheduleReminder(for: task)
        }
        try? task.modelContext?.save()
        NotificationCenter.default.post(name: .vortexTasksChanged, object: nil)
    }
}

private struct PanelCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(0.06))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Close")
    }
}

struct ActivityStandaloneView: View {
    @StateObject private var viewModel = ActivityMonitorViewModel()
    @State private var selectedTab = 0
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerView
            tabSelector
            contentView
        }
        .frame(width: 340, height: 380)
        .panelSurface(cornerRadius: 18)
        .onAppear {
            viewModel.startTracking()
        }
    }

    private var headerView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text(L("活动", "Activity"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(selectedTab == 0 ? L("最近应用", "Recent apps") : L("最近网页", "Recent web pages"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()
                PanelCloseButton(action: onClose)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(Color.white.opacity(0.06))
            Divider().opacity(0.35)
        }
    }

    private var tabSelector: some View {
        HStack(spacing: 0) {
            tabButton(L("应用", "Apps"), index: 0)
            tabButton(L("网页", "Web"), index: 1)
            tabButton(L("终端", "Terminals"), index: 2)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func tabButton(_ title: String, index: Int) -> some View {
        Button(action: {
            selectedTab = index
            if index == 1 {
                viewModel.selectedBrowser = "Safari"
                viewModel.refreshBrowserTabs()
            } else if index == 2 {
                viewModel.selectedBrowser = "Terminal"
                viewModel.refreshBrowserTabs()
            }
        }) {
            Text(title)
                .font(.system(size: 13, weight: selectedTab == index ? .medium : .regular))
                .foregroundColor(selectedTab == index ? .primary : .secondary)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(selectedTab == index ? Color.primary.opacity(0.10) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case 0:
            appsListView
        case 1:
            webListView
        case 2:
            terminalsListView
        default:
            appsListView
        }
    }

    private var appsListView: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(viewModel.activities, id: \.id) { activity in
                    ActivityRowCompact(activity: activity) {
                        onClose()
                        DispatchQueue.main.async {
                            viewModel.activateActivity(activity)
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    private var webListView: some View {
        VStack(spacing: 0) {
            webBrowserPicker
            ScrollView {
                if viewModel.browserTabs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "globe")
                            .font(.system(size: 30))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(L("无可用网页", "No web pages"))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Button(action: { viewModel.refreshBrowserTabs() }) {
                            Text(L("刷新", "Refresh"))
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.browserTabs) { tab in
                            BrowserTabRowStandalone(tab: tab) {
                                onClose()
                                DispatchQueue.main.async {
                                    viewModel.activateWebPage(tab)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .onAppear {
            viewModel.selectedBrowser = "Safari"
            viewModel.refreshBrowserTabs()
        }
    }

    private var webBrowserPicker: some View {
        Picker(L("浏览器", "Browser"), selection: $viewModel.selectedBrowser) {
            Text("Safari").tag("Safari")
            Text("Chrome").tag("Chrome")
        }
        .pickerStyle(.segmented)
        .padding(.bottom, 8)
        .onChange(of: viewModel.selectedBrowser) { _, _ in
            viewModel.refreshBrowserTabs()
        }
    }

    private var terminalsListView: some View {
        VStack(spacing: 0) {
            ScrollView {
                if viewModel.browserTabs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "terminal")
                            .font(.system(size: 30))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(L("无可用终端", "No terminals"))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Button(action: {
                            viewModel.selectedBrowser = "Terminal"
                            viewModel.refreshBrowserTabs()
                        }) {
                            Text(L("刷新", "Refresh"))
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.browserTabs) { tab in
                            BrowserTabRowStandalone(tab: tab) {
                                onClose()
                                DispatchQueue.main.async {
                                    viewModel.activateWebPage(tab)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .onAppear {
            viewModel.selectedBrowser = "Terminal"
            viewModel.refreshBrowserTabs()
        }
    }

    private func L(_ zh: String, _ en: String) -> String {
        let language = UserDefaults.standard.string(forKey: "appLanguage") ?? "zh-Hans"
        return language == "en" ? en : zh
    }
}

struct BrowserTabRowStandalone: View {
    let tab: BrowserActivityAdapter.BrowserTab
    let onActivate: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(tab.title)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(tab.url)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .overlay(MouseDownActionView(action: onActivate))
    }
}

private struct MouseDownActionView: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> MouseDownView {
        let view = MouseDownView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: MouseDownView, context: Context) {
        nsView.action = action
    }

    final class MouseDownView: NSView {
        var action: (() -> Void)?

        override func mouseDown(with event: NSEvent) {
            action?()
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

private struct PanelSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                PanelVisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.08),
                                Color.black.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
            )
    }
}

private extension View {
    func panelSurface(cornerRadius: CGFloat) -> some View {
        modifier(PanelSurfaceModifier(cornerRadius: cornerRadius))
    }
}

private struct PanelVisualEffectView: NSViewRepresentable {
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
