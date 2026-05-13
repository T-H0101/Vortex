import Cocoa
import SwiftUI
import QuartzCore

enum WindowExpansionState {
    case collapsed
    case expanded
}

final class EdgeDockingController: ObservableObject {
    private weak var window: NSWindow?

    @Published var expansionState: WindowExpansionState = .expanded
    @Published var dockedSide: DockSide = .none
    @Published var contentSize: CGSize

    let expandedSize = CGSize(width: 430, height: 460)
    private let collapsedSideSize = CGSize(width: 56, height: 188)
    private let collapsedTopSize = CGSize(width: 280, height: 48)
    private let dockThreshold: CGFloat = 48

    private var moveObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var hoverTimer: Timer?
    private var dockEvaluationWorkItem: DispatchWorkItem?
    private var collapseWorkItem: DispatchWorkItem?
    private var returnToDockWorkItem: DispatchWorkItem?

    private var isMonitoring = false
    private var isHovering = false

    private(set) var preferredDockSide: DockSide = .right
    private(set) var autoExpandOnHover = true
    private(set) var autoReturnToDock = true
    private(set) var collapseDelay: TimeInterval = 0.9
    private(set) var returnToDockDelay: TimeInterval = 1.2
    private(set) var animationDuration: TimeInterval = 0.24

    init(window: NSWindow?) {
        self.window = window
        self.contentSize = expandedSize
    }

    func startMonitoring() {
        guard !isMonitoring, let window else { return }
        isMonitoring = true

        let center = NotificationCenter.default
        moveObserver = center.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleDockEvaluation()
        }

