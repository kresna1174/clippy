// Sources/UI/NotchPanel/NotchWindow.swift
import AppKit

class NotchWindow: NSWindow {
    private(set) var isExpanded = false
    private let targetScreen: NSScreen

    static func notchFrame(on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let notchWidth: CGFloat = 162
        let notchHeight: CGFloat = 26
        let x = screenFrame.midX - notchWidth / 2
        let y = screenFrame.maxY - notchHeight
        return NSRect(x: x, y: y, width: notchWidth, height: notchHeight)
    }

    static func expandedFrame(on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let panelWidth: CGFloat = 480
        let panelHeight: CGFloat = 520
        let notchHeight: CGFloat = 26
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.maxY - notchHeight - panelHeight
        return NSRect(x: x, y: y, width: panelWidth, height: notchHeight + panelHeight)
    }

    init(screen: NSScreen) {
        self.targetScreen = screen
        let frame = NotchWindow.notchFrame(on: screen)
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        backgroundColor = .black
        isOpaque = true
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    func animateExpand(completion: (() -> Void)? = nil) {
        guard !isExpanded else { completion?(); return }
        let target = NotchWindow.expandedFrame(on: targetScreen)
        hasShadow = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(target, display: true)
        } completionHandler: {
            self.isExpanded = true
            completion?()
        }
    }

    func animateCollapse(completion: (() -> Void)? = nil) {
        guard isExpanded else { completion?(); return }
        let target = NotchWindow.notchFrame(on: targetScreen)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(target, display: true)
        } completionHandler: {
            self.hasShadow = false
            self.isExpanded = false
            completion?()
        }
    }
}
