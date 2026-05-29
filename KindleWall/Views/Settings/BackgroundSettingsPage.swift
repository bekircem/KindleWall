import SwiftUI

/// "Arka Plan" page — custom gradient override for the wallpaper background.
struct BackgroundSettingsPage: View {
    @Bindable var settingsVM: SettingsViewModel
    let actions: SettingsActions

    var body: some View {
        SettingsPage(title: "Arka Plan") {
            SettingsCard(
                title: "Özel Gradient",
                footnote: "Seçili stilin arka planını özel renklerle değiştir. Metin rengi otomatik olarak okunabilirliğe göre ayarlanır."
            ) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    GradientPicker(
                        startColor: $settingsVM.backgroundStartColor,
                        endColor: $settingsVM.backgroundEndColor
                    )

                    HStack {
                        Spacer()
                        Button("Varsayılana Dön") {
                            settingsVM.resetBackgroundGradient()
                            actions.onTypographyChanged()
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .onChange(of: settingsVM.backgroundStartColor) {
                settingsVM.updateBackgroundGradient()
                actions.onTypographyChanged()
            }
            .onChange(of: settingsVM.backgroundEndColor) {
                settingsVM.updateBackgroundGradient()
                actions.onTypographyChanged()
            }
        }
    }
}
