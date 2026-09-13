import AppKit

/// Writes a clip's full content to the system pasteboard. Shared between
/// `FloatingPanelController` and `NotchPanelController`, which previously
/// each carried their own copy of this logic.
enum ClipboardPasteboardWriter {
    /// Fetches the item's full content by id (lazily — the list/search UI
    /// only ever holds the lightweight `ClipboardItemSummary`) and writes it
    /// to the pasteboard.
    static func write(_ item: ClipboardItemSummary, store: ClipboardStore) {
        guard let content = try? store.fetchContent(id: item.id) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.type {
        case .text:
            if let str = String(data: content, encoding: .utf8) { pb.setString(str, forType: .string) }
        case .image:
            pb.setData(content, forType: NSPasteboard.PasteboardType("public.png"))
        case .file:
            if let str = String(data: content, encoding: .utf8), let url = URL(string: str) {
                pb.writeObjects([url as NSURL])
            }
        }
    }
}
