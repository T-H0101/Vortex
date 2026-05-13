import Foundation
import AppKit

final class BrowserActivityAdapter: @unchecked Sendable {
    static let shared = BrowserActivityAdapter()

    private let cacheTTL: TimeInterval = 2.0
    private var tabCache: [String: (timestamp: Date, tabs: [BrowserTab])] = [:]
    private let cacheLock = NSLock()

    private init() {}

    struct BrowserTab: Identifiable {
        let id = UUID()
        let title: String
        let url: String
        let browserName: String
    }

    func fetchTabs(for browser: String) -> [BrowserTab] {
        switch browser {
        case "Safari":
            return fetchSafariTabs()
        case "Chrome":
            return fetchChromeTabs()
        default:
            return []
        }
    }

    func fetchRecentWebPages(limit: Int) -> [BrowserTab] {
        let combined = fetchSafariTabs() + fetchChromeTabs()
        var seenURLs = Set<String>()
        var uniqueTabs: [BrowserTab] = []

        for tab in combined where !tab.url.isEmpty {
            let normalized = tab.url.lowercased()
            guard seenURLs.insert(normalized).inserted else { continue }
            uniqueTabs.append(tab)
            if uniqueTabs.count >= limit {
                break
            }
        }

        return uniqueTabs
    }

    func fetchSafariTabs() -> [BrowserTab] {
        guard isBrowserRunning("Safari") else { return [] }
        if let cached = cachedTabs(for: "Safari") { return cached }

        let script = """
        tell application "Safari"
            set tabList to {}
            if (count of windows) > 0 then
                repeat with w in windows
                    repeat with t in tabs of w
                        set end of tabList to {title of t, URL of t}
                    end repeat
                end repeat
            end if
            return tabList
        end tell
        """

        let tabs = executeScript(script, browserName: "Safari")
        storeTabs(tabs, for: "Safari")
        return tabs
    }

    func fetchChromeTabs() -> [BrowserTab] {
        guard isBrowserRunning("Chrome") else { return [] }
        if let cached = cachedTabs(for: "Chrome") { return cached }

        let script = """
        tell application "Google Chrome"
            set tabList to {}
            if (count of windows) > 0 then
                repeat with w in windows
                    repeat with t in tabs of w
                        set end of tabList to {title of t, URL of t}
                    end repeat
                end repeat
            end if
            return tabList
        end tell
        """

        let tabs = executeScript(script, browserName: "Chrome")
        storeTabs(tabs, for: "Chrome")
        return tabs
    }

    private func executeScript(_ script: String, browserName: String) -> [BrowserTab] {
        var tabs: [BrowserTab] = []
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return [] }

        let result = appleScript.executeAndReturnError(&error)
        if error != nil { return [] }

        let count = result.numberOfItems
        for i in 1...count {
            guard let itemDescriptor = result.atIndex(i) as NSAppleEventDescriptor? else { continue }
            let itemsCount = itemDescriptor.numberOfItems
            if itemsCount >= 2 {
                let title = itemDescriptor.atIndex(1)?.stringValue ?? "Untitled"
                let url = itemDescriptor.atIndex(2)?.stringValue ?? ""
                tabs.append(BrowserTab(title: title, url: url, browserName: browserName))
            }
        }

        return tabs
    }

    private func cachedTabs(for browser: String) -> [BrowserTab]? {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        guard let cache = tabCache[browser] else { return nil }
        guard Date().timeIntervalSince(cache.timestamp) <= cacheTTL else { return nil }
        return cache.tabs
    }

    private func storeTabs(_ tabs: [BrowserTab], for browser: String) {
        cacheLock.lock()
        tabCache[browser] = (Date(), tabs)
        cacheLock.unlock()
    }

    func activateTab(_ tab: BrowserTab) -> Bool {
        guard !tab.url.isEmpty else { return false }

        switch tab.browserName {
        case "Safari":
            return activateSafariTab(url: tab.url)
        case "Chrome":
            return activateChromeTab(url: tab.url)
        default:
            return false
        }
    }

    private func activateSafariTab(url: String) -> Bool {
        guard isBrowserRunning("Safari") else { return false }
        let escapedURL = escapeAppleScriptString(url)
        let script = """
        tell application "Safari"
            set targetURL to "\(escapedURL)"
            set foundTab to false
            if (count of windows) > 0 then
                repeat with w in windows
                    repeat with t in tabs of w
                        if (URL of t as text) is targetURL then
                            set current tab of w to t
                            set index of w to 1
                            activate
                            set foundTab to true
                            exit repeat
                        end if
                    end repeat
                    if foundTab then exit repeat
                end repeat
            end if
            if foundTab is false then
                activate
            end if
            return foundTab
        end tell
        """
        return executeBooleanScript(script)
    }

    private func activateChromeTab(url: String) -> Bool {
        guard isBrowserRunning("Chrome") else { return false }
        let escapedURL = escapeAppleScriptString(url)
        let script = """
        tell application "Google Chrome"
            set targetURL to "\(escapedURL)"
            set foundTab to false
            if (count of windows) > 0 then
                repeat with w in windows
                    set tabIndex to 0
                    repeat with t in tabs of w
                        set tabIndex to tabIndex + 1
                        if (URL of t as text) is targetURL then
                            set active tab index of w to tabIndex
                            set index of w to 1
                            activate
                            set foundTab to true
                            exit repeat
                        end if
                    end repeat
                    if foundTab then exit repeat
                end repeat
            end if
            if foundTab is false then
                activate
            end if
            return foundTab
        end tell
        """
        return executeBooleanScript(script)
    }

    private func executeBooleanScript(_ script: String) -> Bool {
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return false }
        let result = appleScript.executeAndReturnError(&error)
        if error != nil { return false }
        return result.booleanValue
    }

    private func escapeAppleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    func isBrowserRunning(_ browserName: String) -> Bool {
        let bundleId: String
        switch browserName.lowercased() {
        case "safari": bundleId = "com.apple.Safari"
        case "chrome", "google chrome": bundleId = "com.google.Chrome"
        default: return false
        }

        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first != nil
    }
}