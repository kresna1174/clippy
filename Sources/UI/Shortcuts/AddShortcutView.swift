// Sources/UI/Shortcuts/AddShortcutView.swift
import SwiftUI
import AppKit

struct AddShortcutView: View {
    @State var item: ShortcutItem
    let onSave: (ShortcutItem) -> Void
    let onCancel: () -> Void
    let isEditing: Bool

    /// Printable key character captured during hotkey recording.
    @State private var hotkeyKeyChar: String = ""
    @State private var isRecordingHotkey = false

    // MARK: - Init

    init(
        item: ShortcutItem? = nil,
        onSave: @escaping (ShortcutItem) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let base = item ?? ShortcutItem(
            name: "",
            actionType: .openApp,
            actionPayload: "",
            hotkeyKeyCode: nil,
            hotkeyModifiers: 0,
            sortOrder: 0
        )
        _item = State(initialValue: base)
        // Pre-populate the key char from the stored value (for edits)
        _hotkeyKeyChar = State(initialValue: base.hotkeyKeyChar ?? "")
        self.onSave = onSave
        self.onCancel = onCancel
        self.isEditing = item != nil
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                // ── Title ──
                Text(isEditing ? "Edit Shortcut" : "New Shortcut")
                    .font(.system(size: 15, weight: .semibold))

                // ── Name field ──
                formSection(label: "Name") {
                    TextField("e.g. Open VS Code", text: $item.name)
                        .textFieldStyle(.roundedBorder)
                }

                // ── Action type ──
                formSection(label: "Action") {
                    Picker("", selection: $item.actionType) {
                        ForEach(ActionType.allCases, id: \.self) { type in
                            HStack {
                                Image(systemName: type.sfSymbol)
                                Text(type.displayName)
                            }
                            .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                // ── Payload (context-sensitive) ──
                if needsPayload {
                    formSection(label: payloadLabel) {
                        HStack {
                            TextField(payloadPlaceholder, text: $item.actionPayload)
                                .textFieldStyle(.roundedBorder)
                            if item.actionType == .openApp {
                                Button("Browse…") { pickApp() }
                            } else if item.actionType == .openFile {
                                Button("Browse…") { pickFile() }
                            }
                        }
                    }
                }

                // ── Global hotkey recorder ──
                formSection(label: "Global Hotkey (optional)") {
                    HStack(spacing: 8) {
                        // Recording pill
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    isRecordingHotkey ? Color.accentColor : Color.secondary.opacity(0.3),
                                    lineWidth: 1
                                )
                                .frame(height: 28)
                            Text(hotkeyDisplayText)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(isRecordingHotkey ? .accentColor : .primary)
                                .padding(.horizontal, 8)
                        }
                        .frame(maxWidth: 140)
                        .contentShape(Rectangle())
                        .onTapGesture { startRecording() }

                        // Clear button
                        if item.hotkeyKeyCode != nil {
                            Button("Clear") {
                                item.hotkeyKeyCode = nil
                                item.hotkeyModifiers = 0
                                item.hotkeyKeyChar = nil
                                hotkeyKeyChar = ""
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                    if isRecordingHotkey {
                        Text("Press your shortcut keys…")
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                    }
                }

                Spacer()

                // ── Footer buttons ──
                HStack {
                    Button("Cancel", action: onCancel)
                    Spacer()
                    Button(isEditing ? "Save" : "Add") {
                        onSave(item)
                    }
                    .disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty ||
                              (needsPayload && item.actionPayload.trimmingCharacters(in: .whitespaces).isEmpty))
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .frame(width: 340, height: 360)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func formSection<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            content()
        }
    }

    private var payloadLabel: String {
        switch item.actionType {
        case .openApp:  return "App (Bundle ID or path)"
        case .openURL:  return "URL"
        case .openFile: return "File / Folder Path"
        case .shell:    return "Shell Command"
        case .systemLock, .systemEmptyTrash: return ""
        }
    }

    private var payloadPlaceholder: String {
        switch item.actionType {
        case .openApp:  return "com.microsoft.VSCode"
        case .openURL:  return "https://github.com"
        case .openFile: return "~/Documents/Projects"
        case .shell:    return "git -C ~/Projects pull"
        case .systemLock, .systemEmptyTrash: return ""
        }
    }

    private var needsPayload: Bool {
        switch item.actionType {
        case .systemLock, .systemEmptyTrash: return false
        default: return true
        }
    }

    private var hotkeyDisplayText: String {
        if isRecordingHotkey { return "Recording…" }
        guard item.hotkeyKeyCode != nil else { return "Click to record" }
        let mods = NSEvent.ModifierFlags(rawValue: UInt(item.hotkeyModifiers))
        var text = ""
        if mods.contains(.control) { text += "⌃" }
        if mods.contains(.option)  { text += "⌥" }
        if mods.contains(.shift)   { text += "⇧" }
        if mods.contains(.command) { text += "⌘" }
        text += hotkeyKeyChar
        return text.isEmpty ? "Click to record" : text
    }

    // MARK: - Hotkey recording

    private func startRecording() {
        isRecordingHotkey = true
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let relevant = event.modifierFlags.intersection([.command, .shift, .option, .control])
            // Require at least one modifier to avoid capturing bare letter presses
            if !relevant.isEmpty && event.keyCode != 0 {
                self.item.hotkeyKeyCode = Int(event.keyCode)
                self.item.hotkeyModifiers = Int(relevant.rawValue)
                let keyChar = event.charactersIgnoringModifiers?.uppercased() ?? ""
                self.hotkeyKeyChar = keyChar
                self.item.hotkeyKeyChar = keyChar
                self.isRecordingHotkey = false
            }
            return nil // consume the event while recording
        }
    }

    // MARK: - File / App pickers

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            if let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier {
                item.actionPayload = bundleID
            } else {
                item.actionPayload = url.path
            }
            if item.name.trimmingCharacters(in: .whitespaces).isEmpty {
                item.name = url.deletingPathExtension().lastPathComponent
            }
        }
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            item.actionPayload = url.path
            if item.name.trimmingCharacters(in: .whitespaces).isEmpty {
                item.name = url.lastPathComponent
            }
        }
    }
}
