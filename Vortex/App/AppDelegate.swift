import Cocoa
import SwiftUI
import SwiftData

extension Notification.Name {
    static let vortexShowSettings = Notification.Name("vortex.showSettings")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindow: NSWindow?
    var modelContainer: ModelContainer?
    private var edgeDockingController: EdgeDockingController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ReminderScheduler.shared.requestAuthorization()
        setupMenu()
        setupModelContainer()
        createMainWindow()
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
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.makeKeyAndOrderFront(nil)

        mainWindow = window
        controller.configure(
            preferredSide: preferredDockSideFromDefaults(),
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
            mainWindow?.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func openSettings() {
        mainWindow?.makeKeyAndOrderFront(nil)
        edgeDockingController?.expandWindow()
        NotificationCenter.default.post(name: .vortexShowSettings, object: nil)
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
