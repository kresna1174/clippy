// Sources/UI/NotchPanel/NotchWindow.swift
import AppKit

class NotchWindow: NSWindow {
    private(set) var isExpanded = false
    private let targetScreen: NSScreen

    static func notchFrame(on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let notchHeight = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 26
        if let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            let notchX = leftArea.maxX
            let notchWidth = rightArea.minX - leftArea.maxX
            let notchY = screenFrame.maxY - notchHeight
            return NSRect(x: notchX, y: notchY, width: notchWidth, height: notchHeight)
        }
        // fallback for screens without notch API
        let notchWidth: CGFloat = 200
        let x = screenFrame.midX - notchWidth / 2
        let y = screenFrame.maxY - notchHeight
        return NSRect(x: x, y: y, width: notchWidth, height: notchHeight)
    }

    static let shadowPad: CGFloat = 4  // minimal padding for clean clipping

    static func expandedFrame(on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let panelWidth: CGFloat = 480
        let panelHeight: CGFloat = 520
        let notchHeight = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 26
        let sp = shadowPad
        let x = screenFrame.midX - panelWidth / 2 - sp
        let y = screenFrame.maxY - notchHeight - panelHeight - sp
        return NSRect(x: x, y: y, width: panelWidth + sp * 2, height: notchHeight + panelHeight + sp)
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
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func animateExpand(completion: (() -> Void)? = nil) {
        guard !isExpanded else { completion?(); return }
        let target = NotchWindow.expandedFrame(on: targetScreen)
        hasShadow = false  // AppKit shadow is rectangular — use SwiftUI shadow instead
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
            self.isExpanded = false
            completion?()
        }
    }
}
