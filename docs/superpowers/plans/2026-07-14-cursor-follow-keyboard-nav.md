# Cursor-Follow Mode & Keyboard Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a cursor-follow popup mode and keyboard-first navigation (type-to-search, arrow keys, Enter-to-paste) to ClipboardManager.

**Architecture:** `PanelCoordinator` owns mode selection and delegates to either the existing `NotchPanelController` or a new `FloatingPanelController`. Both share `NotchPanelContent` (SwiftUI). Keyboard handling lives in the SwiftUI view via `@FocusState` and `onKeyPress`.

**Tech Stack:** Swift 5.9, macOS 13+, SwiftUI, AppKit, Accessibility (AX) framework, GRDB, HotKey, Fuse.

## Global Constraints

- macOS 13.0 minimum (`LSMinimumSystemVersion` in Info.plist)
- No new package dependencies
- Do not modify `NotchPanelController` or `NotchWindow` — they must remain unchanged
- `NSAccessibilityUsageDescription` already present in `Sources/App/Info.plist`
- Bundle ID: `com.clipboardmanager.app`
- Build: `swift build` from repo root; run: `swift run` or `.build/debug/ClipboardManager`

---

## File Map

**New files:**
- `Sources/App/AppPreferences.swift` — UserDefaults-backed preferences, `PanelMode` enum
- `Sources/UI/Panel/PanelCoordinator.swift` — mode selection, delegates toggle/hide
- `Sources/UI/Panel/FloatingPanelController.swift` — floating window lifecycle + AX caret detection
- `Sources/UI/Panel/FloatingPanelWindow.swift` — borderless NSWindow subclass for floating mode

**Modified files:**
- `Sources/UI/NotchPanel/NotchPanelContent.swift` — add keyboard nav, `selectedIndex`, `searchFocused`
- `Sources/UI/Components/ClipboardItemRow.swift` — add `isSelected: Bool` prop + highlight
- `Sources/UI/Settings/SettingsView.swift` — add `prefs: AppPreferences` param + panel mode picker
- `Sources/App/AppDelegate.swift` — replace `NotchPanelController` with `PanelCoordinator`; pass `prefs` to settings

---

### Task 1: AppPreferences + PanelMode enum

**Files:**
- Create: `Sources/App/AppPreferences.swift`

**Interfaces:**
- Produces:
  - `enum PanelMode: String, CaseIterable { case notch, cursorFollow }`
  - `class AppPreferences: ObservableObject` with `@Published var panelMode: PanelMode`

- [ ] **Step 1: Create `AppPreferences.swift`**

```swift
// Sources/App/AppPreferences.swift
import Foundation
import Combine

enum PanelMode: String, CaseIterable {
    case notch
    case cursorFollow
}

class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    @Published var panelMode: PanelMode {
        didSet { UserDefaults.standard.set(panelMode.rawValue, forKey: "panelMode") }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: "panelMode") ?? ""
        panelMode = PanelMode(rawValue: raw) ?? .notch
    }
}
```

- [ ] **Step 2: Build to verify no errors**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/App/AppPreferences.swift
git commit -m "feat: add AppPreferences with PanelMode enum"
```

---

### Task 2: FloatingPanelWindow

**Files:**
- Create: `Sources/UI/Panel/FloatingPanelWindow.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `class FloatingPanelWindow: NSWindow`
  - `static let panelSize: CGSize = CGSize(width: 480, height: 520)`
  - `init(frame: NSRect)`

- [ ] **Step 1: Create directory and file**

```bash
mkdir -p Sources/UI/Panel
```

```swift
// Sources/UI/Panel/FloatingPanelWindow.swift
import AppKit

class FloatingPanelWindow: NSWindow {
    static let panelSize = CGSize(width: 480, height: 520)

    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/UI/Panel/FloatingPanelWindow.swift
git commit -m "feat: add FloatingPanelWindow borderless NSWindow"
```

---

### Task 3: FloatingPanelController

**Files:**
- Create: `Sources/UI/Panel/FloatingPanelController.swift`

**Interfaces:**
- Consumes:
  - `FloatingPanelWindow(frame:)` from Task 2
  - `NotchPanelContent(viewModel:onSelect:onPin:onSettings:)` (existing)
  - `PanelViewModel(store:)` (existing)
  - `ClipboardStore` (existing)
