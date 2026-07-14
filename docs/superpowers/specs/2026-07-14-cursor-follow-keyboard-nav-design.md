# Cursor-Follow Mode & Keyboard Navigation

Date: 2026-07-14

## Overview

Two features added to ClipboardManager:
1. **Cursor-follow mode** — popup appears near the active text caret (or mouse fallback), like Windows clipboard IME popup
2. **Keyboard-first navigation** — type to search, arrow keys navigate, Enter pastes immediately

## Architecture

```
AppDelegate
  └── PanelCoordinator              ← new: owns mode selection
        ├── NotchPanelController    (existing, unchanged)
        └── FloatingPanelController ← new
              └── FloatingPanelWindow ← new

Shared:
  NotchPanelContent (SwiftUI)       ← extended with keyboard nav
  PanelViewModel                    ← unchanged
```

`AppDelegate` calls `coordinator.toggle()` instead of directly calling `NotchPanelController`. `PanelCoordinator` reads `AppPreferences.panelMode` and delegates to the correct controller.

## New Files

### `PanelCoordinator.swift`
- Owns `AppPreferences` instance
- Holds either `NotchPanelController` or `FloatingPanelController` depending on mode
- Exposes `toggle()`, `hide()`, `onShowSettings` passthrough
- Recreates the active controller when mode changes

### `FloatingPanelController.swift`
- On `show()`: calls `resolvePopupOrigin()`, spawns `FloatingPanelWindow` at that origin
- On `hide()`: collapses and removes window (simple fade, no notch animation)
- Shares `NotchPanelContent` view with same `onSelect`/`onPin`/`onSettings` callbacks
- Registers outside-click and ESC monitors (same pattern as `NotchPanelController`)
- Restores previous app on paste

### `FloatingPanelWindow.swift`
- `NSWindow` subclass: borderless, `backgroundColor = .clear`, `hasShadow = false`
- `level = .popUpMenu`
- `canBecomeKey = true`
- Fixed content size 480×520

### `AppPreferences.swift`
- `ObservableObject`, UserDefaults-backed
- `panelMode: PanelMode` — `.notch` / `.cursorFollow`

## Modified Files

### `AppDelegate.swift`
- Replace `NotchPanelController` with `PanelCoordinator`
- Pass `AppPreferences` to `SettingsView`

### `NotchPanelContent.swift`
- Add `@State private var selectedIndex: Int?`
- Add `@FocusState private var searchFocused: Bool`
- On appear: set `searchFocused = true`
- Add `.onKeyPress` on outer `VStack`:
  - Printable chars → append to `searchQuery` (if search not focused, steal focus)
  - `↑` / `↓` → move `selectedIndex`, clamp to list bounds
  - `Enter` → paste selected item (call `onSelect(item, true)`)
  - `⌘Enter` → copy selected item (call `onSelect(item, false)`)
  - `ESC` → dismiss (already handled by controller monitor, but also clear search here)
- Pass `selectedIndex` down to `ClipboardItemRow` as `isSelected: Bool`
- `ScrollViewReader` to scroll selected item into view on arrow key

### `ClipboardItemRow.swift`
- Add `isSelected: Bool` prop
- Background: `isSelected` → `Color.accentColor.opacity(0.2)`, hover → `Color.white.opacity(0.08)`, else clear
- Selected takes priority over hover

### `SettingsView.swift`
- Add `@ObservedObject var prefs: AppPreferences` param
- Add "Panel Position" section with `Picker`:
  - Notch (default)
  - Follow cursor
- On mode change to `.cursorFollow`: check `AXIsProcessTrusted()`, if false show alert directing user to System Settings > Privacy > Accessibility

## AX Caret Detection

```swift
func resolvePopupOrigin() -> CGPoint {
    if let rect = axCaretRect() { return CGPoint(x: rect.minX, y: rect.minY - 8) }
    return NSEvent.mouseLocation
}

func axCaretRect() -> CGRect? {
    guard AXIsProcessTrusted() else { return nil }
    let system = AXUIElementCreateSystemWide()
    var focused: AnyObject?
    guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
          let el = focused as! AXUIElement? else { return nil }
    var rangeVal: AnyObject?
    guard AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &rangeVal) == .success else { return nil }
    var range = CFRange()
    AXValueGetValue(rangeVal as! AXValue, .cfRange, &range)
    var boundsVal: AnyObject?
    let rangeAX = AXValueCreate(.cfRange, &range)!
    guard AXUIElementCopyParameterizedAttributeValue(el, kAXBoundsForRangeParameterizedAttribute as CFString, rangeAX, &boundsVal) == .success else { return nil }
    var rect = CGRect.zero
    AXValueGetValue(boundsVal as! AXValue, .cgRect, &rect)
    return rect  // already in screen (Quartz) coordinates, need to flip Y for AppKit
}
```

Y-axis: AX returns Quartz coords (origin bottom-left on main screen). Convert with `NSScreen.main!.frame.maxY - rect.maxY`.

## Popup Positioning

After resolving origin:
1. Place popup so top-left = `(origin.x, origin.y - panelHeight)`
2. Clamp: if right edge > screen.maxX → shift left
3. Clamp: if bottom edge < screen.minY → flip above caret (`origin.y + 8`)
4. Margin: 8pt from any screen edge

## Accessibility Permission

- Add `NSAccessibilityUsageDescription` to `Info.plist`
- Check `AXIsProcessTrusted()` when user switches to cursor-follow mode
- If not trusted: show `NSAlert` with message "Enable Accessibility access in System Settings > Privacy & Security > Accessibility to use cursor-follow mode." with button "Open System Settings" → `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)`
- If user denies: revert `panelMode` to `.notch`

## Keyboard Shortcuts Summary

| Key | Action |
|-----|--------|
| Any printable | Type into search (panel opens focused on search) |
| `↓` / `↑` | Navigate list |
| `Enter` | Paste selected item to previous app |
| `⌘Enter` | Copy selected item only (no paste) |
| `ESC` | Dismiss panel |
| `Tab` | Toggle focus search ↔ list |

## Out of Scope

- Configurable hotkey (tracked separately in SettingsView as v1 note)
- Per-app mode overrides
- Mouse-cursor-only mode (replaced by AX+fallback approach)
