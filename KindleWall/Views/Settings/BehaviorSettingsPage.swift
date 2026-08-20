import SwiftUI

/// "Behavior" — a single scrollable page that gathers the four behavior settings groups
/// (schedule, rotation, long-quote handling, source file) as stacked sections.
///
/// Replaces four separate sidebar destinations whose individual content was too small to
/// justify a full detail pane. Mirrors macOS System Settings, where one sidebar category
/// presents several grouped sections in one scrolling pane.
struct BehaviorSettingsPage: View {
    let viewModel: MainViewModel
    @Bindable var settingsVM: SettingsViewModel
    let actions: SettingsActions

    /// Optional so a preview or a test host without the injection does not trap.
    @Environment(ImportState.self) private var importState: ImportState?

    /// Quotes in the user's pinned books — context shown by the rotation "Pinned Books" scope.
    private var pinnedQuoteCount: Int {
        viewModel.clippings.filter { settingsVM.pinnedBookTitles.contains($0.bookTitle) }.count
    }

    var body: some View {
        SettingsPage(title: "Behavior") {
            SettingsGroup("Schedule") {
                ScheduleSection(settingsVM: settingsVM, actions: actions)
            }

            SettingsGroup("Rotation") {
                // The pinned-quote total is derived inside the section now: it reads it off
                // the same `RotationBook` counts the picker shows, so the two cannot disagree.
                RotationSection(
                    settingsVM: settingsVM,
                    availableBooks: viewModel.availableBooks,
                    totalQuoteCount: viewModel.clippings.count,
                    actions: actions
                )
            }

            SettingsGroup("Long Quotes") {
                LongQuoteSection(settingsVM: settingsVM, actions: actions)
            }

            SettingsGroup("Source File") {
                SourceFileSection(
                    settingsVM: settingsVM,
                    clippingsCount: viewModel.clippings.count,
                    actions: actions,
                    canCheckForNewClippings: viewModel.canCheckForNewClippings,
                    isImporting: importState?.isRunning ?? false
                )
            }
        }
    }
}
