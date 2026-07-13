import Fuse

class FuzzySearcher {
    private let fuse = Fuse()

    func search(query: String, in items: [ClipboardItem]) -> [ClipboardItem] {
        guard !query.isEmpty else { return items }
        let results = fuse.search(query, in: items.map { $0.preview })
        return results
            .sorted { $0.score < $1.score }
            .map { items[$0.index] }
    }
}
