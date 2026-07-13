import HotKey

class HotkeyManager {
    private var hotKey: HotKey?

    func register(onTrigger: @escaping () -> Void) {
        hotKey = HotKey(key: .v, modifiers: [.command, .shift])
        hotKey?.keyDownHandler = onTrigger
    }

    func unregister() {
        hotKey = nil
    }
}
