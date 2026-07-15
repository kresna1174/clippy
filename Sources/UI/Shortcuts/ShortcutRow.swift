// Sources/UI/Shortcuts/ShortcutRow.swift
import SwiftUI
import AppKit

struct ShortcutRow: View {
    let item: ShortcutItem
    let onRun: (ShortcutItem) -> Void
    let onEdit: (ShortcutItem) -> Void
    let onDelete: (ShortcutItem) -> Void

    @State private var isHovered = false

    private var iconColor: Color {
        switch item.actionType {
        case .openApp:         return .blue
        case .openURL:         return .green
        case .openFile:        return .orange
        case .shell:           return .purple
        case .systemLock:      return .red
        case .systemEmptyTrash: return .gray
        }
    }

    /// Fetch the real app icon from NSWorkspace (for openApp type)
    private var appIcon: NSImage? {
        guard item.actionType == .openApp, !item.actionPayload.isEmpty else { return nil }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.actionPayload) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        // Fallback: treat payload as a file path
        if FileManager.default.fileExists(atPath: item.actionPayload) {
            return NSWorkspace.shared.icon(forFile: item.actionPayload)
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 10) {
            // ── Icon ──
            if let img = appIcon {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                Image(systemName: item.sfSymbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 22, height: 22)
            }

            // ── Name + subtitle ──
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(item.actionType.displayName)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // ── Hotkey badge ──
            if let hotkeyLabel = hotkeyDisplayString, !hotkeyLabel.isEmpty {
                Text(hotkeyLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // ── Action buttons (shown on hover) ──
            if isHovered {
                HStack(spacing: 4) {
                    Button(action: { onEdit(item) }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button(action: { onRun(item) }) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)

                    Button(action: { onDelete(item) }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? Color.white.opacity(0.08) : Color.clear)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onEdit(item) }
        .onTapGesture { onRun(item) }
    }

    // MARK: - Hotkey display

    /// Builds a symbol string like "⌃⌥⇧⌘" from the stored modifier flags.
    /// The key character itself is omitted here because converting a raw CGKeyCode
    /// to a printable character requires a Carbon call; the full string is assembled
    /// properly inside AddShortcutView which has access to the character at record time.
    private var hotkeyDisplayString: String? {
        guard item.hotkeyKeyCode != nil else { return nil }
        let mods = NSEvent.ModifierFlags(rawValue: UInt(item.hotkeyModifiers))
        var parts = ""
        if mods.contains(.control) { parts += "⌃" }
        if mods.contains(.option)  { parts += "⌥" }
        if mods.contains(.shift)   { parts += "⇧" }
        if mods.contains(.command) { parts += "⌘" }
        // Append the stored key character if available
        if let keyChar = item.hotkeyKeyChar, !keyChar.isEmpty {
            parts += keyChar
        } else if !parts.isEmpty {
            parts += "…"
        }
        return parts.isEmpty ? nil : parts
    }
}
