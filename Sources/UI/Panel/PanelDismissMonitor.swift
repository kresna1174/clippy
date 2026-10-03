import AppKit

/// Shared outside-click / ESC / deactivate dismissal logic for panels.
final class PanelDismissMonitor {
    private var outsideClickMonitor: Any?
    private var escKeyMonitor: Any?
    private var resignActiveObserver: Any?
    private var resignKeyObserver: Any?

    /// - Parameters:
    ///   - window: The panel's NSWindow. If provided, dismissal occurs when it resigns key status.
    ///   - frame: Returns the panel's current screen frame; clicks inside it don't dismiss.
    ///   - onDismiss: Called when an outside click, ESC, or focus loss should close the panel.
    func start(window: NSWindow? = nil, frame: @escaping () -> NSRect?, onDismiss: @escaping () -> Void) {
        stop()

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            guard NSApp.modalWindow == nil, !ShortcutFormWindowHolder.isOpen, let frame = frame() else { return }
            if !NSMouseInRect(NSEvent.mouseLocation, frame, false) {
                DispatchQueue.main.async { onDismiss() }
            }
        }

        escKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // ESC
                onDismiss()
                return nil
            }
            return event
        }

        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            guard NSApp.modalWindow == nil, !ShortcutFormWindowHolder.isOpen else { return }
            onDismiss()
        }

        if let window {
            resignKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { _ in
                guard NSApp.modalWindow == nil, !ShortcutFormWindowHolder.isOpen else { return }
                DispatchQueue.main.async { onDismiss() }
            }
        }
    }

    func stop() {
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m); outsideClickMonitor = nil }
        if let m = escKeyMonitor { NSEvent.removeMonitor(m); escKeyMonitor = nil }
        if let o = resignActiveObserver { NotificationCenter.default.removeObserver(o); resignActiveObserver = nil }
        if let o = resignKeyObserver { NotificationCenter.default.removeObserver(o); resignKeyObserver = nil }
    }

    deinit { stop() }
}
