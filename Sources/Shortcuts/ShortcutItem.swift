// Sources/Shortcuts/ShortcutItem.swift
import Foundation
import GRDB

enum ActionType: String, CaseIterable, Codable {
    case openApp
    case openURL
    case openFile
    case shell
    case systemLock   // lock screen
    case systemEmptyTrash

    var displayName: String {
        switch self {
        case .openApp: return "Open App"
        case .openURL: return "Open URL"
        case .openFile: return "Open File / Folder"
        case .shell: return "Shell Command"
        case .systemLock: return "Lock Screen"
        case .systemEmptyTrash: return "Empty Trash"
        }
    }

    var sfSymbol: String {
        switch self {
        case .openApp: return "app.badge"
        case .openURL: return "link"
        case .openFile: return "folder"
        case .shell: return "terminal"
        case .systemLock: return "lock.fill"
        case .systemEmptyTrash: return "trash"
        }
    }
}

struct ShortcutItem: Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var actionType: ActionType
    var actionPayload: String   // bundle ID / URL string / shell command / empty for system
    var hotkeyKeyCode: Int?     // CGKeyCode value, nil = no hotkey
    var hotkeyKeyChar: String?  // Display character e.g. "V", "F2"
    var hotkeyModifiers: Int    // NSEvent.ModifierFlags raw value
    var sortOrder: Int
    var isEnabled: Bool = true

    /// SF Symbol for this shortcut's action type
    var sfSymbol: String { actionType.sfSymbol }
}

extension ShortcutItem: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "shortcuts" }

    enum Columns {
        static let id = Column("id")
        static let name = Column("name")
        static let actionType = Column("actionType")
        static let actionPayload = Column("actionPayload")
        static let hotkeyKeyCode = Column("hotkeyKeyCode")
        static let hotkeyKeyChar = Column("hotkeyKeyChar")
        static let hotkeyModifiers = Column("hotkeyModifiers")
        static let sortOrder = Column("sortOrder")
        static let isEnabled = Column("isEnabled")
    }

    init(row: Row) {
        id = row[Columns.id]
        name = row[Columns.name]
        actionType = ActionType(rawValue: row[Columns.actionType]) ?? .openApp
        actionPayload = row[Columns.actionPayload]
        hotkeyKeyCode = row[Columns.hotkeyKeyCode]
        hotkeyKeyChar = row[Columns.hotkeyKeyChar]
        hotkeyModifiers = row[Columns.hotkeyModifiers]
        sortOrder = row[Columns.sortOrder]
        isEnabled = row[Columns.isEnabled]
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.name] = name
        container[Columns.actionType] = actionType.rawValue
        container[Columns.actionPayload] = actionPayload
        container[Columns.hotkeyKeyCode] = hotkeyKeyCode
        container[Columns.hotkeyKeyChar] = hotkeyKeyChar
        container[Columns.hotkeyModifiers] = hotkeyModifiers
        container[Columns.sortOrder] = sortOrder
        container[Columns.isEnabled] = isEnabled
    }
}
