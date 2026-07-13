// Sources/UI/MenuBar/MenuBarController.swift
import AppKit

class MenuBarController {
    private var statusItem: NSStatusItem?
    private var mouseMonitor: Any?

    func start(onNotchClick: @escaping () -> Void) {
        // 1px invisible status item — keeps app in menu bar space
        statusItem = NSStatusBar.system.statusItem(withLength: 1)
        statusItem?.isVisible = false

        guard let screen = NSScreen.main else { return }
        let notchRect = NotchWindow.notchFrame(on: screen)

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { event in
            let loc = NSEvent.mouseLocation
            if NSMouseInRect(loc, notchRect, false) {
                onNotchClick()
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
