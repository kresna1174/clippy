// Sources/App/AppDelegate.swift
import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: ClipboardStore!
    private var monitor: ClipboardMonitor!
    private var hotkey: HotkeyManager!
    private var coordinator: PanelCoordinator!
    private var menuBar: MenuBarController!
    private var settingsWindow: NSWindow?
    private let prefs = AppPreferences.shared

    @AppStorage("sizeLimitMB") private var sizeLimitMB: Double = 10

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.clipboardmanager.app")
            .filter { $0 != NSRunningApplication.current }
            .forEach { $0.terminate() }

        NSApp.setActivationPolicy(.accessory)

        do {
            store = try ClipboardStore(sizeLimitBytes: Int64(sizeLimitMB * 1_000_000))
        } catch {
            fatalError("Cannot open database: \(error)")
        }

        monitor = ClipboardMonitor(store: store)
        monitor.onNewItem = { _ in }
        monitor.start()

        coordinator = PanelCoordinator(store: store, prefs: prefs)
        coordinator.onShowSettings = { [weak self] in self?.showSettings() }

        hotkey = HotkeyManager()
        hotkey.register { [weak self] in
            DispatchQueue.main.async { self?.coordinator.toggle() }
        }

        menuBar = MenuBarController()
        menuBar.start { [weak self] in
            DispatchQueue.main.async { self?.coordinator.toggle() }
        }
    }

    private func showSettings() {
        if settingsWindow == nil {
            let sizeLimitBinding = Binding<Double>(
                get: { self.sizeLimitMB },
                set: { self.sizeLimitMB = $0 }
            )
            let view = SettingsView(
                store: store,
                prefs: prefs,
                sizeLimitMB: sizeLimitBinding,
                onDismiss: { [weak self] in self?.settingsWindow?.close() }
            )
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 340),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "ClipboardManager Settings"
            w.contentView = NSHostingView(rootView: view)
            w.center()
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
