// Sources/UI/Panel/FloatingPanelController.swift
import AppKit
import SwiftUI

class FloatingPanelController {
    private var window: FloatingPanelWindow?
    private var viewModel: PanelViewModel?
    private var outsideClickMonitor: Any?
    private var escKeyMonitor: Any?
    private var previousApp: NSRunningApplication?
    private let store: ClipboardStore

    var onShowSettings: (() -> Void)?
    private(set) var isVisible = false

    init(store: ClipboardStore) {
        self.store = store
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        guard !isVisible else { return }
        previousApp = NSWorkspace.shared.frontmostApplication

        let origin = resolvePopupOrigin()
        let size = FloatingPanelWindow.panelSize
        let screen = screenContaining(origin)
        let frame = clampedFrame(origin: origin, size: size, screen: screen)

        let vm = PanelViewModel(store: store)
        viewModel = vm

        let w = FloatingPanelWindow(frame: frame)
        let content = NotchPanelContent(
            viewModel: vm,
            onSelect: { [weak self] item, isCommandClick in
                self?.handleSelect(item: item, paste: isCommandClick)
            },
            onPin: { [weak self] item in
                guard let self else { return }
                try? self.store.togglePin(id: item.id)
                self.viewModel?.reload()
            },
            onSettings: { [weak self] in
                self?.onShowSettings?()
            }
        )
        w.contentView = NSHostingView(rootView: content)
        window = w

        vm.reload()
        w.makeKeyAndOrderFront(nil)
        isVisible = true

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self, let w = self.window else { return }
            if !NSMouseInRect(NSEvent.mouseLocation, w.frame, false) { self.hide() }
        }

        escKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.hide(); return nil }
            return event
        }
    }

    func hide() {
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m); outsideClickMonitor = nil }
        if let m = escKeyMonitor { NSEvent.removeMonitor(m); escKeyMonitor = nil }
        window?.orderOut(nil)
        window = nil
        viewModel = nil
        isVisible = false
    }

    // MARK: - Private

    private func handleSelect(item: ClipboardItem, paste: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.type {
        case .text:
            if let str = String(data: item.content, encoding: .utf8) { pb.setString(str, forType: .string) }
        case .image:
            pb.setData(item.content, forType: NSPasteboard.PasteboardType("public.png"))
        case .file:
            if let str = String(data: item.content, encoding: .utf8), let url = URL(string: str) {
                pb.writeObjects([url as NSURL])
            }
        }
        hide()
        if paste {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.previousApp?.activate(options: .activateIgnoringOtherApps)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let src = CGEventSource(stateID: .hidSystemState)
                    let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
                    let up   = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
                    down?.flags = .maskCommand; up?.flags = .maskCommand
                    down?.post(tap: .cgAnnotatedSessionEventTap)
                    up?.post(tap: .cgAnnotatedSessionEventTap)
                }
            }
        }
    }

    private func resolvePopupOrigin() -> CGPoint {
        if let rect = axCaretRect() {
            // AX returns Quartz coords (Y from bottom of main screen); convert to AppKit
            let flippedY = (NSScreen.main?.frame.maxY ?? 0) - rect.maxY
            return CGPoint(x: rect.minX, y: flippedY - 8)
        }
        return NSEvent.mouseLocation
    }

    private func axCaretRect() -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              CFGetTypeID(focused as CFTypeRef) == AXUIElementGetTypeID() else { return nil }
        let el = focused as! AXUIElement
        var rangeVal: AnyObject?
        guard AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &rangeVal) == .success,
              CFGetTypeID(rangeVal as CFTypeRef) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        AXValueGetValue(rangeVal as! AXValue, AXValueType.cfRange, &range)
        var rangeAXVal = range
        guard let rangeAX = AXValueCreate(AXValueType.cfRange, &rangeAXVal) else { return nil }
        var boundsVal: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(el, kAXBoundsForRangeParameterizedAttribute as CFString, rangeAX, &boundsVal) == .success,
              CFGetTypeID(boundsVal as CFTypeRef) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        AXValueGetValue(boundsVal as! AXValue, AXValueType.cgRect, &rect)
        return rect
    }

    private func screenContaining(_ point: CGPoint) -> NSScreen {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func clampedFrame(origin: CGPoint, size: CGSize, screen: NSScreen) -> NSRect {
        let margin: CGFloat = 8
        let sf = screen.visibleFrame
        var x = origin.x
        var y = origin.y - size.height

        // flip above caret if would go below screen
        if y < sf.minY + margin { y = origin.y + 8 }
        // clamp right
        if x + size.width > sf.maxX - margin { x = sf.maxX - margin - size.width }
        // clamp left
        if x < sf.minX + margin { x = sf.minX + margin }
        // clamp top
        if y + size.height > sf.maxY - margin { y = sf.maxY - margin - size.height }

        return NSRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
