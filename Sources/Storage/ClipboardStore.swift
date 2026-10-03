import Foundation
import GRDB

class ClipboardStore {
    let db: DatabaseQueue
    private let sizeLimitBytes: Int64
    var maxItems: Int {
        didSet { try? pruneIfNeeded() }
    }

    init(maxItems: Int = 50, sizeLimitBytes: Int64 = 500_000_000) throws {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("Clippy")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("history.db")
        db = try DatabaseQueue(path: dbURL.path)
        self.maxItems = maxItems
        self.sizeLimitBytes = sizeLimitBytes
        try migrate()
        try pruneIfNeeded()
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
        migrator.registerMigration("v2") { db in
            try db.alter(table: "items") { t in
                t.add(column: "isPinned", .boolean).notNull().defaults(to: false)
            }
        }
        migrator.registerMigration("v3") { db in
            try db.alter(table: "items") { t in
                t.add(column: "thumbnail", .blob)
            }
        }
        try migrator.migrate(db)
    }

    /// Record a freshly-copied clip. If an item with identical type+content
    /// already exists, it's moved to the top in place (preserving its id and
    /// pin state) instead of being deleted and re-inserted — one write
    /// instead of two, and pinned items no longer lose their pin when the
    /// same content is copied again.
    func recordNewClip(_ item: ClipboardItem) throws {
        try db.write { db in
            let existingID = try String.fetchOne(
                db,
                sql: "SELECT id FROM items WHERE type = ? AND content = ? LIMIT 1",
                arguments: [item.type.rawValue, item.content]
            )
            if let existingID {
                try db.execute(
                    sql: "UPDATE items SET createdAt = ?, preview = ?, thumbnail = ? WHERE id = ?",
                    arguments: [item.createdAt, item.preview, item.thumbnail, existingID]
                )
            } else {
                try item.insert(db)
            }
        }
        try pruneIfNeeded()
    }

    /// List/search projection — never touches the `content` column, so
    /// browsing history doesn't load large image/file blobs into memory.
    func fetchAllSummaries() throws -> [ClipboardItemSummary] {
        try db.read { db in
            try ClipboardItemSummary
                .order(Column("isPinned").desc, Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    /// Fetch the full payload for one item, e.g. right before writing it to
    /// the pasteboard. Kept separate from the summary so it's only paid for
    /// when actually needed.
    func fetchContent(id: String) throws -> Data? {
        try db.read { db in
            try Data.fetchOne(db, sql: "SELECT content FROM items WHERE id = ?", arguments: [id])
        }
    }

    func togglePin(id: String) throws {
        try db.write { db in
            try db.execute(sql: "UPDATE items SET isPinned = NOT isPinned WHERE id = ?", arguments: [id])
        }
    }

    func totalSizeBytes() throws -> Int64 {
        try db.read { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(sizeBytes), 0) FROM items") ?? 0
        }
    }

    func delete(id: String) throws {
        _ = try db.write { db in try ClipboardItem.deleteOne(db, key: id) }
    }

    func clearUnpinned() throws {
        _ = try db.write { db in
            try db.execute(sql: "DELETE FROM items WHERE isPinned = 0")
        }
    }

    func clearAll() throws {
        _ = try db.write { db in try ClipboardItem.deleteAll(db) }
    }

    private func pruneIfNeeded() throws {
        try db.write { db in
            // 1. Prune by item count limit: keep newest maxItems unpinned items, preserve all pinned items
            if self.maxItems > 0 {
                try db.execute(
                    sql: """
                    DELETE FROM items 
                    WHERE isPinned = 0 
                      AND id NOT IN (
                          SELECT id FROM items 
                          WHERE isPinned = 0 
                          ORDER BY createdAt DESC 
                          LIMIT ?
                      )
                    """,
                    arguments: [self.maxItems]
                )
            }

            // 2. Prune by size limit if still exceeding
            let totalSize = try Int64.fetchOne(
                db, sql: "SELECT COALESCE(SUM(sizeBytes), 0) FROM items"
            ) ?? 0
            guard totalSize > sizeLimitBytes else { return }
            var excess = totalSize - sizeLimitBytes

            // Stream id+sizeBytes only (no content blobs) and stop as soon as
            // enough space is freed, instead of loading every non-pinned
            // record (content included) into memory up front.
            let rows = try Row.fetchCursor(
                db, sql: "SELECT id, sizeBytes FROM items WHERE isPinned = 0 ORDER BY createdAt ASC"
            )
            while excess > 0, let row = try rows.next() {
                let id: String = row["id"]
                let size: Int64 = row["sizeBytes"]
                try db.execute(sql: "DELETE FROM items WHERE id = ?", arguments: [id])
                excess -= size
            }
        }
    }
}
