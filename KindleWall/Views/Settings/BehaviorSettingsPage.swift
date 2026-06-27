import SwiftUI

/// "Davranış" — a single scrollable page that gathers the four behavior settings groups
/// (schedule, rotation, long-quote handling, source file) as stacked sections.
///
/// Replaces four separate sidebar destinations whose individual content was too small to
/// justify a full detail pane. Mirrors macOS System Settings, where one sidebar category
/// presents several grouped sections in one scrolling pane.
struct BehaviorSettingsPage: View {
    let viewModel: MainViewModel
    @Bindable var settingsVM: SettingsViewModel
    let actions: SettingsActions

    /// Quotes in the user's pinned books — context shown by the rotation "Sabit Kitaplar" scope.
    private var pinnedQuoteCount: Int {
        viewModel.clippings.filter { settingsVM.pinnedBookTitles.contains($0.bookTitle) }.count
    }

    var body: some View {
        SettingsPage(title: "Davranış") {
            BehaviorGroup("Zamanlama") {
                ScheduleSection(settingsVM: settingsVM, actions: actions)
            }

            BehaviorGroup("Döngü Modu") {
                RotationSection(
                    settingsVM: settingsVM,
                    availableBooks: viewModel.availableBooks,
                    totalQuoteCount: viewModel.clippings.count,
                    pinnedQuoteCount: pinnedQuoteCount,
                    actions: actions
                )
            }

            BehaviorGroup("Uzun Alıntılar") {
                LongQuoteSection(settingsVM: settingsVM, actions: actions)
            }

            BehaviorGroup("Kaynak Dosya") {
                SourceFileSection(settingsVM: settingsVM, clippingsCount: viewModel.clippings.count, actions: actions)
            }
        }
    }
}

// MARK: - Behavior Group

/// A labeled group within `BehaviorSettingsPage`: a prominent header above its section content.
/// The header sits one step above `SettingsCard`'s own uppercased titles, giving a clear
/// hierarchy (group → card → row) on the consolidated page.
private struct BehaviorGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.leading, Theme.Spacing.xs)

            content
        }
    }
}
