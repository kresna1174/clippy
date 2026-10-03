// Sources/UI/Panel/FloatingPanelController.swift
import AppKit
import SwiftUI

class FloatingPanelController {
    private var window: FloatingPanelWindow?
    private var viewModel: PanelViewModel?
    private let dismissMonitor = PanelDismissMonitor()
    private var previousApp: NSRunningApplication?
    private let store: ClipboardStore
    private let shortcutsViewModel: ShortcutsViewModel

    var onShowSettings: (() -> Void)?
    private(set) var isVisible = false

    init(store: ClipboardStore, shortcutsViewModel: ShortcutsViewModel) {
        self.store = store
        self.shortcutsViewModel = shortcutsViewModel
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
        var content = NotchPanelContent(
            viewModel: vm,
            shortcutsViewModel: shortcutsViewModel,
            onSelect: { [weak self] item, isCommandClick in
                self?.handleSelect(item: item, paste: isCommandClick)
            },
            onPin: { [weak self] item in
                guard let self else { return }
                try? self.store.togglePin(id: item.id)
                self.viewModel?.reload()
            },
            onDelete: { [weak self] item in
                guard let self else { return }
                try? self.store.delete(id: item.id)
                self.viewModel?.reload()
            },
            onClearUnpinned: { [weak self] in
                guard let self else { return }
                try? self.store.clearUnpinned()
                self.viewModel?.reload()
            },
            onClearAll: { [weak self] in
                guard let self else { return }
                try? self.store.clearAll()
                self.viewModel?.reload()
            },
            onSettings: { [weak self] in
                self?.onShowSettings?()
            },
            onRunShortcut: { shortcut in
                ShortcutRunner.shared.run(shortcut)
            }
        )
        content.isFloating = true
        w.contentView = NSHostingView(rootView: content)
        window = w

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isVisible = true

        dismissMonitor.start(frame: { [weak self] in self?.window?.frame }, onDismiss: { [weak self] in self?.hide() })
    }

    func hide() {
        dismissMonitor.stop()
        window?.orderOut(nil)
        window = nil
        viewModel = nil
        isVisible = false
    }

    // MARK: - Private

    private func handleSelect(item: ClipboardItemSummary, paste: Bool) {
        ClipboardPasteboardWriter.write(item, store: store)
        hide()
        if paste {
            simulatePaste(into: previousApp)
        }
    }

    private func resolvePopupOrigin() -> CGPoint {
        if let rect = axCaretRect() {
            // AX returns Quartz coords (Y from bottom of main screen); convert to AppKit
            let screen = screenContaining(CGPoint(x: rect.midX, y: rect.midY))
            let flippedY = screen.frame.maxY - rect.maxY
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
