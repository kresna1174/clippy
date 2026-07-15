# ClipboardManager — Notch Panel Design

**Date:** 2026-07-13  
**Status:** Approved

---

## Overview

macOS clipboard manager yang memanfaatkan notch MacBook sebagai UI entry point. Panel muncul dengan animasi Dynamic Island-style — notch "melebar" ke samping lalu turun ke bawah menampilkan clipboard history. Target device: MacBook 14".

---

## Architecture

```
ClipboardManager
├── App/            ← NSApplication entry, AppDelegate, lifecycle
├── Monitor/        ← NSPasteboard polling (0.5s interval), detect changes
├── Storage/        ← SQLite via GRDB, store text/image/file items
├── Keyboard/       ← hotkey registration via HotKey package (⌘⇧V)
└── UI/
    ├── NotchPanel/ ← Fake Dynamic Island window + SwiftUI content
    ├── MenuBar/    ← NSStatusItem (1px hidden) untuk notch click detection
    └── Settings/   ← SwiftUI settings panel
```

**Build system:** Swift Package Manager (no `.xcodeproj`), `swift build` / `swift run`.

**Dependencies:**
- [GRDB.swift](https://github.com/groue/GRDB.swift) — SQLite ORM
- [HotKey](https://github.com/soffes/HotKey) — global hotkey registration
- [fuse-swift](https://github.com/krisk/fuse-swift) — fuzzy search

---

## Data Flow

1. `Monitor` deteksi `NSPasteboard.changeCount` berubah → parse tipe → simpan ke `Storage`
2. User trigger via hotkey `⌘⇧V` atau click notch area → `NotchPanel` animate expand
3. User browse/fuzzy search → pilih item:
   - Click biasa → copy ke clipboard
   - `⌘+Click` → paste langsung ke app yang aktif sebelumnya
4. Panel dismiss: click luar, ESC, atau re-trigger hotkey

---

## NotchPanel — Fake Dynamic Island

### Notch Geometry
```swift
// Detect notch width dari safeAreaInsets
let notchWidth = NSScreen.main?.safeAreaInsets.top ?? 0
// 14" notch: ~162pt wide, tinggi ~26pt
```

### Window Setup
- `NSWindow` dengan `styleMask: .borderless`, `backgroundColor: .black`
- Level: `NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)`
- Initial frame: persis notch bounds (centered di top of main screen)
- `collectionBehavior: [.canJoinAllSpaces, .stationary, .ignoresCycle]`
- `isOpaque: false`, `hasShadow: false` saat collapsed; shadow enable saat expanded

### Expand Animation
```
Collapsed:  [  ████notch████  ]        ← match notch persis
Expanding:  [ ██████████████████ ]     ← melebar ke samping
             ┌──────────────────┐
             │  clipboard panel │      ← turun ke bawah
             └──────────────────┘
```
- `NSAnimationContext` dengan `duration: 0.35`, `timingFunction: .easeInEaseOut`
- Content: `NSHostingView<NotchPanelContent>` (SwiftUI)
- Panel width saat expanded: 480pt, height: max 520pt (scrollable)

### Click Detection di Notch Area
- `NSStatusItem` width 1px di kiri notch sebagai invisible anchor
- Global mouse event monitor via `NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown)` — cek apakah koordinat dalam notch bounds
- Bila ya → trigger expand sama seperti hotkey

### Dismiss
- Click di luar window bounds → reverse animate collapse
- ESC key → collapse
- Re-trigger hotkey → toggle (collapse jika sudah expand)

---

## Storage

### Schema
```sql
CREATE TABLE items (
  id          TEXT PRIMARY KEY,   -- UUID string
  type        TEXT NOT NULL,      -- "text" | "image" | "file"
  content     BLOB NOT NULL,      -- raw content (text UTF-8 / PNG bytes / file path)
  preview     TEXT,               -- display string: truncated text / filename / URL
  created_at  INTEGER NOT NULL,   -- Unix timestamp (seconds)
  size_bytes  INTEGER NOT NULL
);
```

### Storage Rules
- DB path: `~/Library/Application Support/ClipboardManager/history.db`
- Total size cap: configurable, default 500MB — prune item terlama saat over limit
- Per-item image cap: 10MB (skip item lebih besar, log warning)
- Unlimited item count (dibatasi size cap saja)

---

## Monitor

- `DispatchSourceTimer` interval 0.5s di background queue
- Bandingkan `NSPasteboard.generalPasteboard.changeCount` dengan last known count
- Tipe detection:
  - `.string` available type → simpan sebagai `text`
  - `.tiff` / `.png` → compress ke PNG → simpan sebagai `image`
  - `.fileURL` → simpan path string sebagai `file`
- Skip jika `changeCount` sama (no change)
- Skip jika content identik dengan item terbaru di storage (copy ulang hal sama)

---

## Keyboard

- Hotkey default: `⌘⇧V` via HotKey package
- Configurable dari Settings panel
- Trigger: toggle NotchPanel expand/collapse

---

## UI — NotchPanel Content (SwiftUI)

```
┌─────────────────────────────────────┐
│  🔍 Search...                  [⚙] │  ← search bar + settings button
├─────────────────────────────────────┤
│  [img] Screenshot 2026-07-13.png    │  ← file item
│  "Hello world this is a long te..." │  ← text item
│  [img] photo.jpg                    │  ← image item
│  /Users/krisna/Documents/file.pdf   │  ← file path item
│  ...                                │
└─────────────────────────────────────┘
```

- `ScrollView` dengan `LazyVStack` untuk performa
- Search bar: `TextField` → real-time fuzzy filter via fuse-swift (search `preview`)
- Item row: icon tipe, preview text/thumbnail, timestamp relative
- Click: copy to clipboard + dismiss panel
- `⌘+Click`: paste langsung (simulate `⌘V` via `CGEvent` ke frontmost app sebelum panel muncul)
- Image item: thumbnail 40×40pt

---

## Settings Panel

Accessible via `⚙` button di panel atau menubar icon:
- **Hotkey:** rebind trigger hotkey
- **Storage size cap:** slider 100MB–2GB
- **Launch at login:** toggle
- **Clear history:** button dengan konfirmasi

---

## Error Handling

- Pasteboard access denied → silent skip, log ke Console
- DB write fail → retry 1x, lalu skip item (tidak crash)
- Image terlalu besar (>10MB) → skip, tidak simpan
- Hotkey conflict → alert di Settings dengan instruksi rebind

---

## Out of Scope

- Privacy/exclude app tertentu (bisa ditambah v2)
- iCloud sync
- Encryption at rest
- Windows/Linux support
