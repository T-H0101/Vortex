import Foundation
import SwiftData
import AppKit

@Model
final class ActivityItem {
    var id: UUID
    var appName: String
    var bundleIdentifier: String
    var appIcon: Data?
    var lastActiveTime: Date
    var tabTitle: String?
    var tabURL: String?
    var isBrowser: Bool

    init(
        id: UUID = UUID(),
        appName: String,
        bundleIdentifier: String,
        appIcon: Data? = nil,
        lastActiveTime: Date = Date(),
        tabTitle: String? = nil,
        tabURL: String? = nil,
        isBrowser: Bool = false
    ) {
        self.id = id
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.appIcon = appIcon
        self.lastActiveTime = lastActiveTime
        self.tabTitle = tabTitle
        self.tabURL = tabURL
        self.isBrowser = isBrowser
    }
}

extension ActivityItem {
    var isActive: Bool {
        Date().timeIntervalSince(lastActiveTime) < 300
    }

    var timeSinceActive: String {
        let interval = Date().timeIntervalSince(lastActiveTime)
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h ago"
        } else {
            return "\(Int(interval / 86400))d ago"
        }
    }

    var nsImage: NSImage? {
        guard let data = appIcon else { return nil }
        return NSImage(data: data)
    }
}