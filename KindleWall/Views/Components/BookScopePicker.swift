import SwiftUI

/// The book chooser for "Sabitler", presented in a popover.
///
/// It used to be a 200pt scroll view nested inside the settings page's own scroll view — two
/// scrollers stacked in the same gesture, in a window too short to read a library through.
/// A popover gives the list the room it needs without the page having to give any up, and
/// keeps the section itself a fixed height.
struct BookScopePicker: View {
    let books: [RotationBook]
    var viewModel: SettingsViewModel

    @State private var search = ""
    @State private var order: BookOrder = .quoteCount
    @FocusState private var searchFocused: Bool

    /// How the list is ordered. Quote count leads because it answers the question the user
    /// actually has — "which of my books have enough highlights to be worth pinning?" — which
    /// no amount of searching by title can answer.
    enum BookOrder: String, CaseIterable, Identifiable {
        case quoteCount, title

        var id: String { rawValue }
        var label: String {
            switch self {
            case .quoteCount: return "Alıntı sayısı"
            case .title:      return "Ad"
            }
        }
    }

    private var visible: [RotationBook] {
        books
            .filter { $0.matches(search) }
            .sorted { lhs, rhs in
                // Pinned first regardless of order, so the current selection never scrolls away.
                let lp = viewModel.isBookPinned(lhs.title), rp = viewModel.isBookPinned(rhs.title)
                if lp != rp { return lp }
                switch order {
                case .quoteCount:
                    return lhs.quoteCount == rhs.quoteCount
                        ? lhs.title < rhs.title
                        : lhs.quoteCount > rhs.quoteCount
                case .title:
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 400, height: 460)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search books or authors…", text: $search)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !search.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") { search = "" }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, 6)
            .background(Theme.Palette.cardFill, in: RoundedRectangle(cornerRadius: Theme.Radius.control))

            Picker("Sort", selection: $order) {
                ForEach(BookOrder.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(Theme.Spacing.m)
        .onAppear { searchFocused = true }
    }

    // MARK: - List

    @ViewBuilder private var list: some View {
        if visible.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(visible) { book in
                        BookScopeRow(
                            book: book,
                            isPinned: viewModel.isBookPinned(book.title)
                        ) {
                            viewModel.togglePinnedBook(book.title)
                        }
                    }
                }
                .padding(Theme.Spacing.s)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Select All") {
                for book in visible where !viewModel.isBookPinned(book.title) {
                    viewModel.togglePinnedBook(book.title)
                }
            }
            .disabled(visible.allSatisfy { viewModel.isBookPinned($0.title) })

            Button("Clear") {
                for book in books where viewModel.isBookPinned(book.title) {
                    viewModel.togglePinnedBook(book.title)
                }
            }
            .disabled(viewModel.pinnedBookTitles.isEmpty)

            Spacer()

            // Both buttons stay in place whatever the state — the pair they replaced swapped
            // position, so the control under the pointer changed meaning as you used it.
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .buttonStyle(.link)
        .font(.callout)
        .padding(Theme.Spacing.m)
    }

    private var summary: String {
        let pinned = books.filter { viewModel.isBookPinned($0.title) }
        guard !pinned.isEmpty else { return "Hiç kitap seçilmedi" }
        let quotes = pinned.reduce(0) { $0 + $1.quoteCount }
        return "\(pinned.count) kitap · \(quotes) alıntı"
    }
}

// MARK: - Row

/// One book in the picker: selection mark, title, author, and the count that makes the choice
/// an informed one.
private struct BookScopeRow: View {
    let book: RotationBook
    let isPinned: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: isPinned ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isPinned ? Theme.Palette.accent : Color.secondary)
                    .font(.body)

                VStack(alignment: .leading, spacing: 1) {
                    Text(book.title)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let author = book.author {
                        Text(author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: Theme.Spacing.s)

                Text("\(book.quoteCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.Palette.cardFill, in: Capsule())
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Shared hover treatment — this row carried its own `@State` copy of it.
        .hoverHighlight(cornerRadius: Theme.Radius.control)
        .accessibilityLabel("\(book.title), \(book.quoteCount) alıntı")
        .accessibilityAddTraits(isPinned ? [.isButton, .isSelected] : .isButton)
    }
}
