import SwiftUI

/// Displays the book library with list and card view modes.
/// Tapping a book navigates to its clippings via NavigationStack.
struct LibraryView: View {
    let clippings: [Clipping]
    var onSelectClipping: (Clipping) -> Void
    var onApplyClipping: (Clipping) -> Void = { _ in }
    var onAddManualClipping: (String, String?, String, String?) -> Void = { _, _, _, _ in }
    var onDeleteManualClipping: (Clipping) -> Void = { _ in }
    var onUpdateManualClipping: (Clipping) -> Void = { _ in }

    @State private var viewModel = LibraryViewModel()
    @State private var coverService = BookCoverService()
    @State private var bookToEdit: Book? = nil
    @State private var showAddClippingForm = false

    private var filteredBooks: [Book] { viewModel.filteredBooks(from: clippings) }

    var body: some View {
        Group {
            if filteredBooks.isEmpty {
                ContentUnavailableView(
                    clippings.isEmpty ? "Kitap bulunamadı" : "Sonuç yok",
                    systemImage: "books.vertical",
                    description: Text(clippings.isEmpty
                        ? "Önce bir My Clippings.txt dosyası yükleyin."
                        : "Arama kriterlerinize uygun kitap yok.")
                )
            } else if viewModel.viewMode == .list {
                List(filteredBooks) { book in
                    NavigationLink(value: book) {
                        BookListRow(
                            book: book,
                            hasFavorite: viewModel.hasFavorite(book),
                            coverImage: coverService.loadedCovers[book.id],
                            onRefreshCover: { Task { await coverService.refreshCover(for: book) } },
                            onEdit: { bookToEdit = book }
                        )
                    }
                    .task(id: book.id) {
                        _ = await coverService.cover(for: book)
                    }
                }
                .navigationDestination(for: Book.self) { book in
                    BookDetailView(
                        book: book,
                        coverImage: coverService.loadedCovers[book.id],
                        onSelectClipping: onSelectClipping,
                        onApplyClipping: onApplyClipping,
                        existingOverride: viewModel.metadataOverrides[book.title],
                        onSave: { override in viewModel.saveMetadataOverride(override) },
                        onReset: { viewModel.removeMetadataOverride(forTitle: book.title) },
                        onAddManualClipping: onAddManualClipping,
                        onDeleteManualClipping: onDeleteManualClipping,
                        onUpdateManualClipping: onUpdateManualClipping,
                        existingBooks: uniqueBooks(from: clippings)
                    )
                }
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 14)],
                        spacing: 14
                    ) {
                        ForEach(filteredBooks) { book in
                            NavigationLink(value: book) {
                                BookGridCard(
                                    book: book,
                                    hasFavorite: viewModel.hasFavorite(book),
                                    coverImage: coverService.loadedCovers[book.id],
                                    onRefreshCover: { Task { await coverService.refreshCover(for: book) } },
                                    onEdit: { bookToEdit = book }
                                )
                            }
                            .buttonStyle(.plain)
                            .task(id: book.id) {
                                _ = await coverService.cover(for: book)
                            }
                        }
                    }
                    .padding()
                }
                .navigationDestination(for: Book.self) { book in
                    BookDetailView(
                        book: book,
                        coverImage: coverService.loadedCovers[book.id],
                        onSelectClipping: onSelectClipping,
                        onApplyClipping: onApplyClipping,
                        existingOverride: viewModel.metadataOverrides[book.title],
                        onSave: { override in viewModel.saveMetadataOverride(override) },
                        onReset: { viewModel.removeMetadataOverride(forTitle: book.title) },
                        onAddManualClipping: onAddManualClipping,
                        onDeleteManualClipping: onDeleteManualClipping,
                        onUpdateManualClipping: onUpdateManualClipping,
                        existingBooks: uniqueBooks(from: clippings)
                    )
                }
            }
        }
        .navigationTitle("Kütüphane")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddClippingForm = true
                } label: {
                    Label("Alıntı Ekle", systemImage: "plus")
                }
                .help("Manuel alıntı ekle (⇧⌘N)")
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            ToolbarItemGroup(placement: .secondaryAction) {
                // View mode toggle
                Picker("Görünüm", selection: $viewModel.viewMode) {
                    Image(systemName: "list.bullet").tag(LibraryViewMode.list)
                    Image(systemName: "square.grid.2x2").tag(LibraryViewMode.card)
                }
                .pickerStyle(.segmented)
                .help("Görünüm modunu değiştir")

                Toggle(isOn: $viewModel.showFavoritesOnly) {
                    Image(systemName: viewModel.showFavoritesOnly ? Constants.Icons.favoriteFilled : Constants.Icons.favorite)
                }
                .toggleStyle(.button)
                .help("Favorili kitapları göster")
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Kitap ara…")
        .sheet(item: $bookToEdit) { book in
            BookMetadataEditView(
                book: book,
                existingOverride: viewModel.metadataOverrides[book.title],
                onSave: { override in viewModel.saveMetadataOverride(override) },
                onReset: { viewModel.removeMetadataOverride(forTitle: book.title) }
            )
        }
        .sheet(isPresented: $showAddClippingForm) {
            ManualClippingFormView(
                existingBooks: uniqueBooks(from: clippings),
                onSave: { title, author, text, page in
                    onAddManualClipping(title, author, text, page)
                    showAddClippingForm = false
                },
                onCancel: { showAddClippingForm = false }
            )
        }
    }

    private func uniqueBooks(from clippings: [Clipping]) -> [(title: String, author: String?)] {
        var seen = Set<String>()
        return clippings.compactMap { c in
            guard !seen.contains(c.bookTitle) else { return nil }
            seen.insert(c.bookTitle)
            return (title: c.bookTitle, author: c.author)
        }.sorted { $0.title < $1.title }
    }
}

