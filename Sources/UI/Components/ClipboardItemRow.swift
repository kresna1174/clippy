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
