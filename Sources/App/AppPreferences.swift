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

    private init() {
        let raw = UserDefaults.standard.string(forKey: "panelMode") ?? ""
        panelMode = PanelMode(rawValue: raw) ?? .notch
    }
}
