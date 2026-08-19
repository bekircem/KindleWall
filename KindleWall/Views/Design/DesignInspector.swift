import SwiftUI

/// The design editor's trailing control panel: one tab's controls at a time, over a fixed
/// footer for the apply mode.
///
/// The three sections themselves are unchanged — `StyleSection`, `TypographySection` and
/// `BackgroundSection` keep every binding they had on the old page. What changed is that only
/// one of them is mounted at a time, so the panel's height is set by the group you are editing
/// instead of by all three stacked together.
struct DesignInspector: View {
    @Bindable var viewModel: MainViewModel
    @Bindable var settingsVM: SettingsViewModel
    let actions: SettingsActions
    @Binding var tab: DesignTab

    var body: some View {
        VStack(spacing: 0) {
            tabPicker

            Divider()

            ScrollView {
                content
                    .padding(Theme.Spacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)

            Divider()

            autoApplyFooter
        }
        .background(.background)
    }

    // MARK: - Tabs

    private var tabPicker: some View {
        Picker("Düzenlenen bölüm", selection: $tab) {
            ForEach(DesignTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(Theme.Spacing.m)
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .style:
            StyleSection(viewModel: viewModel)
        case .typography:
            TypographySection(viewModel: viewModel)
        case .background:
            BackgroundSection(viewModel: viewModel, settingsVM: settingsVM, actions: actions)
        }
    }

    // MARK: - Footer

    /// Pinned rather than scrolled with a tab: it governs every tab, so it must not be
    /// something you have to scroll a particular one to the bottom to find.
    private var autoApplyFooter: some View {
        Toggle(isOn: $viewModel.autoApplyDesignChanges) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Otomatik Uygula")
                Text(viewModel.autoApplyDesignChanges
                     ? "Değişiklikler kısa bir duraklamadan sonra masaüstüne geçer."
                     : "Değişiklikler önizlemede kalır; Uygula'ya basman gerekir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .padding(Theme.Spacing.l)
    }
}
