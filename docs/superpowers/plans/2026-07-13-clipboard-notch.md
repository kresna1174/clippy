# ClipboardManager — Notch Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS clipboard manager that displays history in a Dynamic Island-style panel expanding from the MacBook notch.

**Architecture:** A Swift Package Manager app with no Xcode project. Five independent modules (Monitor, Storage, Keyboard, UI, App) communicate through thin protocols. The NotchPanel is a borderless NSWindow that sits over the hardware notch and animates to expand when triggered.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit, SPM, GRDB.swift, HotKey, fuse-swift.

## Global Constraints

- macOS 13.0+ minimum (safeAreaInsets notch API available since macOS 12, but 13 for SwiftUI improvements)
- SPM only — no `.xcodeproj`, no CocoaPods
- All UI on main thread; clipboard polling on background queue
- Target device: MacBook 14" (notch ~162pt wide, ~26pt tall)
- DB at `~/Library/Application Support/ClipboardManager/history.db`
- Default storage cap: 500MB; per-image cap: 10MB
- Panel expanded size: 480pt wide, max 520pt tall

---

## File Map

```
ClipboardManager/
├── Package.swift
├── Sources/
│   ├── App/
│   │   ├── main.swift              ← NSApplication entry, runs app
│   │   └── AppDelegate.swift       ← wires Monitor, Storage, Keyboard, NotchPanel
│   ├── Monitor/
│   │   └── ClipboardMonitor.swift  ← NSPasteboard polling, emits ClipboardItem
│   ├── Storage/
│   │   ├── ClipboardItem.swift     ← model struct + GRDB record
│   │   └── ClipboardStore.swift    ← GRDB wrapper, CRUD, pruning
│   ├── Keyboard/
│   │   └── HotkeyManager.swift     ← HotKey wrapper, toggle callback
│   └── UI/
│       ├── NotchPanel/
│       │   ├── NotchWindow.swift       ← NSWindow subclass, geometry, animation
│       │   ├── NotchPanelController.swift ← show/hide/toggle logic
│       │   └── NotchPanelContent.swift ← SwiftUI root view (search + list)
│       ├── MenuBar/
│       │   └── MenuBarController.swift ← NSStatusItem (1px), mouse monitor
│       ├── Settings/
│       │   └── SettingsView.swift      ← SwiftUI settings panel
│       └── Components/
│           ├── ClipboardItemRow.swift  ← SwiftUI row for one item
│           └── FuzzySearcher.swift     ← fuse-swift wrapper
```

---

## Task 1: Package.swift + Project Scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/App/main.swift`

**Interfaces:**
- Produces: buildable SPM target `ClipboardManager`

- [ ] **Step 1: Write Package.swift**

```swift
// Package.swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipboardManager",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClipboardManager",
            path: "Sources",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "HotKey", package: "HotKey"),
                .product(name: "Fuse", package: "fuse-swift"),
            ]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0"),
        .package(url: "https://github.com/krisk/fuse-swift.git", from: "4.0.0"),
    ]
)
```

- [ ] **Step 2: Write minimal main.swift**

