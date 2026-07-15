// Sources/UI/Panel/PanelCoordinator.swift
import Foundation
import Combine

class PanelCoordinator {
    private let store: ClipboardStore
    private let prefs: AppPreferences
    private let shortcutsViewModel: ShortcutsViewModel

    private var notchController: NotchPanelController?
    private var floatingController: FloatingPanelController?
    private var prefsCancellable: AnyCancellable?

    var onShowSettings: (() -> Void)? {
        didSet {
            notchController?.onShowSettings = onShowSettings
            floatingController?.onShowSettings = onShowSettings
        }
    }

    init(store: ClipboardStore, prefs: AppPreferences, shortcutsViewModel: ShortcutsViewModel) {
        self.store = store
        self.prefs = prefs
        self.shortcutsViewModel = shortcutsViewModel
        prefsCancellable = prefs.$panelMode.sink { [weak self] _ in
            self?.hideAll()
        }
    }

    func toggle() {
        switch prefs.panelMode {
        case .notch:
            floatingController?.hide()
            floatingController = nil
            if notchController == nil {
                let c = NotchPanelController(store: store, shortcutsViewModel: shortcutsViewModel)
                c.onShowSettings = onShowSettings
                notchController = c
            }
            notchController?.toggle()
        case .cursorFollow:
            notchController?.hide()
            notchController = nil
            if floatingController == nil {
                let c = FloatingPanelController(store: store, shortcutsViewModel: shortcutsViewModel)
                c.onShowSettings = onShowSettings
                floatingController = c
            }
            floatingController?.toggle()
        }
    }

    func hide() { hideAll() }

    private func hideAll() {
        notchController?.hide()
        floatingController?.hide()
    }
}
