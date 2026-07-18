<div align="center">

# Clippy

**Clipboard history manager for macOS — lives in your notch or follows your cursor.**

[![macOS](https://img.shields.io/badge/macOS-14.0+-000000?style=flat&logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9+-F05138?style=flat&logo=swift&logoColor=white)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat)](LICENSE)

![Clippy panel](images.png)

</div>

---

## What is Clippy?

Clippy silently records everything you copy — text, images, files — and lets you paste any of it back with a single keyboard shortcut. No cloud, no subscriptions, no bloat. Just a fast, native macOS app that stays out of your way until you need it.

Press `⌘⇧V`, search or arrow through your history, hit `Enter` — the item pastes directly into whatever you were typing in.

---

## Features

| | |
|---|---|
| **Clipboard history** | Automatically captures text, images, and files |
| **Instant paste** | `⌘⇧V` → arrow keys → `Enter` pastes to active cursor |
| **Fuzzy search** | Find any clip fast — just start typing |
| **Two panel modes** | Notch-anchored or cursor-following floating panel |
| **Pin items** | Keep important clips permanently at the top |
| **Action Shortcuts** | Define custom keyboard shortcuts for any action |
| **Frosted glass UI** | Native macOS vibes with adaptive dark/light support |
| **Size limit** | Configurable storage cap — auto-prunes old items |

---

## Install

```bash
git clone https://github.com/kresna1174/clippy
cd clippy
bash install.sh
```

Builds a release binary, creates `Clippy.app` in `/Applications`, and registers a LaunchAgent so it starts automatically on every login.

### Accessibility permission

Cursor-follow mode uses the Accessibility API to detect your text caret position. Grant access when prompted, or go to:

**System Settings → Privacy & Security → Accessibility → enable Clippy**

### Uninstall

```bash
bash uninstall.sh
```

Stops the app, removes the LaunchAgent, and deletes the app bundle.

---

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘⇧V` | Open Clippy |
| `↑` / `↓` | Navigate items |
| `Enter` | Paste selected item to active cursor |
| `⌘Enter` | Copy only (no paste) |
| Click | Paste item |
| Hover → pin icon | Pin / unpin item |
| `ESC` | Dismiss |

---

## Panel modes

**Notch** *(default)* — panel drops from the MacBook notch. Zero screen real-estate taken when closed.

**Cursor follow** — panel appears at your text cursor (or mouse position when caret is not detectable). Switch in Settings → Panel Position. Requires Accessibility permission.

---

## Architecture

```
Sources/
├── App/
│   ├── AppDelegate.swift              # Entry point — wires everything together
│   └── AppPreferences.swift           # UserDefaults-backed settings
├── Keyboard/
│   └── HotkeyManager.swift            # Global ⌘⇧V hotkey
├── Monitor/
│   └── ClipboardMonitor.swift         # Polls NSPasteboard for new items
├── Shortcuts/
│   ├── ShortcutStore.swift            # SQLite-backed shortcut persistence
│   ├── ShortcutItem.swift             # Shortcut data model
│   ├── ShortcutRunner.swift           # Executes shortcuts
│   └── ShortcutHotkeyManager.swift    # Per-shortcut hotkey registration
├── Storage/
│   ├── ClipboardItem.swift            # Data model (text / image / file)
│   └── ClipboardStore.swift           # SQLite store via GRDB, size-limited
└── UI/
    ├── Components/
    │   ├── ClipboardItemRow.swift      # Row with hover + selection highlight
    │   ├── NavigableTextField.swift    # Search field with arrow key interception
    │   └── FuzzySearcher.swift        # Fuse-powered fuzzy search
    ├── MenuBar/
    │   └── MenuBarController.swift    # Menu bar icon + toggle
    ├── NotchPanel/
    │   ├── NotchPanelContent.swift    # Shared SwiftUI panel + keyboard nav
    │   ├── NotchPanelController.swift # Notch-mode lifecycle (expand/collapse)
    │   └── NotchWindow.swift          # Borderless NSWindow anchored to notch
    ├── Panel/
    │   ├── FloatingPanelController.swift  # Cursor-follow lifecycle + AX caret
    │   ├── FloatingPanelWindow.swift      # Borderless NSWindow at popup level
    │   ├── PanelCoordinator.swift         # Routes toggle() by panel mode
    │   └── PasteHelper.swift              # yieldActivation + CGEvent paste
    ├── Settings/
    │   └── SettingsView.swift         # Storage limit, panel mode, login item
    └── Shortcuts/
        ├── ShortcutsPanel.swift       # Shortcuts tab UI
        ├── ShortcutRow.swift          # Single shortcut row
        └── AddShortcutView.swift      # New shortcut form
```

**Data flow:**

```
NSPasteboard change
    → ClipboardMonitor → ClipboardStore (SQLite / GRDB)

⌘⇧V
    → HotkeyManager → PanelCoordinator.toggle()
    → NotchPanelController or FloatingPanelController
    → NotchPanelContent (SwiftUI, shared)

User selects item + Enter
    → NSPasteboard ← item content
    → NSApp.yieldActivation(to: previousApp)
    → CGEvent ⌘V → previous app cursor
```

---

## Dependencies

| Package | Purpose |
|---------|---------|
| [GRDB](https://github.com/groue/GRDB.swift) | SQLite ORM for clipboard + shortcut storage |
| [HotKey](https://github.com/soffes/HotKey) | Global keyboard shortcut registration |
| [Fuse](https://github.com/krisk/fuse-swift) | Fuzzy search |

---

## Build from source

```bash
swift build              # debug
swift build -c release   # release
swift run                # run debug build directly
```

**Requirements:** macOS 14.0+, Swift 5.9+

---

<div align="center">

Made with ☕ on macOS

</div>