```swift
// Sources/App/main.swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 3: Create stub AppDelegate so it compiles**

```swift
// Sources/App/AppDelegate.swift
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
```

- [ ] **Step 4: Verify build**

```bash
cd /Users/krisna/Documents/PROJECT/ClipboardManager
swift build
```

Expected: `Build complete!` (may take a few minutes first run for package resolution)

- [ ] **Step 5: Commit**

```bash
git init
git add Package.swift Sources/App/main.swift Sources/App/AppDelegate.swift
git commit -m "feat: scaffold SPM project with dependencies"
```

---

## Task 2: Storage — ClipboardItem model + GRDB

**Files:**
- Create: `Sources/Storage/ClipboardItem.swift`
- Create: `Sources/Storage/ClipboardStore.swift`

**Interfaces:**
- Produces:
  - `struct ClipboardItem` with fields: `id: String`, `type: ClipboardItemType`, `content: Data`, `preview: String`, `createdAt: Int`, `sizeBytes: Int`
  - `enum ClipboardItemType: String` cases: `text`, `image`, `file`
  - `class ClipboardStore` with methods:
    - `init(sizeLimitBytes: Int64 = 500_000_000) throws`
    - `func insert(_ item: ClipboardItem) throws`
    - `func fetchAll() throws -> [ClipboardItem]`
    - `func fetchLatest() throws -> ClipboardItem?`
    - `func delete(id: String) throws`
    - `func clearAll() throws`

- [ ] **Step 1: Write ClipboardItem.swift**

```swift
// Sources/Storage/ClipboardItem.swift
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
```

- [ ] **Step 2: Write ClipboardStore.swift**

```swift
// Sources/Storage/ClipboardStore.swift
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
        try db.write { db in
            try item.insert(db)
        }
        try pruneIfNeeded()
    }

    func fetchAll() throws -> [ClipboardItem] {
        try db.read { db in
            try ClipboardItem.order(Column("createdAt").desc).fetchAll(db)
        }
    }

    func fetchLatest() throws -> ClipboardItem? {
        try db.read { db in
            try ClipboardItem.order(Column("createdAt").desc).fetchOne(db)
        }
    }

    func delete(id: String) throws {
        try db.write { db in
            try ClipboardItem.deleteOne(db, key: id)
        }
    }

    func clearAll() throws {
        try db.write { db in
            try ClipboardItem.deleteAll(db)
        }
    }

    private func pruneIfNeeded() throws {
        try db.write { db in
            let totalSize = try Int64.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(sizeBytes), 0) FROM items"
            ) ?? 0
            guard totalSize > sizeLimitBytes else { return }
            // delete oldest until under limit
            let excess = totalSize - sizeLimitBytes
            var freed: Int64 = 0
            let oldest = try ClipboardItem
                .order(Column("createdAt").asc)
                .fetchAll(db)
            for item in oldest {
                try ClipboardItem.deleteOne(db, key: item.id)
                freed += Int64(item.sizeBytes)
                if freed >= excess { break }
            }
        }
    }
}
```

- [ ] **Step 3: Verify build**

```bash
swift build
```

Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/Storage/
git commit -m "feat: add ClipboardItem model and ClipboardStore (GRDB)"
```

---

## Task 3: Monitor — Clipboard Polling

**Files:**
- Create: `Sources/Monitor/ClipboardMonitor.swift`

**Interfaces:**
- Consumes: `ClipboardItem`, `ClipboardItemType`, `ClipboardStore.fetchLatest()`
- Produces:
  - `class ClipboardMonitor`
    - `init(store: ClipboardStore)`
    - `func start()`
    - `func stop()`
    - `var onNewItem: ((ClipboardItem) -> Void)?`

- [ ] **Step 1: Write ClipboardMonitor.swift**

```swift
// Sources/Monitor/ClipboardMonitor.swift
import AppKit
import Foundation

class ClipboardMonitor {
    private let store: ClipboardStore
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private let queue = DispatchQueue(label: "com.clipboardmanager.monitor", qos: .utility)

    var onNewItem: ((ClipboardItem) -> Void)?

    init(store: ClipboardStore) {
        self.store = store
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(500))
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func poll() {
        let pb = NSPasteboard.general
        let count = pb.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        guard let item = parseItem(from: pb) else { return }

        // skip duplicate of latest
        if let latest = try? store.fetchLatest(),
           latest.type == item.type,
           latest.content == item.content { return }

        do {
            try store.insert(item)
            onNewItem?(item)
        } catch {
            print("[ClipboardMonitor] insert failed: \(error)")
        }
    }

    private func parseItem(from pb: NSPasteboard) -> ClipboardItem? {
        // text
        if let string = pb.string(forType: .string), !string.isEmpty {
            let preview = String(string.prefix(200))
            return ClipboardItem(
                type: .text,
                content: Data(string.utf8),
                preview: preview
            )
        }
        // file URL
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first {
            let path = url.path
            let preview = url.lastPathComponent
            return ClipboardItem(
                type: .file,
                content: Data(path.utf8),
                preview: preview
            )
        }
        // image
        if let image = NSImage(pasteboard: pb) {
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return nil }
            guard png.count <= 10_000_000 else {
                print("[ClipboardMonitor] image too large (\(png.count) bytes), skipping")
                return nil
            }
            return ClipboardItem(
                type: .image,
                content: png,
                preview: "Image \(png.count / 1024)KB"
            )
        }
        return nil
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/Monitor/
git commit -m "feat: add ClipboardMonitor with pasteboard polling"
```

---

## Task 4: Keyboard — HotKey Manager

**Files:**
- Create: `Sources/Keyboard/HotkeyManager.swift`