- Produces:
  - `class FloatingPanelController`
  - `init(store: ClipboardStore)`
  - `var onShowSettings: (() -> Void)?`
  - `func toggle()`
  - `func show()`
  - `func hide()`

- [ ] **Step 1: Create `FloatingPanelController.swift`**

```swift
// Sources/UI/Panel/FloatingPanelController.swift
import AppKit
import SwiftUI

class FloatingPanelController {
    private var window: FloatingPanelWindow?
    private var viewModel: PanelViewModel?
    private var outsideClickMonitor: Any?
    private var escKeyMonitor: Any?
    private var previousApp: NSRunningApplication?
    private let store: ClipboardStore

    var onShowSettings: (() -> Void)?
    private(set) var isVisible = false

    init(store: ClipboardStore) {
        self.store = store
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication

        let origin = resolvePopupOrigin()
        let size = FloatingPanelWindow.panelSize
        let screen = screenContaining(origin)
        let frame = clampedFrame(origin: origin, size: size, screen: screen)

        let vm = PanelViewModel(store: store)
        viewModel = vm

        let w = FloatingPanelWindow(frame: frame)
        let content = NotchPanelContent(
            viewModel: vm,
            onSelect: { [weak self] item, isCommandClick in
                self?.handleSelect(item: item, paste: isCommandClick)
            },
            onPin: { [weak self] item in
                guard let self else { return }
                try? self.store.togglePin(id: item.id)
                self.viewModel?.reload()
            },
            onSettings: { [weak self] in
                self?.onShowSettings?()
            }
        )
        w.contentView = NSHostingView(rootView: content)
        window = w

        vm.reload()
        w.makeKeyAndOrderFront(nil)
        isVisible = true

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self, let w = self.window else { return }
            if !NSMouseInRect(NSEvent.mouseLocation, w.frame, false) { self.hide() }
        }

        escKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.hide(); return nil }
            return event
        }
    }

    func hide() {
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m); outsideClickMonitor = nil }
        if let m = escKeyMonitor { NSEvent.removeMonitor(m); escKeyMonitor = nil }
        window?.orderOut(nil)
        window = nil
        viewModel = nil
        isVisible = false
    }

    // MARK: - Private

    private func handleSelect(item: ClipboardItem, paste: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.type {
        case .text:
            if let str = String(data: item.content, encoding: .utf8) { pb.setString(str, forType: .string) }
        case .image:
            pb.setData(item.content, forType: NSPasteboard.PasteboardType("public.png"))
        case .file:
            if let str = String(data: item.content, encoding: .utf8), let url = URL(string: str) {
                pb.writeObjects([url as NSURL])
            }
        }
        hide()
        if paste {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.previousApp?.activate(options: .activateIgnoringOtherApps)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let src = CGEventSource(stateID: .hidSystemState)
                    let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
                    let up   = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
                    down?.flags = .maskCommand; up?.flags = .maskCommand
                    down?.post(tap: .cgAnnotatedSessionEventTap)
                    up?.post(tap: .cgAnnotatedSessionEventTap)
                }
            }
        }
    }

    private func resolvePopupOrigin() -> CGPoint {
        if let rect = axCaretRect() {
            // AX returns Quartz coords (Y from bottom of main screen); convert to AppKit
            let flippedY = (NSScreen.main?.frame.maxY ?? 0) - rect.maxY
            return CGPoint(x: rect.minX, y: flippedY - 8)
        }
        return NSEvent.mouseLocation
    }

    private func axCaretRect() -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              CFGetTypeID(focused as CFTypeRef) == AXUIElementGetTypeID() else { return nil }
        let el = focused as! AXUIElement
        var rangeVal: AnyObject?
        guard AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &rangeVal) == .success,
              CFGetTypeID(rangeVal as CFTypeRef) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        AXValueGetValue(rangeVal as! AXValue, AXValueType.cfRange, &range)
        var rangeAXVal = range
        guard let rangeAX = AXValueCreate(AXValueType.cfRange, &rangeAXVal) else { return nil }
        var boundsVal: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(el, kAXBoundsForRangeParameterizedAttribute as CFString, rangeAX, &boundsVal) == .success,
              CFGetTypeID(boundsVal as CFTypeRef) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        AXValueGetValue(boundsVal as! AXValue, AXValueType.cgRect, &rect)
        return rect
    }

    private func screenContaining(_ point: CGPoint) -> NSScreen {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func clampedFrame(origin: CGPoint, size: CGSize, screen: NSScreen) -> NSRect {
        let margin: CGFloat = 8
        let sf = screen.visibleFrame
        var x = origin.x
        var y = origin.y - size.height

        // flip above caret if would go below screen
        if y < sf.minY + margin { y = origin.y + 8 }
        // clamp right
        if x + size.width > sf.maxX - margin { x = sf.maxX - margin - size.width }
        // clamp left
        if x < sf.minX + margin { x = sf.minX + margin }
        // clamp top
        if y + size.height > sf.maxY - margin { y = sf.maxY - margin - size.height }

        return NSRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/UI/Panel/FloatingPanelController.swift
git commit -m "feat: add FloatingPanelController with AX caret detection"
```