        screenObserver = center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleDockEvaluation()
        }

        startHoverMonitoring()
        scheduleDockEvaluation()
    }

    func stopMonitoring() {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
            self.moveObserver = nil
        }

        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }

        hoverTimer?.invalidate()
        hoverTimer = nil
        dockEvaluationWorkItem?.cancel()
        collapseWorkItem?.cancel()
        returnToDockWorkItem?.cancel()
        isMonitoring = false
    }

    func configure(
        preferredSide: DockSide,
        autoExpandOnHover: Bool,
        autoReturnToDock: Bool,
        collapseDelay: TimeInterval,
        returnToDockDelay: TimeInterval,
        animationDuration: TimeInterval
    ) {
        preferredDockSide = preferredSide
        self.autoExpandOnHover = autoExpandOnHover
        self.autoReturnToDock = autoReturnToDock
        self.collapseDelay = max(0.2, collapseDelay)
        self.returnToDockDelay = max(0.2, returnToDockDelay)
        self.animationDuration = max(0.1, animationDuration)
        scheduleDockEvaluation()
    }

    func toggleExpansion() {
        if expansionState == .expanded {
            collapseWindow()
        } else {
            expandWindow()
        }
    }

    func dock(to side: DockSide) {
        guard side != .none else {
            dockedSide = .none
            expandWindow()
            return
        }

        returnToDockWorkItem?.cancel()
        dockedSide = side
        collapseWindow()
    }

    func handleHoverChange(isHovering: Bool) {
        self.isHovering = isHovering

        if isHovering {
            collapseWorkItem?.cancel()
            returnToDockWorkItem?.cancel()
            if expansionState == .collapsed && autoExpandOnHover {
                expandWindow()
            }
            return
        }

        if expansionState == .expanded {
            if dockedSide != .none {
                scheduleCollapseIfNeeded(for: dockedSide)
            } else {
                scheduleReturnToDockIfNeeded()
            }
        }
    }

    func expandWindow() {
        guard let window, let screen = screenFor(window: window) else { return }

        let frame = expandedFrame(for: window, side: dockedSide == .none ? preferredDockSide : dockedSide, in: screen.visibleFrame)
        animateWindow(to: frame, opacity: 1.0)
        expansionState = .expanded
        updateContentSize()
    }

    func collapseWindow() {
        guard let window, let screen = screenFor(window: window) else { return }
        let side = dockedSide == .none ? preferredDockSide : dockedSide
        dockedSide = side
        let frame = collapsedFrame(for: window, side: side, in: screen.visibleFrame)
        animateWindow(to: frame, opacity: 1.0)
        expansionState = .collapsed
        updateContentSize()
    }

    private func scheduleDockEvaluation() {
        dockEvaluationWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.evaluateDockState()
        }
        dockEvaluationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private func evaluateDockState() {
        guard let window, let screen = screenFor(window: window) else { return }
        let windowFrame = window.frame
        let screenFrame = screen.visibleFrame

        let leftDistance = abs(windowFrame.minX - screenFrame.minX)
        let rightDistance = abs(screenFrame.maxX - windowFrame.maxX)
        let topDistance = abs(screenFrame.maxY - windowFrame.maxY)
        let nearestDistance = min(leftDistance, rightDistance, topDistance)

        guard nearestDistance <= dockThreshold else {
            collapseWorkItem?.cancel()
            if expansionState == .collapsed && !isHovering {
                dockedSide = .none
                expandWindow()
            } else if expansionState == .expanded {
                dockedSide = .none
            }
            return
        }

        returnToDockWorkItem?.cancel()
        if nearestDistance == topDistance {
            dockedSide = .top
        } else if nearestDistance == leftDistance {
            dockedSide = .left
        } else {
            dockedSide = .right
        }

        if expansionState == .expanded && !isHovering {
            scheduleCollapseIfNeeded(for: dockedSide)
        }
    }

    private func scheduleCollapseIfNeeded(for side: DockSide) {
        collapseWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let window, let screen = self.screenFor(window: window) else { return }
            let frame = window.frame
            let screenFrame = screen.visibleFrame

            let shouldCollapse: Bool
            switch side {
            case .left:
                shouldCollapse = abs(frame.minX - screenFrame.minX) <= self.dockThreshold
            case .right:
                shouldCollapse = abs(screenFrame.maxX - frame.maxX) <= self.dockThreshold
            case .top:
                shouldCollapse = abs(screenFrame.maxY - frame.maxY) <= self.dockThreshold
            default:
                shouldCollapse = false
            }

            if shouldCollapse && !self.isHovering {
                self.collapseWindow()
            }
        }

        collapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: workItem)
    }

    private func scheduleReturnToDockIfNeeded() {
        guard autoReturnToDock else { return }
        returnToDockWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isHovering, self.expansionState == .expanded, let window, let screen = self.screenFor(window: window) else {
                return
            }

            let targetSide = self.autoReturnSide(for: window.frame, in: screen.visibleFrame)
            self.dockedSide = targetSide
            self.collapseWindow()
        }

        returnToDockWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + returnToDockDelay, execute: workItem)
    }

    private func autoReturnSide(for frame: NSRect, in screenFrame: NSRect) -> DockSide {
        if preferredDockSide == .top {
            return .top
        }

        let distanceToLeft = abs(frame.midX - screenFrame.minX)
        let distanceToRight = abs(screenFrame.maxX - frame.midX)
        return distanceToLeft <= distanceToRight ? .left : .right
    }

    private func startHoverMonitoring() {
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.evaluateMouseHoverForCollapsedWindow()
        }
        hoverTimer?.tolerance = 0.05
    }

    private func evaluateMouseHoverForCollapsedWindow() {
        guard autoExpandOnHover, expansionState == .collapsed, let window else { return }

        let mouseLocation = NSEvent.mouseLocation
        let hoverZone = window.frame.insetBy(dx: -10, dy: -8)
        let hovering = hoverZone.contains(mouseLocation)

        if hovering {
            isHovering = true
            expandWindow()
        } else {
            isHovering = false
        }
    }

    private func updateContentSize() {
        if expansionState == .expanded {
            contentSize = expandedSize
            return
        }

        contentSize = dockedSide == .top ? collapsedTopSize : collapsedSideSize
    }

    private func expandedFrame(for window: NSWindow, side: DockSide, in screenFrame: NSRect) -> NSRect {
        let width = expandedSize.width
        let height = expandedSize.height
        let currentFrame = window.frame

        var x = currentFrame.origin.x
        var y = currentFrame.origin.y

        switch side {
        case .left:
            x = screenFrame.minX
            y = max(screenFrame.minY, min(currentFrame.origin.y, screenFrame.maxY - height))
        case .right:
            x = screenFrame.maxX - width
            y = max(screenFrame.minY, min(currentFrame.origin.y, screenFrame.maxY - height))
        case .top:
            x = max(screenFrame.minX, min(currentFrame.midX - width / 2, screenFrame.maxX - width))
            y = screenFrame.maxY - height
        default:
            x = max(screenFrame.minX, min(currentFrame.origin.x, screenFrame.maxX - width))
            y = max(screenFrame.minY, min(currentFrame.origin.y, screenFrame.maxY - height))
        }

        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func collapsedFrame(for window: NSWindow, side: DockSide, in screenFrame: NSRect) -> NSRect {
        let currentFrame = window.frame

        switch side {
        case .left:
            let x = screenFrame.minX
            let y = max(screenFrame.minY, min(currentFrame.midY - collapsedSideSize.height / 2, screenFrame.maxY - collapsedSideSize.height))
            return NSRect(x: x, y: y, width: collapsedSideSize.width, height: collapsedSideSize.height)
        case .right:
            let x = screenFrame.maxX - collapsedSideSize.width
            let y = max(screenFrame.minY, min(currentFrame.midY - collapsedSideSize.height / 2, screenFrame.maxY - collapsedSideSize.height))
            return NSRect(x: x, y: y, width: collapsedSideSize.width, height: collapsedSideSize.height)
        case .top:
            let x = max(screenFrame.minX, min(currentFrame.midX - collapsedTopSize.width / 2, screenFrame.maxX - collapsedTopSize.width))
            let y = screenFrame.maxY - collapsedTopSize.height
            return NSRect(x: x, y: y, width: collapsedTopSize.width, height: collapsedTopSize.height)
        default:
            let x = screenFrame.maxX - collapsedSideSize.width
            let y = max(screenFrame.minY, min(currentFrame.midY - collapsedSideSize.height / 2, screenFrame.maxY - collapsedSideSize.height))
            return NSRect(x: x, y: y, width: collapsedSideSize.width, height: collapsedSideSize.height)
        }
    }

    private func animateWindow(to frame: NSRect, opacity: CGFloat) {
        guard let window else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            window.animator().alphaValue = opacity
            window.animator().setFrame(frame, display: true)
        }
    }

    private func screenFor(window: NSWindow) -> NSScreen? {
        window.screen ?? NSScreen.main
    }
}