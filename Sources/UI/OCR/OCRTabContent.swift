// Sources/UI/OCR/OCRTabContent.swift
import SwiftUI
import AppKit

struct OCRTabContent: View {
    @ObservedObject var viewModel: PanelViewModel
    var searchQuery: String = ""
    let onSelectText: (String, Bool) -> Void
    let onDelete: (ClipboardItemSummary) -> Void

    @State private var selectedImageID: String? = nil
    @State private var isCopied = false
    @State private var isExtracting = false
    @State private var onDemandText: [String: String] = [:]
    @State private var fullImageCache: [String: NSImage] = [:]

    private var imageItems: [ClipboardItemSummary] {
        let allImages = viewModel.items.filter { $0.type == .image }
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return allImages }
        return allImages.filter { item in
            let previewMatch = item.preview.lowercased().contains(q)
            let textMatch = item.extractedText?.lowercased().contains(q) ?? false
            return previewMatch || textMatch
        }
    }

    private var activeItem: ClipboardItemSummary? {
        if let id = selectedImageID, let match = imageItems.first(where: { $0.id == id }) {
            return match
        }
        return imageItems.first
    }

    private var currentText: String? {
        guard let item = activeItem else { return nil }
        if let live = onDemandText[item.id] {
            return live.isEmpty ? nil : live
        }
        return item.extractedText
    }

    var body: some View {
        Group {
            if imageItems.isEmpty {
                emptyState
            } else if let item = activeItem {
                mainContentView(for: item)
            }
        }
        .onAppear {
            if selectedImageID == nil {
                selectedImageID = imageItems.first?.id
            }
            performOnDemandOCRIfNeeded()
        }
        .onChange(of: selectedImageID) { _ in
            isCopied = false
            performOnDemandOCRIfNeeded()
        }
        .onChange(of: viewModel.items.map(\.id)) { _ in
            if selectedImageID == nil || !imageItems.contains(where: { $0.id == selectedImageID }) {
                selectedImageID = imageItems.first?.id
            }
            performOnDemandOCRIfNeeded()
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "text.viewfinder")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.6))

            Text("No Images Found")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            Text("Copy a screenshot (⌘⇧4) or image.\nClippy will automatically extract the text here.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Main Content

    @ViewBuilder
    private func mainContentView(for item: ClipboardItemSummary) -> some View {
        VStack(spacing: 10) {
            // Recent images thumbnail strip (if more than 1 image)
            if imageItems.count > 1 {
                thumbnailStrip
                    .padding(.top, 4)
            }

            // Image info & preview card
            imagePreviewCard(for: item)

            // Extracted text box
            textBox(for: item)

            // Action footer
            actionFooter(for: item)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Thumbnail Strip

    @ViewBuilder
    private var thumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(imageItems) { item in
                    thumbnailPill(for: item)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .frame(height: 38)
    }

    @ViewBuilder
    private func thumbnailPill(for item: ClipboardItemSummary) -> some View {
        let isSelected = item.id == (activeItem?.id ?? "")
        Button(action: {
            selectedImageID = item.id
        }) {
            HStack(spacing: 6) {
                if let thumbData = item.thumbnail, let nsImg = NSImage(data: thumbData) {
                    Image(nsImage: nsImg)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 12))
                        .frame(width: 24, height: 24)
                        .foregroundColor(.secondary)
                }

                Text(formatRelativeTime(item.createdAt))
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.3)
                    : Color.white.opacity(0.06)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.1), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contextMenu {
                Button("Delete", role: .destructive) {
                    deleteItem(item)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Image Preview Card

    @ViewBuilder
    private func imagePreviewCard(for item: ClipboardItemSummary) -> some View {
        HStack(spacing: 12) {
            // Thumbnail / Image
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.25))

                if let cached = fullImageCache[item.id] {
                    Image(nsImage: cached)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(6)
                        .padding(4)
                } else if let thumbData = item.thumbnail, let thumb = NSImage(data: thumbData) {
                    Image(nsImage: thumb)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(6)
                        .padding(4)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 80, height: 60)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )

            // Meta details
            VStack(alignment: .leading, spacing: 4) {
                Text(item.preview.isEmpty ? "Captured Image" : item.preview)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .foregroundColor(.primary)

                HStack(spacing: 8) {
                    Label(formatRelativeTime(item.createdAt), systemImage: "clock")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    if let text = currentText {
                        let wordCount = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text("\(wordCount) words")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }

                if isExtracting {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                        Text("Recognizing text…")
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                    }
                }
            }
            Spacer()

            Button(action: {
                deleteItem(item)
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Delete image from history (⌫)")
        }
        .padding(8)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Extracted Text Box

    @ViewBuilder
    private func textBox(for item: ClipboardItemSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Extracted Text")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()

                if let text = currentText, !text.isEmpty {
                    Text("\(text.count) characters")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.2))

                if isExtracting {
                    VStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Extracting text via Apple Vision…")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let text = currentText, !text.isEmpty {
                    ScrollView {
                        Text(text)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "text.badge.xmark")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text("No text detected in this image")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: 200)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Action Footer

    @ViewBuilder
    private func actionFooter(for item: ClipboardItemSummary) -> some View {
        HStack(spacing: 8) {
            // Delete button
            Button(action: {
                deleteItem(item)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                    Text("Delete")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06))
                .foregroundColor(.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Delete this image from history (⌫)")

            // Feedback badge
            if isCopied {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 12))
                    Text("Copied to clipboard!")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.green)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            Spacer()

            if let text = currentText, !text.isEmpty {
                // Paste to frontmost app button (Cmd+Return)
                Button(action: {
                    onSelectText(text, true)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 11))
                        Text("Paste to App")
                            .font(.system(size: 11, weight: .medium))
                        Text("⌘↩")
                            .font(.system(size: 9))
                            .opacity(0.7)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Copy text and paste into the previous application (⌘+Return)")

                // Copy Text Button (Return)
                Button(action: {
                    copyTextToClipboard(text)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 11))
                        Text("Copy Text")
                            .font(.system(size: 11, weight: .semibold))
                        Text("↩")
                            .font(.system(size: 10))
                            .opacity(0.8)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Copy extracted text to clipboard (Return)")
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Actions & Helpers

    func deleteItem(_ item: ClipboardItemSummary) {
        let currentItems = imageItems
        if let currentIndex = currentItems.firstIndex(where: { $0.id == item.id }) {
            if currentItems.count > 1 {
                let nextIndex = (currentIndex + 1 < currentItems.count) ? currentIndex + 1 : currentIndex - 1
                selectedImageID = currentItems[nextIndex].id
            } else {
                selectedImageID = nil
            }
        }
        fullImageCache.removeValue(forKey: item.id)
        onDemandText.removeValue(forKey: item.id)
        onDelete(item)
    }

    func copyCurrentText(paste: Bool) {
        guard let text = currentText, !text.isEmpty else { return }
        if paste {
            onSelectText(text, true)
        } else {
            copyTextToClipboard(text)
        }
    }

    private func copyTextToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) {
            isCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.15)) {
                isCopied = false
            }
        }
    }

    private func performOnDemandOCRIfNeeded() {
        guard let item = activeItem else { return }

        // Load full image for better preview if not yet cached
        if fullImageCache[item.id] == nil {
            DispatchQueue.global(qos: .userInitiated).async {
                if let content = try? viewModel.store.fetchContent(id: item.id),
                   let img = NSImage(data: content) {
                    DispatchQueue.main.async {
                        self.fullImageCache[item.id] = img
                    }
                }
            }
        }

        // Check if OCR is already present
        if item.extractedText != nil || onDemandText[item.id] != nil {
            return
        }

        // Run OCR on-demand
        isExtracting = true
        let itemId = item.id
        DispatchQueue.global(qos: .userInitiated).async {
            guard let content = try? viewModel.store.fetchContent(id: itemId) else {
                DispatchQueue.main.async { self.isExtracting = false }
                return
            }

            let text = TextRecognitionService.recognizeText(from: content)
            if let text, !text.isEmpty {
                try? viewModel.store.updateExtractedText(id: itemId, text: text)
            }

            DispatchQueue.main.async {
                self.onDemandText[itemId] = text ?? ""
                self.isExtracting = false
                self.viewModel.reload()
            }
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func formatRelativeTime(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