---

### Task 4: PanelCoordinator

**Files:**
- Create: `Sources/UI/Panel/PanelCoordinator.swift`

**Interfaces:**
- Consumes:
  - `AppPreferences.shared` from Task 1
  - `NotchPanelController(store:)` (existing)
  - `FloatingPanelController(store:)` from Task 3
  - `ClipboardStore` (existing)
- Produces:
  - `class PanelCoordinator`
  - `init(store: ClipboardStore, prefs: AppPreferences)`
  - `var onShowSettings: (() -> Void)?`
  - `func toggle()`
  - `func hide()`

- [ ] **Step 1: Create `PanelCoordinator.swift`**

```swift
// Sources/UI/Panel/PanelCoordinator.swift
import Foundation
import Combine

class PanelCoordinator {
    private let store: ClipboardStore
    private let prefs: AppPreferences

    private var notchController: NotchPanelController?
    private var floatingController: FloatingPanelController?
    private var prefsCancellable: AnyCancellable?

    var onShowSettings: (() -> Void)? {
        didSet {
            notchController?.onShowSettings = onShowSettings
            floatingController?.onShowSettings = onShowSettings
        }
    }

    init(store: ClipboardStore, prefs: AppPreferences) {
        self.store = store
        self.prefs = prefs
        prefsCancellable = prefs.$panelMode.sink { [weak self] _ in
            self?.hideAll()
        }
    }

    func toggle() {
        switch prefs.panelMode {
        case .notch:
            floatingController?.hide()
            floatingController = nil
            if notchController == nil {
                let c = NotchPanelController(store: store)
                c.onShowSettings = onShowSettings
                notchController = c
            }
            notchController?.toggle()
        case .cursorFollow:
            notchController?.hide()
            notchController = nil
            if floatingController == nil {
                let c = FloatingPanelController(store: store)
                c.onShowSettings = onShowSettings
                floatingController = c
            }
            floatingController?.toggle()
        }
    }

    func hide() { hideAll() }

    private func hideAll() {
        notchController?.hide()
        floatingController?.hide()
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/UI/Panel/PanelCoordinator.swift
git commit -m "feat: add PanelCoordinator for mode delegation"
```

---

### Task 5: Wire PanelCoordinator into AppDelegate

**Files:**
- Modify: `Sources/App/AppDelegate.swift`

**Interfaces:**
- Consumes:
  - `PanelCoordinator(store:prefs:)` from Task 4
  - `AppPreferences.shared` from Task 1

- [ ] **Step 1: Replace `NotchPanelController` with `PanelCoordinator` in AppDelegate**

Replace entire content of `Sources/App/AppDelegate.swift`:

