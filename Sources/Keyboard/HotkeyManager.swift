import HotKey
import Foundation

class HotkeyManager {
    private var hotKey: HotKey?
    private var onTrigger: (() -> Void)?

    func register(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        setupHotKey()

        // In case an old process was terminating during launch, re-verify after 0.5s and 1.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.setupHotKey()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.setupHotKey()
        }
    }

    private func setupHotKey() {
        guard let onTrigger else { return }
        let hk = HotKey(key: .v, modifiers: [.command, .shift])
        hk.keyDownHandler = onTrigger
        self.hotKey = hk
    }

    func unregister() {
        hotKey = nil
        onTrigger = nil
    }
}
