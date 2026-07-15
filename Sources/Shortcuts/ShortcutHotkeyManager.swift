// Sources/Shortcuts/ShortcutHotkeyManager.swift
import AppKit
import HotKey

class ShortcutHotkeyManager {
    private var registeredKeys: [String: HotKey] = [:] // shortcutID -> HotKey
    var onTrigger: ((ShortcutItem) -> Void)?

    func reload(shortcuts: [ShortcutItem]) {
        // Unregister all
        registeredKeys.removeAll()

        // Register each enabled shortcut that has a hotkey
        for shortcut in shortcuts where shortcut.isEnabled {
            guard let keyCode = shortcut.hotkeyKeyCode, keyCode >= 0 else { continue }
            guard let key = Key(carbonKeyCode: UInt32(keyCode)) else { continue }
            let modifiers = NSEvent.ModifierFlags(rawValue: UInt(shortcut.hotkeyModifiers))
            var cocoaModifiers: NSEvent.ModifierFlags = []
            if modifiers.contains(.command) { cocoaModifiers.insert(.command) }
            if modifiers.contains(.shift) { cocoaModifiers.insert(.shift) }
            if modifiers.contains(.option) { cocoaModifiers.insert(.option) }
            if modifiers.contains(.control) { cocoaModifiers.insert(.control) }

            let hotKey = HotKey(key: key, modifiers: cocoaModifiers)
            let capturedShortcut = shortcut
            hotKey.keyDownHandler = { [weak self] in
                self?.onTrigger?(capturedShortcut)
            }
            registeredKeys[shortcut.id] = hotKey
        }
    }

    func unregisterAll() {
        registeredKeys.removeAll()
    }
}
