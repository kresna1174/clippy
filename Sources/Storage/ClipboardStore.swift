import Foundation
import GRDB

class ClipboardStore {
    private let db: DatabaseQueue
    private let sizeLimitBytes: Int64

    init(sizeLimitBytes: Int64 = 500_000_000) throws {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("ClipboardManager")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("history.db")
        db = try DatabaseQueue(path: dbURL.path)
        self.sizeLimitBytes = sizeLimitBytes
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "items") { t in
                t.column("id", .text).primaryKey()
                t.column("type", .text).notNull()
                t.column("content", .blob).notNull()
                t.column("preview", .text).notNull()
                t.column("createdAt", .integer).notNull()
                t.column("sizeBytes", .integer).notNull()
            }
        }
        try migrator.migrate(db)
    }

    func insert(_ item: ClipboardItem) throws {
        try db.write { db in try item.insert(db) }
        try pruneIfNeeded()
    }

    func fetchAll() throws -> [ClipboardItem] {
        try db.read { db in
            try ClipboardItem.order(Column("createdAt").desc).fetchAll(db)
        }
    }

    func exists(type: ClipboardItemType, content: Data) throws -> Bool {
        try db.read { db in
            try ClipboardItem
                .filter(Column("type") == type.rawValue && Column("content") == content)
                .fetchCount(db) > 0
        }
    }

    func fetchLatest() throws -> ClipboardItem? {
        try db.read { db in
            try ClipboardItem.order(Column("createdAt").desc).fetchOne(db)
        }
    }

    func delete(id: String) throws {
        try db.write { db in try ClipboardItem.deleteOne(db, key: id) }
    }

    func clearAll() throws {
        try db.write { db in try ClipboardItem.deleteAll(db) }
    }

    private func pruneIfNeeded() throws {
        try db.write { db in
            let totalSize = try Int64.fetchOne(
                db, sql: "SELECT COALESCE(SUM(sizeBytes), 0) FROM items"
            ) ?? 0
            guard totalSize > sizeLimitBytes else { return }
            let excess = totalSize - sizeLimitBytes
            var freed: Int64 = 0
            let oldest = try ClipboardItem.order(Column("createdAt").asc).fetchAll(db)
            for item in oldest {
                try ClipboardItem.deleteOne(db, key: item.id)
                freed += Int64(item.sizeBytes)
                if freed >= excess { break }
            }
        }
    }
}
