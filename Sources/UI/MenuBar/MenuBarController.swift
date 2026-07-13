// Sources/UI/MenuBar/MenuBarController.swift
import AppKit

class MenuBarController {
    private var statusItem: NSStatusItem?
    private var mouseMonitor: Any?

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

    func stop() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        statusItem = nil
    }
}
