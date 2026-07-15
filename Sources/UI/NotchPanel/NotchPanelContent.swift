// Sources/UI/NotchPanel/NotchPanelContent.swift
import SwiftUI

class PanelViewModel: ObservableObject {
    @Published var items: [ClipboardItem] = []
    let store: ClipboardStore

    init(store: ClipboardStore) { self.store = store }

    func reload() { items = (try? store.fetchAll()) ?? [] }
}

struct NotchPanelContent: View {
    @ObservedObject var viewModel: PanelViewModel
    let onSelect: (ClipboardItem, Bool) -> Void
    let onPin: (ClipboardItem) -> Void
    let onSettings: () -> Void

    @State private var searchQuery = ""
    @State private var isVisible = false
    @State private var selectedIndex: Int? = nil
    @FocusState private var searchFocused: Bool

    private let searcher = FuzzySearcher()

    private var displayedItems: [ClipboardItem] {
        searcher.search(query: searchQuery, in: viewModel.items)
    }

    private var notchHeight: CGFloat { NSScreen.main?.safeAreaInsets.top ?? 26 }
    private let shadowPad: CGFloat = NotchWindow.shadowPad

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)

            VStack(spacing: 0) {
                // header
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    TextField("Search...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($searchFocused)
                    Spacer()
                    Text("\(viewModel.items.count) items")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Button(action: onSettings) {
                        Image(systemName: "gear")
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider().opacity(0.4)

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
            .background(VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow))
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0, bottomLeadingRadius: 20,
                    bottomTrailingRadius: 20, topTrailingRadius: 0
                )
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0, bottomLeadingRadius: 20,
                    bottomTrailingRadius: 20, topTrailingRadius: 0
                )
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
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
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { isVisible = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { searchFocused = true }
        }
        .onDisappear { isVisible = false }
        .onChange(of: searchQuery) { _ in selectedIndex = nil }
    }

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
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
            let paste = press.modifiers.contains(.command) ? false : true
            onSelect(item, paste)
            return .handled
        case .tab:
            searchFocused.toggle()
            return .handled
        default:
            // printable char while list focused → redirect to search
            if !searchFocused && !press.characters.isEmpty && press.characters.allSatisfy({ $0.isLetter || $0.isNumber || $0.isPunctuation || $0 == " " }) {
                searchFocused = true
                searchQuery += press.characters
                return .handled
            }
            return .ignored
        }
    }
}
