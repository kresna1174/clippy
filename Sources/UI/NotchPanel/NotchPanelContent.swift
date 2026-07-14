// Sources/UI/NotchPanel/NotchPanelContent.swift
import SwiftUI

class PanelViewModel: ObservableObject {
    @Published var items: [ClipboardItem] = []
    let store: ClipboardStore

    init(store: ClipboardStore) {
        self.store = store
    }

    func reload() {
        items = (try? store.fetchAll()) ?? []
    }
}

struct NotchPanelContent: View {
    @ObservedObject var viewModel: PanelViewModel
    let onSelect: (ClipboardItem, Bool) -> Void
    let onSettings: () -> Void

    @State private var searchQuery = ""
    private let searcher = FuzzySearcher()

    private var displayedItems: [ClipboardItem] {
        searcher.search(query: searchQuery, in: viewModel.items)
    }

    private var notchHeight: CGFloat {
        NSScreen.main?.safeAreaInsets.top ?? 26
    }

    private let shadowPad: CGFloat = NotchWindow.shadowPad

    var body: some View {
        // outer padding matches window's shadowPad so content stays centered
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)

            VStack(spacing: 0) {
                // search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    TextField("Search...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    Spacer()
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

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(displayedItems, id: \.id) { item in
                            ClipboardItemRow(item: item, onSelect: onSelect)
                            Divider().opacity(0.25)
                        }
                    }
                }
            }
            .background(
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
            )
            // top corners square (flush to notch), bottom corners rounded
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 20,
                    bottomTrailingRadius: 20,
                    topTrailingRadius: 0
                )
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 20,
                    bottomTrailingRadius: 20,
                    topTrailingRadius: 0
                )
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 12)
            .padding(.horizontal, shadowPad)
            .padding(.bottom, shadowPad)
        }
        .onAppear { viewModel.reload() }
    }
}
