import Foundation
import AppKit

final class ActivityTracker: @unchecked Sendable {
    static let shared = ActivityTracker()

    var onActivitiesUpdated: (([ActivityItem]) -> Void)?

    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?
    private let maxActivityItems = 50
    private var iconCache: [String: Data] = [:]
    private var activitiesByBundle: [String: ActivityItem] = [:]
    private var runningAppsByBundle: [String: NSRunningApplication] = [:]

    private(set) var activities: [ActivityItem] = []

    private init() {}

    func startTracking() {
        guard timer == nil, activationObserver == nil else { return }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        activationObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleActivation(notification)
        }

        let interval = max(6.0, UserDefaults.standard.double(forKey: "activityRefreshInterval"))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.captureRunningApplications(markFrontmostAsActive: true)
        }
        timer?.tolerance = min(2.0, interval * 0.25)

        captureRunningApplications(markFrontmostAsActive: true)
    }

    func stopTracking() {
        timer?.invalidate()
        timer = nil

        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    func updateRefreshInterval(_ interval: TimeInterval) {
        UserDefaults.standard.set(interval, forKey: "activityRefreshInterval")
        if timer != nil {
            stopTracking()
            startTracking()
        }
    }

    private func handleActivation(_ notification: Notification) {
        let activePID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
        captureRunningApplications(markFrontmostAsActive: true, activePID: activePID)
    }

    private func captureRunningApplications(markFrontmostAsActive: Bool, activePID: pid_t? = nil) {
        let runningApps = NSWorkspace.shared.runningApplications
        let frontmostPID = activePID ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        var activeBundles: Set<String> = []
        var updatedRunningApps: [String: NSRunningApplication] = [:]

        for app in runningApps {
            guard app.activationPolicy == .regular,
                  let bundleId = app.bundleIdentifier,
                  let appName = app.localizedName,
                  shouldTrack(bundleIdentifier: bundleId)
            else { continue }

            activeBundles.insert(bundleId)
            updatedRunningApps[bundleId] = app
            let isActive = markFrontmostAsActive && app.processIdentifier == frontmostPID
            let iconData = cachedIconData(for: app)

            if let activity = activitiesByBundle[bundleId] {
                activity.appName = appName
                activity.appIcon = iconData
                if isActive {
                    activity.lastActiveTime = Date()
                }
            } else {
                let activity = ActivityItem(
                    appName: appName,
                    bundleIdentifier: bundleId,
                    appIcon: iconData,
                    lastActiveTime: isActive ? Date() : Date().addingTimeInterval(-3600),
                    isBrowser: isBrowserApp(bundleId)
                )
                activitiesByBundle[bundleId] = activity
            }
        }

        activitiesByBundle.keys
            .filter { !activeBundles.contains($0) }
            .forEach { activitiesByBundle.removeValue(forKey: $0) }
        runningAppsByBundle = updatedRunningApps

        var updatedActivities = activitiesByBundle.values.sorted { $0.lastActiveTime > $1.lastActiveTime }

        if updatedActivities.count > maxActivityItems {
            updatedActivities = Array(updatedActivities.prefix(maxActivityItems))
        }

        activities = updatedActivities
        onActivitiesUpdated?(getRecentActivities(limit: 20))
    }

    private func shouldTrack(bundleIdentifier: String) -> Bool {
        if !bundleIdentifier.hasPrefix("com.apple.") {
            return true
        }

        let allowedAppleApps = Set([
            "com.apple.Safari",
            "com.apple.Terminal",
            "com.apple.finder",
            "com.apple.mail",
            "com.apple.dt.Xcode"
        ])

        return allowedAppleApps.contains(bundleIdentifier)
    }

    private func cachedIconData(for app: NSRunningApplication) -> Data? {
        guard let bundleId = app.bundleIdentifier else { return nil }
        if let cached = iconCache[bundleId] {
            return cached
        }

        let iconData = app.icon?.tiffRepresentation
        iconCache[bundleId] = iconData
        return iconData
    }

    private func isBrowserApp(_ bundleId: String) -> Bool {
        let browsers = [
            "com.apple.Safari",
            "com.google.Chrome",
            "org.mozilla.firefox",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "com.vivaldi.Vivaldi",
            "com.microsoft.Word",
            "com.apple.mail"
        ]
        return browsers.contains(bundleId)
    }

    func activateApplication(_ activity: ActivityItem) {
        let app = runningAppsByBundle[activity.bundleIdentifier] ??
            NSRunningApplication.runningApplications(withBundleIdentifier: activity.bundleIdentifier).first

        if let app {
            app.unhide()
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }

        activateUsingWorkspace(bundleIdentifier: activity.bundleIdentifier)
        activateUsingAppleScript(bundleIdentifier: activity.bundleIdentifier)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            let retryApp = self?.runningAppsByBundle[activity.bundleIdentifier] ??
                NSRunningApplication.runningApplications(withBundleIdentifier: activity.bundleIdentifier).first
            retryApp?.unhide()
            retryApp?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            self?.activateUsingAppleScript(bundleIdentifier: activity.bundleIdentifier)
        }
    }

    private func activateUsingWorkspace(bundleIdentifier: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    private func activateUsingAppleScript(bundleIdentifier: String) {
        let escapedBundleIdentifier = bundleIdentifier
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application id \"\(escapedBundleIdentifier)\" to activate"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)

        if let error {
            print("Failed to activate \(bundleIdentifier) via AppleScript: \(error)")
        }
    }

    func getRecentActivities(limit: Int = 20) -> [ActivityItem] {
        return Array(activities.prefix(limit))
    }
}
