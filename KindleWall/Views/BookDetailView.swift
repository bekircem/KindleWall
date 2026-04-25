import SwiftUI

/// Shows all clippings for a selected book.
struct BookDetailView: View {
    let book: Book
    let coverImage: NSImage?
    var onSelectClipping: (Clipping) -> Void
    var onApplyClipping: (Clipping) -> Void = { _ in }
    var existingOverride: BookMetadataOverride? = nil
    var onSave: (BookMetadataOverride) -> Void = { _ in }
    var onReset: () -> Void = {}

    @State private var vm = LibraryViewModel()
    @State private var showEditSheet = false
    @State private var currentOverride: BookMetadataOverride?

    /// Book with the current (possibly just-saved) override applied for reactive display.
    private var displayBook: Book {
        Book(
            title: book.title,
            author: book.author,
            clippings: book.clippings,
            displayTitle: currentOverride?.displayTitle,
            displayAuthor: currentOverride?.displayAuthor
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            BookDetailHeader(book: displayBook, coverImage: coverImage, onEdit: { showEditSheet = true })

            Divider()

            List(book.clippings) { clipping in
                ClippingCard(clipping: clipping, isFavorite: vm.isFavorite(clipping))
                    .contentShape(Rectangle())
                    .onTapGesture { onSelectClipping(clipping) }
                    .contextMenu {
                        Button("Önizle") {
                            onSelectClipping(clipping)
                        }
                        Button("Wallpaper Yap") {
                            onApplyClipping(clipping)
                        }
                        .keyboardShortcut(.return, modifiers: .command)
                        Divider()
                        Button(vm.isFavorite(clipping) ? "Favorilerden Çıkar" : "Favorilere Ekle") {
                            vm.toggleFavorite(clipping)
                        }
                        .keyboardShortcut("d", modifiers: .command)
                        Button("Kopyala") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(clipping.text, forType: .string)
                        }
                        .keyboardShortcut("c", modifiers: .command)
                    }
            }
        }
        .navigationTitle(displayBook.displayTitle)
        .onAppear { currentOverride = existingOverride }
        .sheet(isPresented: $showEditSheet) {
            BookMetadataEditView(
                book: book,
                existingOverride: currentOverride,
                onSave: { override in
                    currentOverride = override
                    onSave(override)
                },
                onReset: {
                    currentOverride = nil
                    onReset()
                }
            )
        }
    }
}

// MARK: - Book Detail Header

private struct BookDetailHeader: View {
    let book: Book
    let coverImage: NSImage?
    var onEdit: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            BookCoverView(
                bookTitle: book.title,
                author: book.author,
                coverImage: coverImage,
                width: 72,
                cornerRadius: 8
            )
            .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 4) {
                Text(book.displayTitle)
                    .font(.title3)
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let author = book.displayAuthor {
                    Text(author)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(statsLine)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)

            Button(action: onEdit) {
                Image(systemName: "pencil.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Metadata Düzenle")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var statsLine: String {
        var parts: [String] = ["\(book.clippingCount) alıntı"]
        if let range = dateRangeLabel { parts.append(range) }
        return parts.joined(separator: "  ·  ")
    }

    private var dateRangeLabel: String? {
        let fmt = Date.FormatStyle().month(.abbreviated).year()
        guard let earliest = book.earliestDate, let latest = book.latestDate else { return nil }
        let start = earliest.formatted(fmt)
        let end   = latest.formatted(fmt)
        return start == end ? start : "\(start) – \(end)"
    }
}
