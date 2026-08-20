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
    var onAddManualClipping: (String, String?, String, String?) -> Void = { _, _, _, _ in }
    var onDeleteManualClipping: (Clipping) -> Void = { _ in }
    var onUpdateManualClipping: (Clipping) -> Void = { _ in }
    var existingBooks: [(title: String, author: String?)] = []

    @State private var vm = LibraryViewModel()
    @State private var showEditSheet = false
    @State private var showAddClippingForm = false
    @State private var clippingToEdit: Clipping? = nil
    @State private var clippingToDelete: Clipping? = nil
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
            BookDetailHeader(
                book: displayBook,
                coverImage: coverImage,
                onEdit: { showEditSheet = true },
                onAdd: { showAddClippingForm = true }
            )

            Divider()

            List(book.clippings) { clipping in
                ClippingCard(clipping: clipping, isFavorite: vm.isFavorite(clipping))
                    .contentShape(Rectangle())
                    .onTapGesture { onSelectClipping(clipping) }
                    .contextMenu {
                        Button("Preview") {
                            onSelectClipping(clipping)
                        }
                        Button("Set as Wallpaper") {
                            onApplyClipping(clipping)
                        }
                        .keyboardShortcut(.return, modifiers: .command)
                        Divider()
                        Button(vm.isFavorite(clipping) ? "Remove from Favorites" : "Add to Favorites") {
                            vm.toggleFavorite(clipping)
                        }
                        .keyboardShortcut("d", modifiers: .command)
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(clipping.text, forType: .string)
                        }
                        .keyboardShortcut("c", modifiers: .command)

                        if clipping.isManualEntry {
                            Divider()
                            Button("Edit") {
                                clippingToEdit = clipping
                            }
                            Button("Delete", role: .destructive) {
                                clippingToDelete = clipping
                            }
                        }
                    }
            }
        }
        .navigationTitle(displayBook.displayTitle)
        .onAppear { currentOverride = existingOverride }
        .confirmationDialog(
            "Delete this quote?",
            isPresented: Binding(
                get: { clippingToDelete != nil },
                set: { if !$0 { clippingToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let c = clippingToDelete {
                    onDeleteManualClipping(c)
                    clippingToDelete = nil
                }
            }
        }
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
        .sheet(isPresented: $showAddClippingForm) {
            ManualClippingFormView(
                prefilledBookTitle: book.title,
                existingBooks: existingBooks,
                onSave: { title, author, text, page in
                    onAddManualClipping(title, author, text, page)
                    showAddClippingForm = false
                },
                onCancel: { showAddClippingForm = false }
            )
        }
        .sheet(item: $clippingToEdit) { clipping in
            ManualClippingFormView(
                clippingToEdit: clipping,
                existingBooks: existingBooks,
                onSave: { title, author, text, page in
                    let updated = Clipping(
                        id: clipping.id,
                        bookTitle: title,
                        author: author,
                        text: text,
                        page: page,
                        location: clipping.location,
                        dateAdded: clipping.dateAdded,
                        isManualEntry: true
                    )
                    onUpdateManualClipping(updated)
                    clippingToEdit = nil
                },
                onCancel: { clippingToEdit = nil }
            )
        }
    }
}

// MARK: - Book Detail Header

private struct BookDetailHeader: View {
    let book: Book
    let coverImage: NSImage?
    var onEdit: () -> Void = {}
    var onAdd: () -> Void = {}

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

            Button(action: onAdd) {
                Image(systemName: "plus.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Add a quote to this book by hand")
            .accessibilityLabel("Add quote by hand")

            Button(action: onEdit) {
                Image(systemName: "pencil.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Edit Details")
            .accessibilityLabel("Edit book details")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var statsLine: String {
        var parts: [String] = [String(localized: "\(book.clippingCount) quotes")]
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
