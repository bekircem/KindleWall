import SwiftUI

/// "Tasarım" — everything that decides what the wallpaper looks like, on one scrolling page.
///
/// Replaces three sidebar destinations (Stil / Tipografi / Arka Plan). Designing a wallpaper is
/// one task, and splitting it across three pages meant visiting all of them and then a fourth
/// to apply the result. Same consolidation `BehaviorSettingsPage` already did for the four
/// behaviour pages, and the live preview stays pinned alongside the whole thing.
struct DesignSettingsPage: View {
    @Bindable var viewModel: MainViewModel
    @Bindable var settingsVM: SettingsViewModel
    let actions: SettingsActions

    var body: some View {
        SettingsPage(title: "Tasarım") {
            autoApplyCard

            SettingsGroup("Stil") {
                StyleSection(viewModel: viewModel)
            }

            SettingsGroup("Arka Plan") {
                BackgroundSection(viewModel: viewModel, settingsVM: settingsVM, actions: actions)
            }

            SettingsGroup("Tipografi") {
                TypographySection(viewModel: viewModel)
            }
        }
    }

    /// The switch lives here, at the top of the page it governs, rather than buried in Genel —
    /// this is where its effect is visible, so it is where the user will look for it.
    private var autoApplyCard: some View {
        SettingsCard(
            footnote: viewModel.autoApplyDesignChanges
                ? "Değişiklikler kısa bir duraklamadan sonra masaüstüne kendiliğinden uygulanır. Alıntı değişmez — yalnızca görünüm."
                : "Değişiklikler yalnızca önizlemede kalır; masaüstüne yansıması için Uygula'ya bas."
        ) {
            // Short title on purpose. A `SettingsRow`'s title reports its full intrinsic width,
            // and on this page — the only one sharing space with the preview inspector — a long
            // one widened the content column enough to push the sidebar off the window.
            SettingsRow(
                icon: "wand.and.sparkles",
                iconColor: .purple,
                title: "Otomatik Uygula"
            ) {
                Toggle("", isOn: $viewModel.autoApplyDesignChanges)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Değişiklikleri otomatik uygula")
            }
        }
    }
}
