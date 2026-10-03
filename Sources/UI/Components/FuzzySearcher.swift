import Foundation
import Fuse

class FuzzySearcher {
    // Configured Fuse with large distance and appropriate threshold for typo tolerance
    private let fuse = Fuse(distance: 1000, threshold: 0.35)

    private struct ScoredItem {
        let item: ClipboardItemSummary
        let score: Double
    }

    func search(query: String, in items: [ClipboardItemSummary]) -> [ClipboardItemSummary] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }

        let qLower = q.lowercased()
        let tokens = qLower.split(separator: " ").map(String.init)

        var scored: [ScoredItem] = []

        for item in items {
            let textLower = item.preview.lowercased()

            // 1. Exact full match
            if textLower == qLower {
                scored.append(ScoredItem(item: item, score: 0.0))
                continue
            }

            // 2. Prefix match
            if textLower.hasPrefix(qLower) {
                scored.append(ScoredItem(item: item, score: 0.05))
                continue
            }

            // 3. Substring match (with word-boundary bonus and earlier position preference)
            if let range = textLower.range(of: qLower) {
                let pos = textLower.distance(from: textLower.startIndex, to: range.lowerBound)
                let isWordBoundary = range.lowerBound == textLower.startIndex ||
                    !textLower[textLower.index(before: range.lowerBound)].isLetter
                let baseScore = isWordBoundary ? 0.10 : 0.20
                let positionPenalty = Double(pos) * 0.0001
                scored.append(ScoredItem(item: item, score: baseScore + positionPenalty))
                continue
            }

            // 4. Multi-token match (all words present anywhere in text)
            if tokens.count > 1 {
                let allMatch = tokens.allSatisfy { textLower.contains($0) }
                if allMatch {
                    scored.append(ScoredItem(item: item, score: 0.30))
                    continue
                }
            }

            // 5. Fuzzy match fallback for typos (queries <= 32 chars supported by Fuse)
            if q.count <= 32 {
                if let result = fuse.search(q, in: item.preview) {
                    scored.append(ScoredItem(item: item, score: 0.50 + result.score * 0.4))
                }
            }
        }

        return scored
            .sorted { $0.score < $1.score }
            .map { $0.item }
    }
}

