import Foundation
import SwiftUI

@MainActor
final class ActivityMonitorViewModel: ObservableObject {
    @Published var activities: [ActivityItem] = []
    @Published var browserTabs: [BrowserActivityAdapter.BrowserTab] = []
    @Published var selectedBrowser: String = "Safari"
    @Published var recentWebPages: [BrowserActivityAdapter.BrowserTab] = []
    @Published var isLoadingBrowser: Bool = false

    private let activityTracker = ActivityTracker.shared
    private let browserAdapter = BrowserActivityAdapter.shared
    private var isTracking = false
    private var recentAppsLimit = 20
    private var recentWebPagesLimit = 20

    init() {}

    func startTracking() {
        guard !isTracking else { return }
        isTracking = true

        activityTracker.onActivitiesUpdated = { [weak self] updated in
            Task { @MainActor in
                guard let self else { return }
                self.activities = Array(updated.prefix(self.recentAppsLimit))
            }
        }
        activityTracker.startTracking()
        refreshActivities()
    }

    func stopTracking() {
        isTracking = false
        activityTracker.stopTracking()
    }

    func refreshActivities() {
        activities = activityTracker.getRecentActivities(limit: recentAppsLimit)
    }

    func activateActivity(_ activity: ActivityItem) {
        activityTracker.activateApplication(activity)
    }

    func refreshRecentWebPages() {
        isLoadingBrowser = true
        let limit = recentWebPagesLimit

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let tabs = self.browserAdapter.fetchRecentWebPages(limit: limit)

            DispatchQueue.main.async {
                self.recentWebPages = tabs
                self.browserTabs = tabs
                self.isLoadingBrowser = false
            }
        }
    }

    func refreshBrowserTabs() {
        isLoadingBrowser = true
        let browser = selectedBrowser

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let tabs = self.browserAdapter.fetchTabs(for: browser)

            DispatchQueue.main.async {
                self.browserTabs = tabs
                self.isLoadingBrowser = false
            }
        }
    }

    func updateActivityRefreshInterval(_ interval: TimeInterval) {
        activityTracker.updateRefreshInterval(interval)
    }

    func isBrowserRunning(_ browser: String) -> Bool {
        browserAdapter.isBrowserRunning(browser)
    }

    func updateRecentLimits(appLimit: Int, webLimit: Int) {
        recentAppsLimit = max(5, appLimit)
        recentWebPagesLimit = max(5, webLimit)
        refreshActivities()
        refreshRecentWebPages()
    }

    func activateWebPage(_ tab: BrowserActivityAdapter.BrowserTab) {
        _ = browserAdapter.activateTab(tab)
    }
}