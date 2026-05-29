import SwiftUI

/// Book-pinning UI shown inside SettingsView when rotation mode is .pinnedBooks.
struct PinnedBooksSectionView: View {
    var viewModel: SettingsViewModel
    let availableBooks: [(title: String, author: String?)]
    @State private var bookSearchText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if availableBooks.isEmpty {
                Text("Henüz alıntı yüklenmedi. Önce bir Clippings dosyası seçin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // ── Arama + Toplu İşlem ──────────────────────────────────────
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        TextField("Kitap ara…", text: $bookSearchText)
                            .textFieldStyle(.plain)
                            .font(.callout)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7)
                        .fill(Color.secondary.opacity(0.1)))

                    if viewModel.pinnedBookTitles.isEmpty {
                        Button("Tümünü Seç") {
                            for book in availableBooks where !viewModel.isBookPinned(book.title) {
                                viewModel.togglePinnedBook(book.title)
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    } else {
                        Button("Seçimi Temizle") {
                            for book in availableBooks where viewModel.isBookPinned(book.title) {
                                viewModel.togglePinnedBook(book.title)
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }

                // ── Kitap Listesi ────────────────────────────────────────────
                let filtered = availableBooks.filter {
                    bookSearchText.isEmpty ||
                    $0.title.localizedCaseInsensitiveContains(bookSearchText) ||
                    ($0.author?.localizedCaseInsensitiveContains(bookSearchText) ?? false)
                }
                let sorted = filtered.sorted {
                    let aSelected = viewModel.isBookPinned($0.title)
                    let bSelected = viewModel.isBookPinned($1.title)
                    if aSelected != bSelected { return aSelected }
                    return $0.title < $1.title
                }

                if sorted.isEmpty {
                    Text("Sonuç bulunamadı.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(sorted, id: \.title) { book in
                                PinnedBookRow(
                                    title: book.title,
                                    author: book.author,
                                    isPinned: viewModel.isBookPinned(book.title)
                                ) {
                                    viewModel.togglePinnedBook(book.title)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.07)))
                }

                // ── Durum satırı ─────────────────────────────────────────────
                if viewModel.pinnedBookTitles.isEmpty {
                    Text("Hiç kitap seçilmedi — tümünden rastgele gösterilecek.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else {
                    Text("\(viewModel.pinnedBookTitles.count) kitap seçildi.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Pinned Book Row

/// A single selectable book row with a hover highlight and accessibility traits.
private struct PinnedBookRow: View {
    let title: String
    let author: String?
    let isPinned: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isPinned ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let author {
                        Text(author)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(
                isHovered ? Color.primary.opacity(0.06) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isPinned ? [.isButton, .isSelected] : .isButton)
    }
}
