import AppKit
import Foundation

class ClipboardMonitor {
    private let store: ClipboardStore
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private let queue = DispatchQueue(label: "com.clipboardmanager.monitor", qos: .utility)

    /// Longest edge of the stored thumbnail, in pixels. Only used for the
    /// small row icon, so it never needs to be anywhere near the original.
    private static let thumbnailMaxDimension: CGFloat = 96

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

        do {
            try store.recordNewClip(item)
            onNewItem?(item)
        } catch {
            print("[ClipboardMonitor] insert failed: \(error)")
        }
    }

    private func parseItem(from pb: NSPasteboard) -> ClipboardItem? {
        // text
        if let string = pb.string(forType: .string), !string.isEmpty {
            let preview = String(string.prefix(1000))
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
            guard png.count <= 50_000_000 else {
                print("[ClipboardMonitor] image too large (\(png.count) bytes), skipping")
                return nil
            }
            let thumbnail = Self.makeThumbnail(from: rep, maxDimension: Self.thumbnailMaxDimension)
            return ClipboardItem(
                type: .image, content: png, preview: "Image \(png.count / 1024)KB", thumbnail: thumbnail
            )
        }
        return nil
    }

    /// Downscale once at capture time so the UI never has to decode the
    /// full-resolution image just to draw a small row icon.
    ///
    /// Renders into an explicit pixel-sized `NSBitmapImageRep` rather than
    /// via `NSImage.lockFocus()`, which silently multiplies the target size
    /// by the screen's backing scale factor (2x on Retina) — that made
    /// thumbnails 4x the intended pixel area, sometimes larger than a
    /// well-compressed full-size source.
    private static func makeThumbnail(from rep: NSBitmapImageRep, maxDimension: CGFloat) -> Data? {
        let sourceSize = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(sourceSize.width, sourceSize.height))
        let targetWidth = max(1, Int((sourceSize.width * scale).rounded()))
        let targetHeight = max(1, Int((sourceSize.height * scale).rounded()))

        guard let targetRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: targetWidth,
            pixelsHigh: targetHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let ctx = NSGraphicsContext(bitmapImageRep: targetRep) else { return nil }
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        rep.draw(in: NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        return targetRep.representation(using: .png, properties: [:])
    }
}