**Interfaces:**
- Produces:
  - `class HotkeyManager`
    - `init()`
    - `func register(onTrigger: @escaping () -> Void)`
    - `func unregister()`

- [ ] **Step 1: Write HotkeyManager.swift**

```swift
// Sources/Keyboard/HotkeyManager.swift
import HotKey
import Carbon

class HotkeyManager {
    private var hotKey: HotKey?

    func register(onTrigger: @escaping () -> Void) {
        hotKey = HotKey(key: .v, modifiers: [.command, .shift])
        hotKey?.keyDownHandler = onTrigger
    }

    func unregister() {
        hotKey = nil
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/Keyboard/
git commit -m "feat: add HotkeyManager (⌘⇧V global hotkey)"
```

---

## Task 5: NotchWindow — NSWindow Subclass + Geometry

**Files:**
- Create: `Sources/UI/NotchPanel/NotchWindow.swift`

**Interfaces:**
- Produces:
  - `class NotchWindow: NSWindow`
    - `static func notchFrame(on screen: NSScreen) -> NSRect` — returns exact notch rect
    - `static func expandedFrame(on screen: NSScreen) -> NSRect` — returns expanded panel rect
    - `init(screen: NSScreen)`
    - `func animateExpand(completion: (() -> Void)?)`
    - `func animateCollapse(completion: (() -> Void)?)`
    - `var isExpanded: Bool`

- [ ] **Step 1: Write NotchWindow.swift**

```swift
// Sources/UI/NotchPanel/NotchWindow.swift
import AppKit

class NotchWindow: NSWindow {
    private(set) var isExpanded = false
    private let targetScreen: NSScreen

    static func notchFrame(on screen: NSScreen) -> NSRect {
        // notch width from safeAreaInsets — safeAreaInsets.top > 0 means notch exists
        let screenFrame = screen.frame
        let notchWidth: CGFloat = 162  // 14" MacBook notch width in points
        let notchHeight: CGFloat = 26
        let x = screenFrame.midX - notchWidth / 2
        let y = screenFrame.maxY - notchHeight
        return NSRect(x: x, y: y, width: notchWidth, height: notchHeight)
    }

    static func expandedFrame(on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let panelWidth: CGFloat = 480
        let panelHeight: CGFloat = 520
        let notchHeight: CGFloat = 26
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.maxY - notchHeight - panelHeight
        return NSRect(x: x, y: y, width: panelWidth, height: notchHeight + panelHeight)
    }

    init(screen: NSScreen) {
        self.targetScreen = screen
        let frame = NotchWindow.notchFrame(on: screen)
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        backgroundColor = .black
        isOpaque = true
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    func animateExpand(completion: (() -> Void)? = nil) {
        guard !isExpanded else { completion?(); return }
        let target = NotchWindow.expandedFrame(on: targetScreen)
        hasShadow = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(target, display: true)
        } completionHandler: {
            self.isExpanded = true
            completion?()
        }
    }

    func animateCollapse(completion: (() -> Void)? = nil) {
        guard isExpanded else { completion?(); return }
        let target = NotchWindow.notchFrame(on: targetScreen)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(target, display: true)
        } completionHandler: {
            self.hasShadow = false
            self.isExpanded = false
            completion?()
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/UI/NotchPanel/NotchWindow.swift
git commit -m "feat: add NotchWindow with expand/collapse animation"
```

---

## Task 6: FuzzySearcher + ClipboardItemRow

**Files:**
- Create: `Sources/UI/Components/FuzzySearcher.swift`
- Create: `Sources/UI/Components/ClipboardItemRow.swift`

**Interfaces:**
- Produces:
  - `class FuzzySearcher`
    - `func search(query: String, in items: [ClipboardItem]) -> [ClipboardItem]`
  - `struct ClipboardItemRow: View`
    - `init(item: ClipboardItem, onSelect: @escaping (ClipboardItem, Bool) -> Void)`
    - `onSelect` second param `Bool` = isCommandClick

- [ ] **Step 1: Write FuzzySearcher.swift**

```swift
// Sources/UI/Components/FuzzySearcher.swift
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
```

- [ ] **Step 2: Write ClipboardItemRow.swift**

