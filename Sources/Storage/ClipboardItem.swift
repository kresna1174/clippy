import Foundation
import GRDB

enum ClipboardItemType: String, Codable, DatabaseValueConvertible {
    case text, image, file
}

struct ClipboardItem: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "items"
    var id: String
    var type: ClipboardItemType
    var content: Data
    var preview: String
    var createdAt: Int   // Unix timestamp seconds
    var sizeBytes: Int

    init(type: ClipboardItemType, content: Data, preview: String) {
        self.id = UUID().uuidString
        self.type = type
        self.content = content
        self.preview = preview
        self.createdAt = Int(Date().timeIntervalSince1970)
        self.sizeBytes = content.count
    }
}
