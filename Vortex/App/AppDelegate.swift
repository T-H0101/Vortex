import Cocoa
import SwiftUI
import SwiftData

extension Notification.Name {
    static let vortexShowTasks = Notification.Name("vortex.showTasks")
    static let vortexShowActivity = Notification.Name("vortex.showActivity")
    static let vortexShowSettings = Notification.Name("vortex.showSettings")
    static let vortexAddTask = Notification.Name("vortex.addTask")
    static let vortexTasksChanged = Notification.Name("vortex.tasksChanged")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindow: NSWindow?
    var modelContainer: ModelContainer?
    private var edgeDockingController: EdgeDockingController?
    private var statusBarPanelController: StatusBarPanelController?
    private var statusItem: NSStatusItem?
    private weak var statusShowItem: NSMenuItem?
    private weak var statusPinRightItem: NSMenuItem?
    private var activeSpaceObserver: NSObjectProtocol?
    private var appActiveObserver: NSObjectProtocol?
    private var persistentWindowTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure notification permission is checked early for developer testing when launched from Xcode
        Task {
            let status = await NotificationPermissionManager.shared.currentStatus()
            if status == .notDetermined {
                _ = await NotificationPermissionManager.shared.requestPermission()
            }
        }

        // Existing reminder scheduler request kept for backward compatibility
        ReminderScheduler.shared.requestAuthorization()
        setupMenu()
        setupStatusItem()
        setupModelContainer()
        createMainWindow()
        setupStatusBarPanelController()
        observeSpaceChanges()
        observeAppActivation()
        startPersistentWindowCorrection()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    private func setupModelContainer() {
        do {
            let schema = Schema([TaskItem.self, ActivityItem.self, ReminderSchedule.self])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            print("Failed to create ModelContainer: \(error)")
        }
    }

    @MainActor
    private func setupStatusBarPanelController() {
        guard let container = modelContainer else { return }
        statusBarPanelController = StatusBarPanelController(modelContainer: container)
    }

