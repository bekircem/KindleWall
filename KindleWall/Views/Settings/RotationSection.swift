import SwiftUI

/// "Rotation" — how the next quote is chosen, and what pool it comes from.
///
/// Two cards: the modes with their explanations, and a scope card whose content follows the
/// selected mode. Neither scrolls; the book chooser that used to scroll inside this page now
/// opens as a popover.
struct RotationSection: View {
    @Bindable var settingsVM: SettingsViewModel
    let availableBooks: [RotationBook]
    let totalQuoteCount: Int
    let actions: SettingsActions

    @State private var isPickingBooks = false

    private var pinnedBooks: [RotationBook] {
        availableBooks.filter { settingsVM.isBookPinned($0.title) }
    }

    private var pinnedQuoteCount: Int {
        pinnedBooks.reduce(0) { $0 + $1.quoteCount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            RotationModeCard(settingsVM: settingsVM, actions: actions)

            scopeCard
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
        .animation(Theme.Motion.smooth, value: settingsVM.rotationMode)
        .onChange(of: settingsVM.pinnedBookTitles) {
            actions.onPinnedBooksChanged(settingsVM.pinnedBookTitles)
        }
    }

    // MARK: - Scope

    @ViewBuilder private var scopeCard: some View {
        switch settingsVM.rotationMode {
        case .pinnedBooks:
            SettingsCard(title: "Pinned Books", footnote: pinnedFootnote) {
                pinnedScope.padding(Theme.Spacing.l)
            }

        case .favorites:
            SettingsCard(title: "Scope") {
                statRow(icon: "heart.fill", title: "Favorite Quotes", value: settingsVM.favoriteCount)
            }

        case .allRandom, .bookByBook:
            SettingsCard(title: "Scope") {
                statRow(icon: "books.vertical.fill", title: "Books", value: availableBooks.count)
                RowDivider()
                statRow(icon: "quote.bubble.fill", title: "Quote", value: totalQuoteCount)
            }
        }
    }

    @ViewBuilder private var pinnedScope: some View {
        if availableBooks.isEmpty {
            Text("No quotes loaded yet. Choose a My Clippings.txt file first.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                if pinnedBooks.isEmpty {
                    Label("No books selected — quotes will come from all books for now.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                } else {
                    // Chips rather than a list: the selection is the thing you glance at, and
                    // each one removes itself in a click without opening the chooser.
                    FlowLayout {
                        ForEach(pinnedBooks) { book in
                            chip(for: book)
                        }
                    }
                }

                HStack {
                    Button("Choose Books…") { isPickingBooks = true }
                        .popover(isPresented: $isPickingBooks, arrowEdge: .bottom) {
                            BookScopePicker(books: availableBooks, viewModel: settingsVM)
                        }

                    Spacer()

                    if !pinnedBooks.isEmpty {
                        Text(verbatim: "\(String(localized: "\(pinnedBooks.count) books")) · \(String(localized: "\(pinnedQuoteCount) quotes"))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    /// A removable pinned book. Shows its quote count, so the pool's makeup is readable
    /// without opening anything.
    private func chip(for book: RotationBook) -> some View {
        Button {
            settingsVM.togglePinnedBook(book.title)
        } label: {
            HStack(spacing: 5) {
                Text(book.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(book.quoteCount)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.leading, Theme.Spacing.m)
            .padding(.trailing, Theme.Spacing.s)
            .padding(.vertical, 5)
            // Capped so one long title cannot claim a whole line to itself.
            .frame(maxWidth: 240)
            .background(Theme.Palette.cardFill, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.Palette.cardStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("\(book.title) — remove from the list")
        .accessibilityLabel("\(book.title), \(String(localized: "\(book.quoteCount) quotes")). \(String(localized: "Click to remove it from the list"))")
    }

    private func statRow(icon: String, title: LocalizedStringKey, value: Int) -> some View {
        SettingsRow(icon: icon, iconColor: Theme.Palette.neutralTile, title: title) {
            Text("\(value)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private var pinnedFootnote: String? {
        guard !availableBooks.isEmpty else { return nil }
        return pinnedBooks.isEmpty
            ? "The books you pick show up here; click one to remove it."
            : String(localized: "Quotes are drawn only from these \(pinnedBooks.count) books.")
    }
}