```swift
// Sources/App/AppDelegate.swift
import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: ClipboardStore!
    private var monitor: ClipboardMonitor!
    private var hotkey: HotkeyManager!
    private var coordinator: PanelCoordinator!
    private var menuBar: MenuBarController!
    private var settingsWindow: NSWindow?
    private let prefs = AppPreferences.shared

    @AppStorage("sizeLimitMB") private var sizeLimitMB: Double = 10

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.clipboardmanager.app")
            .filter { $0 != NSRunningApplication.current }
            .forEach { $0.terminate() }

        NSApp.setActivationPolicy(.accessory)

        do {
            store = try ClipboardStore(sizeLimitBytes: Int64(sizeLimitMB * 1_000_000))
        } catch {
            fatalError("Cannot open database: \(error)")
        }

        monitor = ClipboardMonitor(store: store)
        monitor.onNewItem = { _ in }
        monitor.start()

        coordinator = PanelCoordinator(store: store, prefs: prefs)
        coordinator.onShowSettings = { [weak self] in self?.showSettings() }

        hotkey = HotkeyManager()
        hotkey.register { [weak self] in
            DispatchQueue.main.async { self?.coordinator.toggle() }
        }

        menuBar = MenuBarController()
        menuBar.start { [weak self] in
            DispatchQueue.main.async { self?.coordinator.toggle() }
        }
    }

    private func showSettings() {
        if settingsWindow == nil {
            let sizeLimitBinding = Binding<Double>(
                get: { self.sizeLimitMB },
                set: { self.sizeLimitMB = $0 }
            )
            let view = SettingsView(
                store: store,
                prefs: prefs,
                sizeLimitMB: sizeLimitBinding,
                onDismiss: { [weak self] in self?.settingsWindow?.close() }
            )
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 340),
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

- [ ] **Step 2: Build (will fail until SettingsView is updated in Task 6)**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: error about `SettingsView` missing `prefs` param — that's fine, Task 6 fixes it.

- [ ] **Step 3: Commit (even with build error — it tracks intent)**

```bash
git add Sources/App/AppDelegate.swift
git commit -m "feat: wire PanelCoordinator into AppDelegate"
```

---

### Task 6: Update SettingsView with panel mode picker

**Files:**
- Modify: `Sources/UI/Settings/SettingsView.swift`

**Interfaces:**
- Consumes:
  - `AppPreferences` from Task 1 — `panelMode: PanelMode`, `PanelMode.notch`, `PanelMode.cursorFollow`
- Produces:
  - `SettingsView(store:prefs:sizeLimitMB:onDismiss:)` — updated signature

- [ ] **Step 1: Replace `SettingsView.swift`**

```swift
// Sources/UI/Settings/SettingsView.swift
import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    let store: ClipboardStore
    @ObservedObject var prefs: AppPreferences
    @Binding var sizeLimitMB: Double
    let onDismiss: () -> Void

    @State private var showClearConfirm = false
    @State private var launchAtLogin = false
    @State private var currentUsageMB: Double = 0
    @State private var showAXAlert = false

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

            // Panel position
            VStack(alignment: .leading, spacing: 6) {
                Text("Panel Position")
                    .foregroundColor(.white)
                    .font(.system(size: 12, weight: .medium))
                Picker("", selection: $prefs.panelMode) {
                    Text("Notch").tag(PanelMode.notch)
                    Text("Follow cursor").tag(PanelMode.cursorFollow)
                }
                .pickerStyle(.segmented)
                .onChange(of: prefs.panelMode) { newMode in
                    if newMode == .cursorFollow && !AXIsProcessTrusted() {
                        showAXAlert = true
                        prefs.panelMode = .notch
                    }
                }
            }
            .alert("Accessibility Access Required", isPresented: $showAXAlert) {
                Button("Open System Settings") {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    )
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enable Accessibility access in System Settings > Privacy & Security > Accessibility to use cursor-follow mode.")
            }

            Divider().background(Color.gray.opacity(0.3))

            // Storage
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Storage limit: \(Int(sizeLimitMB)) MB")
                        .foregroundColor(.white)
                        .font(.system(size: 12))
                    Spacer()
                    Text("Used: \(String(format: "%.1f", currentUsageMB)) MB")
                        .foregroundColor(currentUsageMB >= sizeLimitMB ? .red : .gray)
                        .font(.system(size: 11))
                }
                Slider(value: $sizeLimitMB, in: 10...500, step: 10)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(currentUsageMB >= sizeLimitMB ? Color.red : Color.blue)
                            .frame(width: geo.size.width * min(currentUsageMB / max(sizeLimitMB, 1), 1.0), height: 4)
                    }
                }
                .frame(height: 4)
            }
            .onAppear {
                currentUsageMB = (try? Double(store.totalSizeBytes())).map { $0 / 1_000_000 } ?? 0
            }

            Toggle("Launch at login", isOn: $launchAtLogin)
                .foregroundColor(.white)
                .font(.system(size: 12))
                .onChange(of: launchAtLogin) { newValue in
                    if newValue { try? SMAppService.mainApp.register() }
                    else { try? SMAppService.mainApp.unregister() }
                }

            HStack {
                Text("Hotkey: ⌘⇧V (non-configurable in v1)")
                    .foregroundColor(.gray)
                    .font(.system(size: 11))
                Spacer()
            }

            Button("Clear All History") { showClearConfirm = true }
                .foregroundColor(.red)
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .confirmationDialog("Clear all clipboard history?", isPresented: $showClearConfirm) {
                    Button("Clear All", role: .destructive) { try? store.clearAll() }
                }

            Spacer()
        }
        .padding(16)
        .background(Color(white: 0.1))
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/UI/Settings/SettingsView.swift
git commit -m "feat: add panel position picker to SettingsView"
```

---

### Task 7: Keyboard navigation in NotchPanelContent

**Files:**
- Modify: `Sources/UI/NotchPanel/NotchPanelContent.swift`

**Interfaces:**
- Consumes: `ClipboardItemRow(item:isSelected:onSelect:onPin:)` — updated sig from Task 8 (implement Task 7 first, Task 8 adds the prop)
- Produces: updated `NotchPanelContent` with `selectedIndex`, `searchFocused`, keyboard handling

Note: Task 7 and Task 8 are tightly coupled. Implement Task 7 first (passing `isSelected: false` placeholder), then Task 8 wires up the real prop.

- [ ] **Step 1: Replace `NotchPanelContent.swift`**

```swift
// Sources/UI/NotchPanel/NotchPanelContent.swift
import SwiftUI

