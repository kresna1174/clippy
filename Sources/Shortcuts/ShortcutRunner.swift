// Sources/Shortcuts/ShortcutRunner.swift
import AppKit
import Foundation

class ShortcutRunner {
    static let shared = ShortcutRunner()
    private init() {}

    /// Run a shortcut item. Completion is called on main queue with optional error message.
    func run(_ item: ShortcutItem, completion: ((String?) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            let error = self.execute(item)
            DispatchQueue.main.async { completion?(error) }
        }
    }

    private func execute(_ item: ShortcutItem) -> String? {
        switch item.actionType {
        case .openApp:
            return openApp(bundleID: item.actionPayload)
        case .openURL:
            return openURL(string: item.actionPayload)
        case .openFile:
            return openFile(path: item.actionPayload)
        case .shell:
            return runShell(command: item.actionPayload)
        case .systemLock:
            lockScreen()
            return nil
        case .systemEmptyTrash:
            emptyTrash()
            return nil
        }
    }

    // MARK: - Action Implementations

    private func openApp(bundleID: String) -> String? {
        guard !bundleID.isEmpty else { return "No app specified" }
        // Try bundle ID first
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config)
            return nil
        }
        // Fallback: treat as file path
        let url = URL(fileURLWithPath: bundleID)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
            return nil
        }
        return "App not found: \(bundleID)"
    }

    private func openURL(string: String) -> String? {
        guard !string.isEmpty, let url = URL(string: string) else {
            return "Invalid URL: \(string)"
        }
        NSWorkspace.shared.open(url)
        return nil
    }

    private func openFile(path: String) -> String? {
        guard !path.isEmpty else { return "No path specified" }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return "Path not found: \(path)"
        }
        NSWorkspace.shared.open(url)
        return nil
    }

    private func runShell(command: String) -> String? {
        guard !command.isEmpty else { return "No command specified" }
        let task = Process()
        task.launchPath = "/bin/zsh"
        task.arguments = ["-c", command]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus != 0 {
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                return output.isEmpty ? "Command failed (exit \(task.terminationStatus))" : output
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func lockScreen() {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession")
        if FileManager.default.fileExists(atPath: url.path) {
            let task = Process()
            task.executableURL = url
            task.arguments = ["-suspend"]
            try? task.run()
        } else {
            // Fallback
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/Frameworks/LocalAuthentication.framework"))
        }
    }

    private func emptyTrash() {
        let script = "tell application \"Finder\" to empty trash"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}