    private func setupMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(withTitle: "About Vortex", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Vortex", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu

        let toggleItem = NSMenuItem(title: "Show/Hide Vortex", action: #selector(toggleWindow), keyEquivalent: "1")
        toggleItem.target = self
        windowMenu.addItem(toggleItem)
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")

        NSApplication.shared.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "circle.hexagongrid.fill", accessibilityDescription: "Vortex")
        item.button?.imagePosition = .imageOnly

        let menu = NSMenu()

        // Quick Add Task
        let addTaskItem = NSMenuItem(title: "Quick Add Task", action: #selector(quickAddTask), keyEquivalent: "")
        addTaskItem.target = self
        menu.addItem(addTaskItem)

        // Show Tasks
        let showTasksItem = NSMenuItem(title: "Show Tasks", action: #selector(showTasks), keyEquivalent: "")
        showTasksItem.target = self
        menu.addItem(showTasksItem)

        // Show Activity
        let showActivityItem = NSMenuItem(title: "Show Activity", action: #selector(showActivity), keyEquivalent: "")
        showActivityItem.target = self
        menu.addItem(showActivityItem)

        menu.addItem(.separator())

        // Show/Hide Vortex
        let showItem = NSMenuItem(title: "Show/Hide Vortex", action: #selector(toggleWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        statusShowItem = showItem

        let dockRightItem = NSMenuItem(title: "Pin to Right Edge", action: #selector(pinToRightEdge), keyEquivalent: "")
        dockRightItem.target = self
        menu.addItem(dockRightItem)
        statusPinRightItem = dockRightItem

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Vortex", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        item.menu = menu
        menu.delegate = self
        statusItem = item
    }

    private func createMainWindow() {
        let window = VortexWindow(
            contentRect: NSRect(x: 140, y: 120, width: 430, height: 460),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        let controller = EdgeDockingController(window: window)
        edgeDockingController = controller

        guard let modelContainer else {
            return
        }

        let contentView = MainTabView(edgeDocking: controller)
            .modelContainer(modelContainer)

        window.contentView = NSHostingView(rootView: contentView)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        applyPersistentWindowBehavior(to: window)
        window.isMovableByWindowBackground = true
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        mainWindow = window
        controller.configure(
            preferredSide: .top,
            autoExpandOnHover: boolSetting(forKey: "autoExpandOnHover", defaultValue: true),
            autoReturnToDock: boolSetting(forKey: "autoReturnToDock", defaultValue: true),
            collapseDelay: doubleSetting(forKey: "collapseDelaySeconds", defaultValue: 0.9),
            returnToDockDelay: doubleSetting(forKey: "returnToDockDelaySeconds", defaultValue: 1.2),
            animationDuration: doubleSetting(forKey: "dockAnimationDuration", defaultValue: 0.24)
        )
        controller.startMonitoring()

        if boolSetting(forKey: "launchDocked", defaultValue: true) {
            controller.dock(to: preferredDockSideFromDefaults())
        } else {
            controller.expandWindow()
        }
    }

    @objc private func toggleWindow() {
        if mainWindow?.isVisible == true {
            mainWindow?.orderOut(nil)
        } else {
            showPersistentWindow()
        }
        updateStatusMenuChecks()
    }

    @objc private func openSettings() {
        showPersistentWindow()
        edgeDockingController?.expandWindow()
        NotificationCenter.default.post(name: .vortexShowSettings, object: nil)
    }

    @objc @MainActor
    private func quickAddTask() {
        statusBarPanelController?.showTaskComposer()
    }

    @objc @MainActor
    private func showTasks() {
        statusBarPanelController?.showTaskList()
    }

    @objc @MainActor
    private func showActivity() {
        statusBarPanelController?.showActivity()
    }

    @objc private func pinToRightEdge() {
        showPersistentWindow()
        UserDefaults.standard.set(DockSide.right.rawValue, forKey: "dockPreference")
        edgeDockingController?.dock(to: .right)
        updateStatusMenuChecks()
    }

    private func observeSpaceChanges() {
        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restoreWindowAfterSpaceChange()
        }
    }

    private func observeAppActivation() {
        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task {
                _ = await NotificationPermissionManager.shared.currentStatus()
            }
        }
    }

    private func restoreWindowAfterSpaceChange() {
        guard let window = mainWindow, window.isVisible else { return }
        applyPersistentWindowBehavior(to: window)

        DispatchQueue.main.async {
            self.showPersistentWindow()
            self.edgeDockingController?.reapplyCurrentPlacement()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.showPersistentWindow()
            self.edgeDockingController?.reapplyCurrentPlacement()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            self.showPersistentWindow()
            self.edgeDockingController?.reapplyCurrentPlacement()
        }
    }

    private func startPersistentWindowCorrection() {
        persistentWindowTimer?.invalidate()
        persistentWindowTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self, let window = self.mainWindow, window.isVisible else { return }
            self.applyPersistentWindowBehavior(to: window)
            self.edgeDockingController?.enforceCurrentPlacement()
            window.orderFrontRegardless()
        }
        persistentWindowTimer?.tolerance = 0.3
    }

    private func showPersistentWindow() {
        guard let window = mainWindow else { return }
        applyPersistentWindowBehavior(to: window)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func applyPersistentWindowBehavior(to window: NSWindow) {
        // Menu bar style window - use normal level for status bar style
        window.level = .floating
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = false
    }

    private func updateStatusMenuChecks() {
        statusShowItem?.state = mainWindow?.isVisible == true ? .on : .off
        statusPinRightItem?.state = edgeDockingController?.dockedSide == .right ? .on : .off
    }

    private func preferredDockSideFromDefaults() -> DockSide {
        let raw = UserDefaults.standard.string(forKey: "dockPreference") ?? DockSide.right.rawValue
        return DockSide(rawValue: raw) ?? .right
    }

    private func boolSetting(forKey key: String, defaultValue: Bool) -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) == nil {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }

    private func doubleSetting(forKey key: String, defaultValue: Double) -> Double {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) == nil {
            return defaultValue
        }
        return defaults.double(forKey: key)
    }
}

final class VortexWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        updateStatusMenuChecks()
    }
}