// MARK: - Book List Row

private struct BookListRow: View {
    let book: Book
    var hasFavorite: Bool
    var coverImage: NSImage? = nil
    var onRefreshCover: () -> Void = {}
    var onEdit: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            BookCoverView(bookTitle: book.title, author: book.author, coverImage: coverImage, width: 44, cornerRadius: 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(book.displayTitle)
                    .font(.body)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                if let author = book.displayAuthor {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Text("\(book.clippingCount) alıntı")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if let date = book.latestDate {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(date, format: .dateTime.month(.abbreviated).year())
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if hasFavorite {
                Image(systemName: Constants.Icons.favoriteFilled)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Düzenle") { onEdit() }
            Divider()
            Button("Kapağı Yenile") { onRefreshCover() }
        }
    }
}

// MARK: - Book Grid Card

/// Full-portrait book card. The entire card IS the cover — info is overlaid at the bottom
/// so all cards share the same 2:3 aspect ratio regardless of title length.
private struct BookGridCard: View {
    let book: Book
    var hasFavorite: Bool
    var coverImage: NSImage? = nil
    var onRefreshCover: () -> Void = {}
    var onEdit: () -> Void = {}

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full portrait cover — real image or gradient fallback
            if let img = coverImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                BookCoverColors.gradient(for: book.title)

                // Large translucent initials — only shown when no real cover
                Text(BookCoverColors.initials(for: book.title))
                    .font(.system(size: 48, weight: .bold, design: .serif))
                    .foregroundColor(.white.opacity(0.25))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Gradient fade + info overlay at bottom
            VStack(spacing: 0) {
                // Fade from transparent to black
                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 70)

                // Info strip
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.displayTitle)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let author = book.displayAuthor {
                        Text(author)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                    }

                    HStack(spacing: 4) {
                        Text("\(book.clippingCount) alıntı")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.55))

                        if let date = book.latestDate {
                            Text("·")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.55))
                            Text(date, format: .dateTime.month(.abbreviated).year())
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.55))
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.72))
            }
        }
        .aspectRatio(2/3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .topTrailing) {
            if hasFavorite {
                Image(systemName: Constants.Icons.favoriteFilled)
                    .foregroundStyle(.white)
                    .font(.caption)
                    .padding(8)
                    .background(.black.opacity(0.3), in: Circle())
                    .padding(6)
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 5, x: 0, y: 3)
        .contextMenu {
            Button("Düzenle") { onEdit() }
            Divider()
            Button("Kapağı Yenile") { onRefreshCover() }
        }
    }
}
