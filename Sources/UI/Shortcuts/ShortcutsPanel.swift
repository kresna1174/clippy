// Sources/UI/Shortcuts/ShortcutsPanel.swift
import SwiftUI

// MARK: - ViewModel

class ShortcutsViewModel: ObservableObject {
    @Published var shortcuts: [ShortcutItem] = []
    let store: ShortcutStore

    /// Called after any mutation so the caller can re-register global hotkeys.
    var onReloadHotkeys: (([ShortcutItem]) -> Void)?

    init(store: ShortcutStore) {
        self.store = store
        reload()
    }

    func reload() {
        shortcuts = (try? store.fetchAll()) ?? []
    }

    func save(_ item: ShortcutItem) {
        try? store.save(item)
        reload()
        onReloadHotkeys?(shortcuts)
    }

    func delete(id: String) {
        try? store.delete(id: id)
        reload()
        onReloadHotkeys?(shortcuts)
    }
}

// MARK: - Window Holder Helper

struct ShortcutFormWindowHolder {
    static var window: NSWindow?
    static func close() {
        window?.close()
        window = nil
    }
}

// MARK: - ShortcutsPanel

struct ShortcutsPanel: View {
    @ObservedObject var viewModel: ShortcutsViewModel
    @Binding var searchQuery: String
    let onRun: (ShortcutItem) -> Void

    @State private var runError: String? = nil
    @State private var showError = false

    // MARK: - Filtering

    private var displayed: [ShortcutItem] {
        guard !searchQuery.isEmpty else { return viewModel.shortcuts }
        return viewModel.shortcuts.filter {
            $0.name.localizedCaseInsensitiveContains(searchQuery) ||
            $0.actionType.displayName.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.shortcuts.isEmpty {
                emptyState
            } else {
                shortcutsList
            }

            Divider().opacity(0.4)

            // ── Footer: Add button ──
            Button(action: { showAddEditWindow(item: nil) }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                    Text("Add Shortcut")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.accentColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        // ── Run error alert ──
        .alert("Error running shortcut", isPresented: $showError, presenting: runError) { _ in
            Button("OK") {}
        } message: { msg in
            Text(msg)
        }
    }

    // MARK: - Subviews

    private var shortcutsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(displayed) { item in
                    ShortcutRow(
                        item: item,
                        onRun: { runItem($0) },
                        onEdit: { showAddEditWindow(item: $0) },
                        onDelete: { viewModel.delete(id: $0.id) }
                    )
                    Divider().opacity(0.25)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bolt.circle")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No shortcuts yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            Text("Add shortcuts to quickly open apps,\nrun commands, or trigger system actions.")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
            Button(action: { showAddEditWindow(item: nil) }) {
                Label("Add Shortcut", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Window Management Helper

    private func showAddEditWindow(item: ShortcutItem? = nil) {
        ShortcutFormWindowHolder.close()
        
        let view = AddShortcutView(
            item: item,
            onSave: { updatedItem in
                viewModel.save(updatedItem)
                ShortcutFormWindowHolder.close()
            },
            onCancel: {
                ShortcutFormWindowHolder.close()
            }
        )
        
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = item == nil ? "Add Shortcut" : "Edit Shortcut"
        w.contentView = NSHostingView(rootView: view)
        w.center()
        w.level = .floating
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        ShortcutFormWindowHolder.window = w
    }

    // MARK: - Actions

    private func runItem(_ item: ShortcutItem) {
        ShortcutRunner.shared.run(item) { error in
            if let error {
                runError = error
                showError = true
            }
        }
        onRun(item)
    }
}
