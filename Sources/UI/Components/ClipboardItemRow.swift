// Sources/UI/Components/ClipboardItemRow.swift
import SwiftUI

struct ClipboardItemRow: View {
    let item: ClipboardItemSummary
    let isSelected: Bool
    let onSelect: (ClipboardItemSummary, Bool) -> Void
    let onPin: (ClipboardItemSummary) -> Void
    let onDelete: (ClipboardItemSummary) -> Void

    @State private var isHovered = false
    // Decoded once per item (from the small stored thumbnail, not the full
    // image) and cached here instead of re-decoding on every body
    // evaluation (e.g. every hover toggle).
    @State private var thumbImage: NSImage?

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

            HStack(spacing: 6) {
                if item.isPinned || isHovered {
                    Button(action: { onPin(item) }) {
                        Image(systemName: item.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 11))
                            .foregroundColor(item.isPinned ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(item.isPinned ? "Unpin item" : "Pin item")
                    .transition(.opacity)
                }

                if isHovered {
                    Button(action: { onDelete(item) }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Delete from history")
                    .transition(.opacity)
                }
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
        .contextMenu {
            Button("Paste") {
                onSelect(item, true)
            }
            Button("Copy to Clipboard") {
                onSelect(item, false)
            }
            Button(item.isPinned ? "Unpin" : "Pin") {
                onPin(item)
            }
            Divider()
            Button("Delete", role: .destructive) {
                onDelete(item)
            }
        }
        .onAppear(perform: decodeThumbnailIfNeeded)
        .onChange(of: item.thumbnail) { _ in decodeThumbnailIfNeeded() }
    }

    private func decodeThumbnailIfNeeded() {
        guard item.type == .image, thumbImage == nil, let data = item.thumbnail else { return }
        thumbImage = NSImage(data: data)
    }

    @ViewBuilder
    private var typeIcon: some View {
        switch item.type {
        case .text:
            Image(systemName: "doc.text").foregroundColor(.blue)
        case .image:
            if let img = thumbImage {
                Image(nsImage: img).resizable().scaledToFill()
                    .frame(width: 20, height: 20).clipped().clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: "photo").foregroundColor(.purple)
            }
        case .file:
            Image(systemName: "doc").foregroundColor(.orange)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var relativeTime: String {
        let date = Date(timeIntervalSince1970: TimeInterval(item.createdAt))
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
