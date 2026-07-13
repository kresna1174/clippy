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
            return ClipboardItem(type: .text, content: Data(string.utf8), preview: preview)
        }
        // file URL
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first {
            return ClipboardItem(type: .file, content: Data(url.path.utf8), preview: url.lastPathComponent)
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
            return ClipboardItem(type: .image, content: png, preview: "Image \(png.count / 1024)KB")
        }
        return nil
    }
}
