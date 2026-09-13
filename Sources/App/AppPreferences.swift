// Sources/App/AppPreferences.swift
import Foundation
import Combine

enum PanelMode: String, CaseIterable {
    case notch
    case cursorFollow
}

class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    @Published var panelMode: PanelMode {
        didSet { UserDefaults.standard.set(panelMode.rawValue, forKey: "panelMode") }
    }

    /// Keep the Mac from idle-sleeping while Clippy runs. Off by default —
    /// this only takes effect once the user opts in from Settings.
    @Published var preventSleep: Bool {
        didSet {
            UserDefaults.standard.set(preventSleep, forKey: "preventSleep")
            if preventSleep {
                PowerAssertionManager.shared.start()
            } else {
                PowerAssertionManager.shared.stop()
            }
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: "panelMode") ?? ""
        panelMode = PanelMode(rawValue: raw) ?? .notch

        preventSleep = UserDefaults.standard.bool(forKey: "preventSleep")
        if preventSleep {
            PowerAssertionManager.shared.start()
        }
    }
}