```swift
// Sources/UI/Components/ClipboardItemRow.swift
import SwiftUI

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let onSelect: (ClipboardItem, Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            typeIcon
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .lineLimit(2)
                Text(relativeTime)
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            let isCmd = NSEvent.modifierFlags.contains(.command)
            onSelect(item, isCmd)
        }
    }

    @ViewBuilder
    private var typeIcon: some View {
        switch item.type {
        case .text:
            Image(systemName: "doc.text")
                .foregroundColor(.blue)
        case .image:
            if let img = NSImage(data: item.content) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 20, height: 20)
                    .clipped()
                    .cornerRadius(3)
            } else {
                Image(systemName: "photo")
                    .foregroundColor(.purple)
            }
        case .file:
            Image(systemName: "doc")
                .foregroundColor(.orange)
        }
    }

    private var relativeTime: String {
        let date = Date(timeIntervalSince1970: TimeInterval(item.createdAt))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
```

- [ ] **Step 3: Verify build**

```bash
swift build
```

Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/UI/Components/
git commit -m "feat: add FuzzySearcher and ClipboardItemRow"
```

---

## Task 7: NotchPanelContent — SwiftUI Root View

**Files:**
- Create: `Sources/UI/NotchPanel/NotchPanelContent.swift`

**Interfaces:**
- Consumes: `ClipboardItem`, `ClipboardStore.fetchAll()`, `FuzzySearcher.search(query:in:)`, `ClipboardItemRow`
- Produces:
  - `struct NotchPanelContent: View`
    - `init(store: ClipboardStore, onSelect: @escaping (ClipboardItem, Bool) -> Void, onSettings: @escaping () -> Void)`

- [ ] **Step 1: Write NotchPanelContent.swift**

```swift
// Sources/UI/NotchPanel/NotchPanelContent.swift
import SwiftUI

struct NotchPanelContent: View {
    let store: ClipboardStore
    let onSelect: (ClipboardItem, Bool) -> Void
    let onSettings: () -> Void

    @State private var items: [ClipboardItem] = []
    @State private var searchQuery = ""
    private let searcher = FuzzySearcher()

    private var displayedItems: [ClipboardItem] {
        searcher.search(query: searchQuery, in: items)
    }

    var body: some View {
        VStack(spacing: 0) {
            // notch-height spacer — keeps top black matching notch
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
        .onAppear { reload() }
    }

    func reload() {
        items = (try? store.fetchAll()) ?? []
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/UI/NotchPanel/NotchPanelContent.swift
git commit -m "feat: add NotchPanelContent SwiftUI view"
```

---

## Task 8: NotchPanelController — Show/Hide/Toggle

**Files:**
- Create: `Sources/UI/NotchPanel/NotchPanelController.swift`

**Interfaces:**
- Consumes: `NotchWindow`, `NotchPanelContent`, `ClipboardStore`
- Produces:
  - `class NotchPanelController`
    - `init(store: ClipboardStore)`
    - `func toggle()`
    - `func show()`
    - `func hide()`
    - `var onShowSettings: (() -> Void)?`

- [ ] **Step 1: Write NotchPanelController.swift**

```swift
// Sources/UI/NotchPanel/NotchPanelController.swift
import AppKit
import SwiftUI

class NotchPanelController {
    private var window: NotchWindow?
    private let store: ClipboardStore
    private var outsideClickMonitor: Any?
    private var previousApp: NSRunningApplication?

    var onShowSettings: (() -> Void)?

    init(store: ClipboardStore) {
        self.store = store
    }

    func toggle() {
        if let w = window, w.isExpanded {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let screen = NSScreen.main else { return }

        // remember the app that was active before we steal focus
        previousApp = NSWorkspace.shared.frontmostApplication

        if window == nil {
            let w = NotchWindow(screen: screen)
            let content = NotchPanelContent(
                store: store,
                onSelect: { [weak self] item, isCommandClick in
                    self?.handleSelect(item: item, paste: isCommandClick)
                },
                onSettings: { [weak self] in
                    self?.onShowSettings?()
                }
            )
            w.contentView = NSHostingView(rootView: content)
            window = w
        }

        window?.makeKeyAndOrderFront(nil)
        window?.animateExpand()

        // dismiss on outside click
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] event in
            guard let self, let w = self.window else { return }
            let loc = event.locationInWindow
            let screenLoc = NSEvent.mouseLocation
            if !NSMouseInRect(screenLoc, w.frame, false) {
                self.hide()
            }
        }

        // ESC key
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                self?.hide()
                return nil
            }
            return event
        }
    }

