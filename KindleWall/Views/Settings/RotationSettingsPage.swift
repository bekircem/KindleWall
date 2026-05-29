import SwiftUI

/// "Döngü Modu" page — how the next quote is chosen (sequential, random, favorites, pinned books).
///
/// Layout is split into two cards so the segmented mode picker keeps a constant height:
/// a "Mod" card (picker only) and a "Kapsam" card whose content adapts to the selected mode.
/// This avoids the abrupt resize that happened when the pinned-books list lived inside the
/// picker card, and fills the page with meaningful per-mode context.
struct RotationSettingsPage: View {
    @Bindable var settingsVM: SettingsViewModel
    let availableBooks: [(title: String, author: String?)]
    let totalQuoteCount: Int
    let pinnedQuoteCount: Int
    let actions: SettingsActions

    var body: some View {
        SettingsPage(title: "Döngü Modu") {
            // MARK: Mode picker — constant height across all modes.
            SettingsCard(title: "Mod", footnote: modeFootnote) {
                Picker("Mod", selection: Binding(
                    get: { settingsVM.rotationMode },
                    set: {
                        settingsVM.updateRotationMode($0)
                        actions.onRotationModeChanged($0)
                    }
                )) {
                    ForEach(RotationMode.allCases.filter { $0 != .favorites || settingsVM.hasFavorites }) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(Theme.Spacing.l)
            }

            // MARK: Scope — per-mode summary / tools.
            scopeCard
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
        .animation(Theme.Motion.smooth, value: settingsVM.rotationMode)
        .onChange(of: settingsVM.pinnedBookTitles) {
            actions.onPinnedBooksChanged(settingsVM.pinnedBookTitles)
        }
    }

    // MARK: - Scope card

    @ViewBuilder private var scopeCard: some View {
        switch settingsVM.rotationMode {
        case .pinnedBooks:
            SettingsCard(
                title: "Sabit Kitaplar",
                footnote: settingsVM.pinnedBookTitles.isEmpty
                    ? nil
                    : "Seçili kitaplardan \(pinnedQuoteCount) alıntı havuzda."
            ) {
                PinnedBooksSectionView(viewModel: settingsVM, availableBooks: availableBooks)
                    .padding(Theme.Spacing.l)
            }

        case .favorites:
            SettingsCard(title: "Kapsam") {
                statRow(icon: "heart.fill", color: .pink, title: "Favori Alıntı", value: settingsVM.favoriteCount)
            }

        case .allRandom, .bookByBook:
            SettingsCard(title: "Kapsam") {
                statRow(icon: "books.vertical.fill", color: .orange, title: "Kitap", value: availableBooks.count)
                RowDivider()
                statRow(icon: "quote.bubble.fill", color: .indigo, title: "Alıntı", value: totalQuoteCount)
            }
        }
    }

    private func statRow(icon: String, color: Color, title: String, value: Int) -> some View {
        SettingsRow(icon: icon, iconColor: color, title: title) {
            Text("\(value)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Mode description

    /// Dynamic explanation shown under the picker. Folds in the favorites hint when the user
    /// has no favorites yet (the Favoriler segment is hidden in that case).
    private var modeFootnote: String {
        if settingsVM.rotationMode == .favorites {
            return "\(settingsVM.favoriteCount) favori alıntı arasından rastgele seçer."
        }
        var text = settingsVM.rotationMode.modeDescription
        if !settingsVM.hasFavorites {
            text += "\n\nFavoriler modu için Kütüphane'den alıntılara kalp ekleyin."
        }
        return text
    }
}
