import Foundation
import AppKit

enum DockSide: String {
    case left
    case right
    case top
    case bottom
    case none
}

enum WindowState {
    case expanded
    case collapsed
    case docked
}

final class WindowManager: ObservableObject {
    static let shared = WindowManager()

    @Published var taskWindowState: WindowState = .expanded
    @Published var activityWindowState: WindowState = .expanded
    @Published var taskDockSide: DockSide = .none
    @Published var activityDockSide: DockSide = .none

    private let dockThreshold: CGFloat = 50.0

    private init() {}

    func handleDragEnd(for window: NSWindow, at location: NSPoint) -> (WindowState, DockSide) {
        guard let screen = NSScreen.main else { return (.expanded, .none) }

        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame

        let distanceToLeft = windowFrame.minX - screenFrame.minX
        let distanceToRight = screenFrame.maxX - windowFrame.maxX
        let distanceToTop = screenFrame.maxY - windowFrame.maxY
        let distanceToBottom = windowFrame.minY - screenFrame.minY

        let minDistance = min(distanceToLeft, distanceToRight, distanceToTop, distanceToBottom)

        if minDistance < dockThreshold {
            if minDistance == distanceToLeft {
                window.setFrame(NSRect(x: screenFrame.minX, y: windowFrame.minY, width: 80, height: windowFrame.height), display: true)
                return (.docked, .left)
            } else if minDistance == distanceToRight {
                window.setFrame(NSRect(x: screenFrame.maxX - 80, y: windowFrame.minY, width: 80, height: windowFrame.height), display: true)
                return (.docked, .right)
            } else if minDistance == distanceToTop {
                window.setFrame(NSRect(x: windowFrame.minX, y: screenFrame.maxY - 60, width: windowFrame.width, height: 60), display: true)
                return (.docked, .top)
            } else if minDistance == distanceToBottom {
                window.setFrame(NSRect(x: windowFrame.minX, y: screenFrame.minY, width: windowFrame.width, height: 60), display: true)
                return (.docked, .bottom)
            }
        }

        return (.expanded, .none)
    }

    func expandWindow(_ window: NSWindow, toFrame frame: NSRect) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.allowsImplicitAnimation = true
            window.animator().setFrame(frame, display: true)
        }
    }

    func collapseWindow(_ window: NSWindow, toSide side: DockSide) {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame

        var collapsedFrame: NSRect

        switch side {
        case .left:
            collapsedFrame = NSRect(x: screenFrame.minX, y: screenFrame.minY, width: 80, height: screenFrame.height)
        case .right:
            collapsedFrame = NSRect(x: screenFrame.maxX - 80, y: screenFrame.minY, width: 80, height: screenFrame.height)
        case .top:
            collapsedFrame = NSRect(x: screenFrame.minX + 100, y: screenFrame.maxY - 60, width: screenFrame.width - 200, height: 60)
        case .bottom:
            collapsedFrame = NSRect(x: screenFrame.minX + 100, y: screenFrame.minY, width: screenFrame.width - 200, height: 60)
        case .none:
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.allowsImplicitAnimation = true
            window.animator().setFrame(collapsedFrame, display: true)
        }
    }
}