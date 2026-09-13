import AppKit

/// Shared outside-click / ESC dismissal logic, previously duplicated between
/// `FloatingPanelController` and `NotchPanelController`.
final class PanelDismissMonitor {
    private var outsideClickMonitor: Any?
    private var escKeyMonitor: Any?

    /// - Parameters:
    ///   - frame: Returns the panel's current screen frame; clicks inside it don't dismiss.
    ///   - onDismiss: Called when an outside click or ESC should close the panel.
    func start(frame: @escaping () -> NSRect?, onDismiss: @escaping () -> Void) {
        stop()

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
            // Don't hide if a modal (e.g. NSOpenPanel) is active
            guard NSApp.modalWindow == nil, let frame = frame() else { return }
            if !NSMouseInRect(NSEvent.mouseLocation, frame, false) { onDismiss() }
        }

        escKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // ESC
                onDismiss()
                return nil
            }
            return event
        }
    }

    func stop() {
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m); outsideClickMonitor = nil }
        if let m = escKeyMonitor { NSEvent.removeMonitor(m); escKeyMonitor = nil }
    }

    deinit { stop() }
}
