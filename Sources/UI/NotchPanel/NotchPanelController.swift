// Sources/UI/NotchPanel/NotchPanelController.swift
import AppKit
import SwiftUI

class NotchPanelController {
    private var window: NotchWindow?
    private var currentScreen: NSScreen?
    private let store: ClipboardStore
    private let shortcutsViewModel: ShortcutsViewModel
    private var viewModel: PanelViewModel?
    private let dismissMonitor = PanelDismissMonitor()
    private var previousApp: NSRunningApplication?

    var onShowSettings: (() -> Void)?

    init(store: ClipboardStore, shortcutsViewModel: ShortcutsViewModel) {
        self.store = store
        self.shortcutsViewModel = shortcutsViewModel
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
                shortcutsViewModel: shortcutsViewModel,
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
                },
                onRunShortcut: { shortcut in
                    ShortcutRunner.shared.run(shortcut)
                }
            )
            w.contentView = NSHostingView(rootView: content)
            window = w
        }

        viewModel?.reload()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.animateExpand()

        dismissMonitor.start(frame: { [weak self] in self?.window?.frame }, onDismiss: { [weak self] in self?.hide() })
    }

    func hide() {
        dismissMonitor.stop()
        window?.animateCollapse { [weak self] in
            self?.window?.orderOut(nil)
            self?.window = nil
            self?.viewModel = nil
            self?.currentScreen = nil
        }
    }

    private func handleSelect(item: ClipboardItemSummary, paste: Bool) {
        ClipboardPasteboardWriter.write(item, store: store)
        hide()
        if paste {
            simulatePaste(into: previousApp)
        }
    }
}
