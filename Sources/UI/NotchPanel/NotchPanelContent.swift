// Sources/UI/NotchPanel/NotchPanelContent.swift
import SwiftUI

// MARK: - Panel Tab

enum PanelTab {
    case clipboard
    case shortcuts
}

// MARK: - PanelViewModel

class PanelViewModel: ObservableObject {
    @Published var items: [ClipboardItem] = []
    let store: ClipboardStore

    init(store: ClipboardStore) { self.store = store }

    func reload() { items = (try? store.fetchAll()) ?? [] }
}

// MARK: - NotchPanelContent

struct NotchPanelContent: View {
    @ObservedObject var viewModel: PanelViewModel
    @ObservedObject var shortcutsViewModel: ShortcutsViewModel
    let onSelect: (ClipboardItem, Bool) -> Void
    let onPin: (ClipboardItem) -> Void
    let onSettings: () -> Void
    let onRunShortcut: (ShortcutItem) -> Void
    var isFloating: Bool = false

    @State private var searchQuery = ""
    @State private var isVisible = false
    @State private var selectedIndex: Int? = nil
    @State private var activeTab: PanelTab = .clipboard
    @FocusState private var searchFocused: Bool

    private let searcher = FuzzySearcher()

    private var displayedItems: [ClipboardItem] {
        searcher.search(query: searchQuery, in: viewModel.items)
    }

    private var notchHeight: CGFloat { NSScreen.main?.safeAreaInsets.top ?? 26 }
    private let shadowPad: CGFloat = NotchWindow.shadowPad

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if !isFloating {
                Color.clear.frame(height: notchHeight)
            }

            VStack(spacing: 0) {
                // ── Header ──
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        // Tab switcher pills
                        HStack(spacing: 2) {
                            tabButton(title: "Clipboard", icon: "doc.on.clipboard", tab: .clipboard)
                            tabButton(title: "Shortcuts", icon: "bolt.fill",        tab: .shortcuts)
                        }
                        .padding(3)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        Spacer()

                        // Settings gear
                        Button(action: onSettings) {
                            Image(systemName: "gear")
                                .foregroundColor(.secondary)
                                .font(.system(size: 13))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                    // Search bar (shared, label adapts to active tab)
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                        TextField(
                            activeTab == .clipboard ? "Search clipboard…" : "Search shortcuts…",
                            text: $searchQuery
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($searchFocused)

                        if activeTab == .clipboard {
                            Text("\(viewModel.items.count) items")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }

                Divider().opacity(0.4)

                // ── Content area ──
                if activeTab == .clipboard {
                    clipboardContent
                } else {
                    shortcutsContent
                }
            }
            .background(VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow))
            .clipShape(
                isFloating
                    ? AnyShape(RoundedRectangle(cornerRadius: 20))
                    : AnyShape(UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 20,
                        bottomTrailingRadius: 20,
                        topTrailingRadius: 0
                      ))
            )
            .overlay(
                Group {
                    if isFloating {
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    } else {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 20,
                            bottomTrailingRadius: 20,
                            topTrailingRadius: 0
                        )
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    }
                }
            )
            .padding(.horizontal, shadowPad)
            .padding(.bottom, shadowPad)
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.96, anchor: .top)
        }
        .focusable()
        .onKeyPress(phases: .down) { press in
            handleKeyPress(press)
        }
        .onAppear {
            viewModel.reload()
            shortcutsViewModel.reload()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { isVisible = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { searchFocused = true }
        }
        .onDisappear { isVisible = false }
        .onChange(of: searchQuery) { _ in selectedIndex = nil }
        .onChange(of: viewModel.items.map(\.id)) { _ in selectedIndex = nil }
        .onChange(of: activeTab) { _ in
            searchQuery = ""
            selectedIndex = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { searchFocused = true }
        }
    }

    // MARK: - Tab Button

    @ViewBuilder
    private func tabButton(title: String, icon: String, tab: PanelTab) -> some View {
        let isActive = activeTab == tab
        Button(action: {
            withAnimation(.easeInOut(duration: 0.18)) { activeTab = tab }
        }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isActive ? Color.white.opacity(0.15) : Color.clear)
            .foregroundColor(isActive ? .primary : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Clipboard Tab

    @ViewBuilder
    private var clipboardContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(displayedItems.enumerated()), id: \.element.id) { idx, item in
                        ClipboardItemRow(
                            item: item,
                            isSelected: selectedIndex == idx,
                            onSelect: onSelect,
                            onPin: onPin
                        )
                        .id(idx)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                        Divider().opacity(0.25)
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: displayedItems.map(\.id))
            }
            .onChange(of: selectedIndex) { idx in
                if let idx { withAnimation { proxy.scrollTo(idx, anchor: .center) } }
            }
        }
    }

    // MARK: - Shortcuts Tab

    @ViewBuilder
    private var shortcutsContent: some View {
        ShortcutsPanel(
            viewModel: shortcutsViewModel,
            searchQuery: $searchQuery,
            onRun: onRunShortcut
        )
    }

    // MARK: - Keyboard handling

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        // Keyboard nav is only active on the clipboard tab
        guard activeTab == .clipboard else { return .ignored }
        let count = displayedItems.count
        switch press.key {
        case .downArrow:
            guard count > 0 else { return .handled }
            searchFocused = false
            selectedIndex = min((selectedIndex ?? -1) + 1, count - 1)
            return .handled
        case .upArrow:
            searchFocused = false
            let next = (selectedIndex ?? count) - 1
            if next < 0 { selectedIndex = nil; searchFocused = true }
            else { selectedIndex = next }
            return .handled
        case .return:
            guard let idx = selectedIndex, idx < count else { return .ignored }
            let item = displayedItems[idx]
            let paste = !press.modifiers.contains(.command)
            onSelect(item, paste)
            return .handled
        case .tab:
            searchFocused.toggle()
            return .handled
        default:
            // Printable char while list is focused → redirect to search
            if !searchFocused && !press.characters.isEmpty &&
               press.characters.allSatisfy({ $0.isLetter || $0.isNumber || $0.isPunctuation || $0 == " " }) {
                searchFocused = true
                searchQuery += press.characters
                return .handled
            }
            return .ignored
        }
    }
}
