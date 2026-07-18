import AppKit

func simulatePaste(into app: NSRunningApplication?) {
    guard let app else { return }
    if #available(macOS 14.0, *) {
        NSApp.yieldActivation(to: app)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            sendCmdV()
        }
    } else {
        app.activate(options: .activateIgnoringOtherApps)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            sendCmdV()
        }
    }
}

private func sendCmdV() {
    let src = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
    let up   = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
    down?.flags = .maskCommand
    up?.flags   = .maskCommand
    down?.post(tap: .cgAnnotatedSessionEventTap)
    up?.post(tap: .cgAnnotatedSessionEventTap)
}
