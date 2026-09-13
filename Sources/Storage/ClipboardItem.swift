import Foundation
import GRDB

enum ClipboardItemType: String, Codable, DatabaseValueConvertible {
    case text, image, file
}

/// Full record, including the (potentially large) raw content blob.
/// Only load this when you actually need the payload (insert, paste).
struct ClipboardItem: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "items"
    var id: String
    var type: ClipboardItemType
    var content: Data
    var preview: String
    var thumbnail: Data?
    var createdAt: Int
    var sizeBytes: Int
    var isPinned: Bool

    init(type: ClipboardItemType, content: Data, preview: String, thumbnail: Data? = nil) {
        self.id = UUID().uuidString
        self.type = type
        self.content = content
        self.preview = preview
        self.thumbnail = thumbnail
        self.createdAt = Int(Date().timeIntervalSince1970)
        self.sizeBytes = content.count
        self.isPinned = false
    }
}

/// Lightweight projection used for list/search UI — deliberately excludes
/// `content` so browsing history never pulls full-size blobs (e.g. large
/// images) into memory. Fetch the full `ClipboardItem`/content by id only
/// when the item is actually pasted.
struct ClipboardItemSummary: Codable, FetchableRecord, TableRecord, Identifiable {
    static let databaseTableName = "items"

    // Restrict every query built from this type to these columns — `content`
    // is deliberately left out so it's never read off disk for a list/search.
    static var databaseSelection: [any SQLSelectable] {
        [Column("id"), Column("type"), Column("preview"), Column("thumbnail"),
         Column("createdAt"), Column("sizeBytes"), Column("isPinned")]
    }

    var id: String
    var type: ClipboardItemType
    var preview: String
    var thumbnail: Data?
    var createdAt: Int
    var sizeBytes: Int
    var isPinned: Bool
}
