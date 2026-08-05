import SwiftUI

/// "Stil" page — pick the wallpaper rendering style.
struct StyleSettingsPage: View {
    var viewModel: MainViewModel
    @Bindable var settingsVM: SettingsViewModel
    let actions: SettingsActions

    var body: some View {
        SettingsPage(title: "Stil") {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader("Wallpaper Stili")

                StylePickerView(selectedStyle: Binding(
                    get: { settingsVM.selectedStyle },
                    set: { style in
                        settingsVM.updateStyle(style)
                        // Applies the style's own font + decoration, which is what makes the
                        // styles feel distinct — and records an undo for it.
                        actions.onStyleChanged(style)
                        settingsVM.reloadTypographyFromStorage()
                    }
                ))

                if let undo = viewModel.styleTypographyUndo {
                    StyleTypographyUndoBanner(styleName: undo.styleName) {
                        viewModel.undoStyleTypography()
                        settingsVM.reloadTypographyFromStorage()
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Text("Alıntılarının render edileceği görsel stili seç. Her stil kendi yazı tipi ve süslemesiyle gelir; Tipografi sayfasından sonradan değiştirebilirsin.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, Theme.Spacing.xs)
                    .padding(.top, Theme.Spacing.xs)
            }
            .animation(Theme.Motion.snappy, value: viewModel.styleTypographyUndo)
        }
    }
}

/// Tells the user a style change rewrote their typography, and offers to put it back.
/// Without this the change would be silent and irreversible — the main objection to letting
/// styles carry their own type.
private struct StyleTypographyUndoBanner: View {
    let styleName: String
    let undo: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "textformat")
                .foregroundStyle(.secondary)

            Text("Tipografi \"\(styleName)\" varsayılanına ayarlandı")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer(minLength: Theme.Spacing.s)

            Button("Geri al", action: undo)
                .buttonStyle(.link)
                .font(.callout)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
    }
}
