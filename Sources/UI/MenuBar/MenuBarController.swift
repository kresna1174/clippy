// Sources/UI/MenuBar/MenuBarController.swift
import AppKit

class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var mouseMonitor: Any?

    /// Fired when the user clicks the "keep awake" indicator icon.
    var onAwakeIconClicked: (() -> Void)?

    func start(onNotchClick: @escaping () -> Void) {
        // 1px invisible status item — keeps app in menu bar space
        statusItem = NSStatusBar.system.statusItem(withLength: 1)
        statusItem?.isVisible = false

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
            let loc = NSEvent.mouseLocation
            // check notch area on whichever screen the cursor is on
            let notchScreens = NSScreen.screens.filter { $0.safeAreaInsets.top > 0 }
            for screen in notchScreens {
                let notchRect = NotchWindow.notchFrame(on: screen)
                if NSMouseInRect(loc, notchRect, false) {
                    onNotchClick()
                    return
                }
            }
        }
    }

    /// Shows a small "keep awake" icon in the menu bar while `active` is
    /// true, and hides it again otherwise — Clippy stays footprint-free in
    /// the menu bar except while it's actually holding the Mac awake.
    func setAwakeIndicator(active: Bool) {
        guard let statusItem else { return }
        if active {
            statusItem.length = NSStatusItem.squareLength
            statusItem.isVisible = true
            let image = NSImage(
                systemSymbolName: "cup.and.saucer.fill",
                accessibilityDescription: "Clippy is keeping your Mac awake — click to turn off"
            )
            // Template rendering makes it follow the standard monochrome
            // menu bar icon style (like Wi-Fi/battery) instead of drawing
            // the symbol's raw artwork at the wrong scale/color.
            image?.isTemplate = true
            statusItem.button?.image = image
            statusItem.button?.target = self
            statusItem.button?.action = #selector(awakeIconClicked)
        } else {
            statusItem.button?.image = nil
            statusItem.button?.action = nil
            statusItem.button?.target = nil
            statusItem.isVisible = false
            statusItem.length = 1
        }
    }

    @objc private func awakeIconClicked() {
        onAwakeIconClicked?()
    }

    func stop() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        statusItem = nil
    }
}
