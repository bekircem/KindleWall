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
                                Button {
                                    viewModel.togglePinnedBook(book.title)
                                } label: {
                                    HStack {
                                        Image(systemName: viewModel.isBookPinned(book.title)
                                            ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(viewModel.isBookPinned(book.title)
                                                ? Color.accentColor : Color.secondary)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(book.title)
                                                .font(.callout)
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            if let author = book.author {
                                                Text(author)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
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