class PanelViewModel: ObservableObject {
    @Published var items: [ClipboardItem] = []
    let store: ClipboardStore

    init(store: ClipboardStore) { self.store = store }

    func reload() { items = (try? store.fetchAll()) ?? [] }
}

struct NotchPanelContent: View {
    @ObservedObject var viewModel: PanelViewModel
    let onSelect: (ClipboardItem, Bool) -> Void
    let onPin: (ClipboardItem) -> Void
    let onSettings: () -> Void

    @State private var searchQuery = ""
    @State private var isVisible = false
    @State private var selectedIndex: Int? = nil
    @FocusState private var searchFocused: Bool

    private let searcher = FuzzySearcher()

    private var displayedItems: [ClipboardItem] {
        searcher.search(query: searchQuery, in: viewModel.items)
    }

    private var notchHeight: CGFloat { NSScreen.main?.safeAreaInsets.top ?? 26 }
    private let shadowPad: CGFloat = NotchWindow.shadowPad

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)

            VStack(spacing: 0) {
                // header
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    TextField("Search...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($searchFocused)
                    Spacer()
                    Text("\(viewModel.items.count) items")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Button(action: onSettings) {
                        Image(systemName: "gear")
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider().opacity(0.4)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(displayedItems.enumerated()), id: \.element.id) { idx, item in
                                ClipboardItemRow(
                                    item: item,
                                    isSelected: selectedIndex == idx,
                                    onSelect: onSelect,
                                    onPin: onPin
                                )
                                .id(idx)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity
                                ))
                                Divider().opacity(0.25)
                            }
                        }
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: displayedItems.map(\.id))
                    }
                    .onChange(of: selectedIndex) { idx in
                        if let idx { withAnimation { proxy.scrollTo(idx, anchor: .center) } }
                    }
                }
            }
            .background(VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow))
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0, bottomLeadingRadius: 20,
                    bottomTrailingRadius: 20, topTrailingRadius: 0
                )
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0, bottomLeadingRadius: 20,
                    bottomTrailingRadius: 20, topTrailingRadius: 0
                )
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .padding(.horizontal, shadowPad)
            .padding(.bottom, shadowPad)
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.96, anchor: .top)
        }
        .focusable()
        .onKeyPress(phases: .down) { press in
            handleKeyPress(press)
        }
        .onAppear {
            viewModel.reload()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { isVisible = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { searchFocused = true }
        }
        .onDisappear { isVisible = false }
        .onChange(of: searchQuery) { _ in selectedIndex = nil }
    }

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        let count = displayedItems.count
        switch press.key {
        case .downArrow:
            searchFocused = false
            selectedIndex = min((selectedIndex ?? -1) + 1, count - 1)
            return .handled
        case .upArrow:
            searchFocused = false
            let next = (selectedIndex ?? count) - 1
            if next < 0 { selectedIndex = nil; searchFocused = true }
            else { selectedIndex = next }
            return .handled
        case .return:
            guard let idx = selectedIndex, idx < count else { return .ignored }
            let item = displayedItems[idx]
            let paste = press.modifiers.contains(.command) ? false : true
            onSelect(item, paste)
            return .handled
        case .tab:
            searchFocused.toggle()
            return .handled
        default:
            // printable char while list focused → redirect to search
            if !searchFocused && !press.characters.isEmpty && press.characters.allSatisfy({ $0.isLetter || $0.isNumber || $0.isPunctuation || $0 == " " }) {
                searchFocused = true
                searchQuery += press.characters
                return .handled
            }
            return .ignored
        }
    }
}
```

- [ ] **Step 2: Build (may fail until ClipboardItemRow updated in Task 8)**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: error about `ClipboardItemRow` missing `isSelected` — proceed to Task 8 immediately.

- [ ] **Step 3: Commit**

```bash
git add Sources/UI/NotchPanel/NotchPanelContent.swift
git commit -m "feat: keyboard navigation in NotchPanelContent"
```

---

### Task 8: ClipboardItemRow selected state

**Files:**
- Modify: `Sources/UI/Components/ClipboardItemRow.swift`

**Interfaces:**
- Consumes: nothing new
- Produces: `ClipboardItemRow(item:isSelected:onSelect:onPin:)` — `isSelected: Bool` added

- [ ] **Step 1: Replace `ClipboardItemRow.swift`**

```swift
// Sources/UI/Components/ClipboardItemRow.swift
import SwiftUI

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onSelect: (ClipboardItem, Bool) -> Void
    let onPin: (ClipboardItem) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            typeIcon
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                Text(relativeTime)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()

            if item.isPinned || isHovered {
                Button(action: { onPin(item) }) {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                        .foregroundColor(item.isPinned ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.25)
                : isHovered ? Color.white.opacity(0.08) : Color.clear
        )
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.1), value: isSelected)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            let isCmd = NSEvent.modifierFlags.contains(.command)
            onSelect(item, isCmd)
        }
    }

    @ViewBuilder
    private var typeIcon: some View {
        switch item.type {
        case .text:
            Image(systemName: "doc.text").foregroundColor(.blue)
        case .image:
            if let img = NSImage(data: item.content) {
                Image(nsImage: img).resizable().scaledToFill()
                    .frame(width: 20, height: 20).clipped().cornerRadius(3)
            } else {
                Image(systemName: "photo").foregroundColor(.purple)
            }
        case .file:
            Image(systemName: "doc").foregroundColor(.orange)
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

- [ ] **Step 2: Build — everything should compile now**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/UI/Components/ClipboardItemRow.swift
git commit -m "feat: add isSelected highlight to ClipboardItemRow"
```

---

### Task 9: Smoke test & final verification

**Files:** none (manual testing)

- [ ] **Step 1: Run the app**

```bash
swift run &
sleep 3
```

- [ ] **Step 2: Test notch mode (default)**

1. Press ⌘⇧V — notch panel opens from top
2. Type a few chars — search filters items
3. Press ↓ to move selection, verify blue highlight moves
4. Press ↑ past top — focus returns to search field
5. Press Enter on selected item — item pasted into focused app
6. Press ⌘⇧V again, press ⌘Enter — item copied but not pasted
7. Press ESC — panel dismisses

- [ ] **Step 3: Test cursor-follow mode**

1. Open ClipboardManager Settings (gear icon in panel)
2. Switch "Panel Position" to "Follow cursor"
   - If Accessibility not granted: alert appears, clicking "Open System Settings" opens Privacy pane
   - Grant access, relaunch app, switch to Follow cursor again
3. Click inside a text field in any app (e.g. TextEdit, Safari URL bar)
4. Press ⌘⇧V — panel appears near the text caret (or near mouse if caret not detectable)
5. Repeat keyboard tests from Step 2

- [ ] **Step 4: Test edge cases**

- Open panel near right screen edge → panel shifts left, stays on screen
- Open panel near bottom → panel flips above origin point
- Switch mode while panel is open → panel closes, reopens in new mode on next ⌘⇧V

- [ ] **Step 5: Final commit**

```bash
git add -A
git status  # verify nothing unexpected
git commit -m "feat: cursor-follow mode and keyboard navigation complete"
```
