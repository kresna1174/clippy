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
    @State private var hotkeyMonitor: Any? = nil

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
                    .onChange(of: item.actionType) { newType in
                        if !isEditing && (item.name.isEmpty || ActionType.allCases.map(\.displayName).contains(item.name)) {
                            item.name = newType.displayName
                        }
                    }
                }

                // ── Payload (context-sensitive) ──
                if item.actionType == .workflow {
                    formSection(label: "Workflow Steps (Apps, URLs, or Commands)") {
                        VStack(alignment: .leading, spacing: 6) {
                            TextEditor(text: $item.actionPayload)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(height: 75)
                                .padding(4)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                            HStack {
                                Button("+ Add App…") { pickApp() }
                                    .controlSize(.small)
                                Spacer()
                                Text("One per line (e.g. OrbStack, Zed)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } else if needsPayload {
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
                    Button("Cancel") {
                        stopRecording()
                        onCancel()
                    }
                    Spacer()
                    Button(isEditing ? "Save" : "Add") {
                        stopRecording()
                        onSave(item)
                    }
                    .disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty ||
                              (needsPayload && item.actionPayload.trimmingCharacters(in: .whitespaces).isEmpty))
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .frame(width: 360, height: item.actionType == .workflow ? 430 : (needsPayload ? 370 : 310))
        .onDisappear {
            stopRecording()
        }
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
        case .workflow: return "Workflow Steps"
        case .systemLock, .systemEmptyTrash, .systemCloseAllApps: return ""
        }
    }

    private var payloadPlaceholder: String {
        switch item.actionType {
        case .openApp:  return "com.microsoft.VSCode"
        case .openURL:  return "https://github.com"
        case .openFile: return "~/Documents/Projects"
        case .shell:    return "git -C ~/Projects pull"
        case .workflow: return "OrbStack\nZed\nDBeaver\nBrave Browser"
        case .systemLock, .systemEmptyTrash, .systemCloseAllApps: return ""
        }
    }

    private var needsPayload: Bool {
        switch item.actionType {
        case .systemLock, .systemEmptyTrash, .systemCloseAllApps: return false
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
        stopRecording()
        isRecordingHotkey = true
        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // ESC cancels recording
                self.stopRecording()
                return nil
            }
            let relevant = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let isModifierOnly = (54...63).contains(Int(event.keyCode))
            if !relevant.isEmpty && !isModifierOnly {
                self.item.hotkeyKeyCode = Int(event.keyCode)
                self.item.hotkeyModifiers = Int(relevant.rawValue)
                let char = event.charactersIgnoringModifiers ?? ""
                let display = char.isEmpty ? "\(event.keyCode)" : char.uppercased()
                self.hotkeyKeyChar = display
                self.item.hotkeyKeyChar = display
                self.stopRecording()
                return nil
            }
            return nil
        }
    }

    private func stopRecording() {
        isRecordingHotkey = false
        if let m = hotkeyMonitor {
            NSEvent.removeMonitor(m)
            hotkeyMonitor = nil
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
            let appName = url.deletingPathExtension().lastPathComponent
            if item.actionType == .workflow {
                let trimmed = item.actionPayload.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    item.actionPayload = appName
                } else {
                    item.actionPayload = trimmed + "\n" + appName
                }
            } else {
                if let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier {
                    item.actionPayload = bundleID
                } else {
                    item.actionPayload = url.path
                }
            }
            if item.name.trimmingCharacters(in: .whitespaces).isEmpty {
                item.name = appName
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
