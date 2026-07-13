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

    var body: some View {
        VStack(spacing: 0) {
            // notch-height spacer — top stays black to match notch hardware
            Color.black.frame(height: 26)

            VStack(spacing: 0) {
                // search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                        .font(.system(size: 12))
                    TextField("Search...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: onSettings) {
                        Image(systemName: "gear")
                            .foregroundColor(.gray)
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider().background(Color.gray.opacity(0.3))

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(displayedItems, id: \.id) { item in
                            ClipboardItemRow(item: item, onSelect: onSelect)
                            Divider().background(Color.gray.opacity(0.2))
                        }
                    }
                }
            }
            .background(Color(white: 0.1))
            .cornerRadius(12)
        }
        .background(Color.black)
        .onAppear { viewModel.reload() }
    }
}