    func hide() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        window?.animateCollapse {
            self.window?.orderOut(nil)
        }
    }

    private func handleSelect(item: ClipboardItem, paste: Bool) {
        // copy to clipboard
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.type {
        case .text:
            if let str = String(data: item.content, encoding: .utf8) {
                pb.setString(str, forType: .string)
            }
        case .image:
            pb.setData(item.content, forType: .png)
        case .file:
            if let str = String(data: item.content, encoding: .utf8),
               let url = URL(string: str) {
                pb.writeObjects([url as NSURL])
            }
        }

        hide()

        if paste {
            // re-activate previous app then simulate ⌘V
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.previousApp?.activate(options: .activateIgnoringOtherApps)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let src = CGEventSource(stateID: .hidSystemState)
                    let vKey: CGKeyCode = 9 // V
                    let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
                    let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
                    down?.flags = .maskCommand
                    up?.flags = .maskCommand
                    down?.post(tap: .cgAnnotatedSessionEventTap)
                    up?.post(tap: .cgAnnotatedSessionEventTap)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/UI/NotchPanel/NotchPanelController.swift
git commit -m "feat: add NotchPanelController with show/hide/paste logic"
```

---

## Task 9: MenuBarController — Click Detection on Notch

**Files:**
- Create: `Sources/UI/MenuBar/MenuBarController.swift`

**Interfaces:**
- Consumes: `NotchWindow.notchFrame(on:)`
- Produces:
  - `class MenuBarController`
    - `init()`
    - `func start(onNotchClick: @escaping () -> Void)`
    - `func stop()`

- [ ] **Step 1: Write MenuBarController.swift**

```swift
// Sources/UI/MenuBar/MenuBarController.swift
import AppKit

class MenuBarController {
    private var statusItem: NSStatusItem?
    private var mouseMonitor: Any?

    func start(onNotchClick: @escaping () -> Void) {
        // 1px invisible status item — just to keep app alive in menu bar space
        statusItem = NSStatusBar.system.statusItem(withLength: 1)
        statusItem?.isVisible = false

        guard let screen = NSScreen.main else { return }
        let notchRect = NotchWindow.notchFrame(on: screen)

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { event in
            let loc = NSEvent.mouseLocation
            if NSMouseInRect(loc, notchRect, false) {
                onNotchClick()
            }
        }
    }

    func stop() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        statusItem = nil
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/UI/MenuBar/MenuBarController.swift
git commit -m "feat: add MenuBarController for notch click detection"
```

---

## Task 10: SettingsView

**Files:**
- Create: `Sources/UI/Settings/SettingsView.swift`

**Interfaces:**
- Consumes: `ClipboardStore.clearAll()`
- Produces:
  - `struct SettingsView: View`
    - `init(store: ClipboardStore, sizeLimitMB: Binding<Double>, onDismiss: @escaping () -> Void)`

- [ ] **Step 1: Write SettingsView.swift**

```swift
// Sources/UI/Settings/SettingsView.swift
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    let store: ClipboardStore
    @Binding var sizeLimitMB: Double
    let onDismiss: () -> Void

    @State private var showClearConfirm = false
    @State private var launchAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Settings")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button("Done", action: onDismiss)
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
            }

            Divider().background(Color.gray.opacity(0.3))

            VStack(alignment: .leading, spacing: 4) {
                Text("Storage limit: \(Int(sizeLimitMB)) MB")
                    .foregroundColor(.white)
                    .font(.system(size: 12))
                Slider(value: $sizeLimitMB, in: 100...2000, step: 100)
            }

            Toggle("Launch at login", isOn: $launchAtLogin)
                .foregroundColor(.white)
                .font(.system(size: 12))
                .onChange(of: launchAtLogin) { enabled in
                    if enabled {
                        try? SMAppService.mainApp.register()
                    } else {
                        try? SMAppService.mainApp.unregister()
                    }
                }

            HStack {
                Text("Hotkey: ⌘⇧V (non-configurable in v1)")
                    .foregroundColor(.gray)
                    .font(.system(size: 11))
                Spacer()
            }

            Button("Clear All History") {
                showClearConfirm = true
            }
            .foregroundColor(.red)
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .confirmationDialog("Clear all clipboard history?", isPresented: $showClearConfirm) {
                Button("Clear All", role: .destructive) {
                    try? store.clearAll()
                }
            }

            Spacer()
        }
        .padding(16)
        .background(Color(white: 0.1))
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/UI/Settings/SettingsView.swift
git commit -m "feat: add SettingsView"
```

---

## Task 11: AppDelegate — Wire Everything Together

**Files:**
- Modify: `Sources/App/AppDelegate.swift`

**Interfaces:**
- Consumes: `ClipboardStore`, `ClipboardMonitor`, `HotkeyManager`, `NotchPanelController`, `MenuBarController`, `SettingsView`

- [ ] **Step 1: Rewrite AppDelegate.swift**

```swift
// Sources/App/AppDelegate.swift
import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: ClipboardStore!
    private var monitor: ClipboardMonitor!
    private var hotkey: HotkeyManager!
    private var panelController: NotchPanelController!
    private var menuBar: MenuBarController!
    private var settingsWindow: NSWindow?

    @AppStorage("sizeLimitMB") private var sizeLimitMB: Double = 500

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            store = try ClipboardStore(sizeLimitBytes: Int64(sizeLimitMB * 1_000_000))
        } catch {
            fatalError("Cannot open database: \(error)")
        }

        monitor = ClipboardMonitor(store: store)
        monitor.onNewItem = { [weak self] _ in
            DispatchQueue.main.async {
                // notify panel to reload if visible — panel reloads onAppear
            }
        }
        monitor.start()

        panelController = NotchPanelController(store: store)
        panelController.onShowSettings = { [weak self] in
            self?.showSettings()
        }

        hotkey = HotkeyManager()
        hotkey.register { [weak self] in
            DispatchQueue.main.async { self?.panelController.toggle() }
        }

        menuBar = MenuBarController()
        menuBar.start { [weak self] in
            DispatchQueue.main.async { self?.panelController.toggle() }
        }

        // show notch window immediately (collapsed, matching notch)
        panelController.show()
        panelController.hide()
    }

    private func showSettings() {
        if settingsWindow == nil {
            var sizeLimitBinding = Binding<Double>(
                get: { self.sizeLimitMB },
                set: { self.sizeLimitMB = $0 }
            )
            let view = SettingsView(
                store: store,
                sizeLimitMB: sizeLimitBinding,
                onDismiss: { [weak self] in
                    self?.settingsWindow?.close()
                }
            )
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 280),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "ClipboardManager Settings"
            w.contentView = NSHostingView(rootView: view)
            w.center()
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build
```

Expected: `Build complete!`

- [ ] **Step 3: Add entitlements for Accessibility (needed for CGEvent paste)**

Create `Sources/App/ClipboardManager.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
```

Note: For `CGEvent` paste and accessibility, macOS will prompt the user to grant Accessibility access in System Settings > Privacy & Security > Accessibility on first run. This is expected behavior.

- [ ] **Step 4: Commit**

```bash
git add Sources/App/AppDelegate.swift Sources/App/ClipboardManager.entitlements
git commit -m "feat: wire AppDelegate — all modules connected"
```

---

## Task 12: Run and Smoke Test

**Files:** None (verification only)

- [ ] **Step 1: Build and run**

```bash
swift run
```

Expected: App launches with no Dock icon (accessory policy). NotchWindow appears over notch area.

- [ ] **Step 2: Test clipboard monitoring**

Copy any text in another app. Wait 1 second. Trigger panel with `⌘⇧V`.
Expected: Item appears in panel list.

- [ ] **Step 3: Test image clipboard**

Copy an image (e.g., screenshot with `⌘⇧4` then copy). Trigger panel.
Expected: Image thumbnail appears in list.

- [ ] **Step 4: Test click-to-copy**

Click an item in the panel.
Expected: Panel dismisses, item is on clipboard (paste anywhere to verify).

- [ ] **Step 5: Test ⌘+Click paste**

Open a text editor. Copy some text in another app. Open panel, `⌘+Click` an item.
Expected: Text pasted directly into editor. (Requires Accessibility permission granted.)

- [ ] **Step 6: Test notch click**

Click in the hardware notch area on screen.
Expected: Panel expands (same as hotkey).

- [ ] **Step 7: Test fuzzy search**

Type partial text into search bar.
Expected: List filters to matching items.

- [ ] **Step 8: Test dismiss**

Press ESC or click outside panel.
Expected: Panel collapses back to notch size.

- [ ] **Step 9: Final commit**

```bash
git add -A
git commit -m "feat: ClipboardManager v1 complete"
```
