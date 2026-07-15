// Sources/Shortcuts/ShortcutStore.swift
import Foundation
import GRDB

class ShortcutStore {
    private let db: DatabaseQueue

    init(db: DatabaseQueue) throws {
        self.db = db
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v3_shortcuts") { db in
            try db.create(table: "shortcuts", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("actionType", .text).notNull()
                t.column("actionPayload", .text).notNull().defaults(to: "")
                t.column("hotkeyKeyCode", .integer)
                t.column("hotkeyKeyChar", .text)
                t.column("hotkeyModifiers", .integer).notNull().defaults(to: 0)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("isEnabled", .boolean).notNull().defaults(to: true)
            }
        }
        try migrator.migrate(db)
    }

    func fetchAll() throws -> [ShortcutItem] {
        try db.read { db in
            try ShortcutItem.order(ShortcutItem.Columns.sortOrder.asc).fetchAll(db)
        }
    }

    func save(_ item: ShortcutItem) throws {
        try db.write { db in
            try item.save(db)
        }
    }

    func delete(id: String) throws {
        try db.write { db in
            try ShortcutItem.deleteOne(db, key: id)
        }
    }

    func updateOrder(_ items: [ShortcutItem]) throws {
        try db.write { db in
            for (idx, var item) in items.enumerated() {
                item.sortOrder = idx
                try item.update(db)
            }
        }
    }
}
