import Foundation
import AppKit

final class BrowserActivityAdapter: @unchecked Sendable {
    static let shared = BrowserActivityAdapter()

    private let cacheTTL: TimeInterval = 12.0
    private var tabCache: [String: (timestamp: Date, tabs: [BrowserTab])] = [:]
    private let cacheLock = NSLock()

    private init() {}

    struct BrowserTab: Identifiable {
        let id = UUID()
        let title: String
        let url: String
        let browserName: String
        var windowIndex: Int?
        var tabIndex: Int?
    }

    func fetchTabs(for browser: String) -> [BrowserTab] {
        switch browser {
        case "Safari":
            return fetchSafariTabs()
        case "Chrome":
            return fetchChromeTabs()
        case "Terminal":
            return fetchTerminalTabs()
        default:
            return []
        }
    }

    func fetchTerminalTabs() -> [BrowserTab] {
        let terminals: [(name: String, bundleId: String, script: String)] = [
            ("Terminal", "com.apple.Terminal", """
                tell application "Terminal"
                    set tabList to {}
                    try
                        if (count of windows) > 0 then
                            set tabCount to (count of tabs of window 1)
                            repeat with i from 1 to tabCount
                                set end of tabList to {"Terminal " & i, "terminal://w1t" & i, 1, i}
                            end repeat
                        end if
                    end try
                    return tabList
                end tell
                """),
            ("iTerm2", "com.googlecode.iterm2", """
                tell application "iTerm2"
                    set tabList to {}
                    try
                        set winCount to (count of windows)
                        repeat with wIdx from 1 to winCount
                            set tabCount to (number of tabs of window wIdx)
                            repeat with tIdx from 1 to tabCount
                                try
                                    set tabName to name of current session of tab tIdx of window wIdx
                                    if tabName is missing value or tabName is "" then
                                        set tabName to "Terminal " & tIdx
                                    end if
                                    set end of tabList to {tabName, "iterm2://w" & wIdx & "t" & tIdx, wIdx, tIdx}
                                on error
                                    set end of tabList to {"Terminal " & tIdx, "iterm2://w" & wIdx & "t" & tIdx, wIdx, tIdx}
                                end try
                            end repeat
                        end repeat
                    on error
                        -- fallback: try first terminal
                        try
                            set tabCount to (number of tabs of window 1)
                            repeat with tIdx from 1 to tabCount
                                set tabName to name of current session of tab tIdx of window 1
                                if tabName is missing value or tabName is "" then
                                    set tabName to "Terminal " & tIdx
                                end if
                                set end of tabList to {tabName, "iterm2://w1t" & tIdx, 1, tIdx}
                            end repeat
                        end try
                    end try
                    return tabList
                end tell
                """)
        ]

        var allTabs: [BrowserTab] = []

        for terminal in terminals {
            guard isBrowserRunning(terminal.name) else { continue }
            if let cached = cachedTabs(for: terminal.name) {
                allTabs.append(contentsOf: cached)
                continue
            }

            let tabs = executeScript(terminal.script, browserName: terminal.name)
            storeTabs(tabs, for: terminal.name)
            allTabs.append(contentsOf: tabs)
        }

        return allTabs
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
        guard count > 0 else { return [] }

        for i in 1...count {
            guard let itemDescriptor = result.atIndex(i) as NSAppleEventDescriptor? else { continue }
            let itemsCount = itemDescriptor.numberOfItems
            if itemsCount >= 2 {
                let title = itemDescriptor.atIndex(1)?.stringValue ?? "Untitled"
                let url = itemDescriptor.atIndex(2)?.stringValue ?? ""
                var windowIndex: Int?
                var tabIndex: Int?
                if itemsCount >= 4 {
                    if let w = itemDescriptor.atIndex(3)?.int32Value {
                        windowIndex = Int(w)
                    }
                    if let t = itemDescriptor.atIndex(4)?.int32Value {
                        tabIndex = Int(t)
                    }
                }
                tabs.append(BrowserTab(title: title, url: url, browserName: browserName, windowIndex: windowIndex, tabIndex: tabIndex))
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
        if tab.browserName == "Terminal" || tab.browserName == "iTerm2" {
            return !tab.title.isEmpty && activateTerminalTab(title: tab.title, windowIndex: tab.windowIndex, tabIndex: tab.tabIndex, browserName: tab.browserName)
        }

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

    private func activateTerminalTab(title: String, windowIndex: Int? = nil, tabIndex: Int? = nil, browserName: String = "Terminal") -> Bool {
        if let wIdx = windowIndex, let tIdx = tabIndex {
            return activateTerminalByIndex(windowIndex: wIdx, tabIndex: tIdx, browserName: browserName)
        }
        return activateTerminalByTitle(title: title, browserName: browserName)
    }

    private func activateTerminalByIndex(windowIndex: Int, tabIndex: Int, browserName: String) -> Bool {
        let script: String
        if browserName == "iTerm2" {
            script = """
                tell application "iTerm2"
                    set foundTab to false
                    try
                        select tab \(tabIndex) of window \(windowIndex)
                        activate
                        set foundTab to true
                    end try
                    return foundTab
                end tell
                """
        } else {
            script = """
                tell application "Terminal"
                    set foundTab to false
                    try
                        set selected tab of window 1 to tab \(tabIndex)
                        activate
                        set foundTab to true
                    on error
                        activate
                    end try
                    return foundTab
                end tell
                """
        }

        guard isBrowserRunning(browserName) else { return false }
        return executeBooleanScript(script)
    }

    private func activateTerminalByTitle(title: String, browserName: String) -> Bool {
        let script: String
        if browserName == "iTerm2" {
            script = """
                tell application "iTerm2"
                    set foundTab to false
                    set escapedTitle to "\(escapeAppleScriptString(title))"
                    try
                        set winCount to (count of windows)
                        repeat with wIdx from 1 to winCount
                            if foundTab is true then exit repeat
                            set tabCount to (number of tabs of window wIdx)
                            repeat with tIdx from 1 to tabCount
                                if foundTab is true then exit repeat
                                try
                                    set tabName to name of current session of tab tIdx of window wIdx
                                    if tabName is escapedTitle then
                                        select tab tIdx of window wIdx
                                        activate
                                        set foundTab to true
                                        exit repeat
                                    end if
                                end try
                            end repeat
                        end repeat
                    end try
                    if foundTab is false then
                        activate
                    end if
                    return foundTab
                end tell
                """
        } else {
            script = """
                tell application "Terminal"
                    set foundTab to false
                    try
                        if (count of windows) > 0 then
                            set tabCount to (count of tabs of window 1)
                            repeat with i from 1 to tabCount
                                set current tab of window 1 to tab i
                                activate
                                set foundTab to true
                                exit repeat
                            end repeat
                        end if
                    end try
                    if foundTab is false then
                        activate
                    end if
                    return foundTab
                end tell
                """
        }

        guard isBrowserRunning(browserName) else { return false }
        return executeBooleanScript(script)
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
        case "terminal": bundleId = "com.apple.Terminal"
        case "iterm2": bundleId = "com.googlecode.iterm2"
        default: return false
        }

        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first != nil
    }
}