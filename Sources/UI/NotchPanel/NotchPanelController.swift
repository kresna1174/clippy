// Sources/UI/NotchPanel/NotchPanelController.swift
import AppKit
import SwiftUI

class NotchPanelController {
    private var window: NotchWindow?
    private var currentScreen: NSScreen?
    private let store: ClipboardStore
    private var viewModel: PanelViewModel?
    private var outsideClickMonitor: Any?
    private var escKeyMonitor: Any?
    private var previousApp: NSRunningApplication?

    var onShowSettings: (() -> Void)?

    init(store: ClipboardStore) {
        self.store = store
    }

    private func screenUnderMouse() -> NSScreen {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    func toggle() {
        if let w = window, w.isExpanded {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let screen = screenUnderMouse()

        // remember the app that was active before we steal focus
        previousApp = NSWorkspace.shared.frontmostApplication

        // recreate window if active screen changed
        if window != nil && currentScreen !== screen {
            window?.orderOut(nil)
            window = nil
            viewModel = nil
        }

        if window == nil {
            currentScreen = screen
            let vm = PanelViewModel(store: store)
            viewModel = vm
            let w = NotchWindow(screen: screen)
            let content = NotchPanelContent(
                viewModel: vm,
                onSelect: { [weak self] item, isCommandClick in
                    self?.handleSelect(item: item, paste: isCommandClick)
                },
                onSettings: { [weak self] in
                    self?.onShowSettings?()
                }
            )
            w.contentView = NSHostingView(rootView: content)
            window = w
        }

        viewModel?.reload()
        window?.makeKeyAndOrderFront(nil)
        window?.animateExpand()

        // dismiss on outside click
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] event in
            guard let self, let w = self.window else { return }
            let screenLoc = NSEvent.mouseLocation
            if !NSMouseInRect(screenLoc, w.frame, false) {
                self.hide()
            }
        }

        // ESC key
        escKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                self?.hide()
                return nil
            }
            return event
        }
    }

    func hide() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        if let monitor = escKeyMonitor {
            NSEvent.removeMonitor(monitor)
            escKeyMonitor = nil
        }
        window?.animateCollapse {
            self.window?.orderOut(nil)
        }
    }

    private func handleSelect(item: ClipboardItem, paste: Bool) {
        // copy to clipboard
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.type {
        case .text:
            if let str = String(data: item.content, encoding: .utf8) {
                pb.setString(str, forType: .string)
            }
        case .image:
            pb.setData(item.content, forType: NSPasteboard.PasteboardType("public.png"))
        case .file:
            if let str = String(data: item.content, encoding: .utf8),
               let url = URL(string: str) {
                pb.writeObjects([url as NSURL])
            }
        }

        hide()

        if paste {
            // re-activate previous app then simulate ⌘V
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.previousApp?.activate(options: .activateIgnoringOtherApps)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let src = CGEventSource(stateID: .hidSystemState)
                    let vKey: CGKeyCode = 9 // V
                    let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
                    let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
                    down?.flags = .maskCommand
                    up?.flags = .maskCommand
                    down?.post(tap: .cgAnnotatedSessionEventTap)
                    up?.post(tap: .cgAnnotatedSessionEventTap)
                }
            }
        }
    }
}
