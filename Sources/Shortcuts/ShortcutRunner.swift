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
            return openApp(target: item.actionPayload)
        case .openURL:
            return openURL(string: item.actionPayload)
        case .openFile:
            return openFile(path: item.actionPayload)
        case .shell:
            return runShell(command: item.actionPayload)
        case .workflow:
            return runWorkflow(payload: item.actionPayload)
        case .systemCloseAllApps:
            closeAllApps()
            return nil
        case .systemLock:
            lockScreen()
            return nil
        case .systemEmptyTrash:
            emptyTrash()
            return nil
        }
    }

    // MARK: - Action Implementations

    private func runWorkflow(payload: String) -> String? {
        let lines = payload.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        guard !lines.isEmpty else { return "No workflow steps specified" }

        var errors: [String] = []

        for line in lines {
            let lower = line.lowercased()
            if lower == "close all" || lower == "quit all" || lower == "close: all" || lower == "quit: all" {
                closeAllApps()
            } else if lower.hasPrefix("close ") || lower.hasPrefix("quit ") {
                let target = String(line.dropFirst(lower.hasPrefix("close ") ? 6 : 5)).trimmingCharacters(in: .whitespaces)
                closeApp(target: target)
            } else if line.hasPrefix("http://") || line.hasPrefix("https://") {
                if let err = openURL(string: line) { errors.append(err) }
            } else if line.hasPrefix("$ ") || line.hasPrefix("shell: ") {
                let cmd = line.hasPrefix("$ ") ? String(line.dropFirst(2)) : String(line.dropFirst(7))
                if let err = runShell(command: cmd) { errors.append(err) }
            } else if line.hasPrefix("/") || line.hasPrefix("~") {
                if line.hasSuffix(".app") {
                    if let err = openApp(target: line) { errors.append(err) }
                } else {
                    if let err = openFile(path: line) { errors.append(err) }
                }
            } else {
                // Application name or bundle identifier
                if let err = openApp(target: line) { errors.append(err) }
            }
        }

        return errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    private func openApp(target: String) -> String? {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "No app specified" }

        // 1. Try bundle ID
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config)
            return nil
        }

        // 2. Try common Application directories by name
        let candidateNames: [String] = trimmed.hasSuffix(".app") ? [trimmed] : [trimmed, "\(trimmed).app"]
        let baseDirs = [
            "/Applications",
            NSString(string: "~/Applications").expandingTildeInPath,
            "/System/Applications",
            "/System/Applications/Utilities"
        ]

        for base in baseDirs {
            for name in candidateNames {
                let fullPath = (base as NSString).appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: fullPath) {
                    let url = URL(fileURLWithPath: fullPath)
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = true
                    NSWorkspace.shared.openApplication(at: url, configuration: config)
                    return nil
                }
            }
        }

        // 3. Fallback: treat as direct file path
        let directUrl = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        if FileManager.default.fileExists(atPath: directUrl.path) {
            NSWorkspace.shared.open(directUrl)
            return nil
        }

        // 4. Try macOS open -a
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-a", trimmed]
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                return nil
            }
        } catch {}

        return "App not found: \(trimmed)"
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

    private func closeAllApps() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let currentBundle = Bundle.main.bundleIdentifier ?? "com.clippy.app"
        let ignoredBundleIDs: Set<String> = [
            "com.apple.finder",
            currentBundle
        ]

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  app.processIdentifier != currentPID else {
                continue
            }
            if let bundleID = app.bundleIdentifier, ignoredBundleIDs.contains(bundleID) {
                continue
            }
            app.terminate()
        }
    }

    private func closeApp(target: String) {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let lower = trimmed.lowercased().replacingOccurrences(of: ".app", with: "")

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular else { continue }
            if let name = app.localizedName?.lowercased(), name == lower {
                app.terminate()
            } else if let bundleID = app.bundleIdentifier?.lowercased(), bundleID == lower {
                app.terminate()
            }
        }
    }
}
