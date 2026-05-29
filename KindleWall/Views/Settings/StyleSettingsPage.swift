import SwiftUI

/// "Stil" page — pick the wallpaper rendering style.
struct StyleSettingsPage: View {
    @Bindable var settingsVM: SettingsViewModel
    let actions: SettingsActions

    var body: some View {
        SettingsPage(title: "Stil") {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader("Wallpaper Stili")

                StylePickerView(selectedStyle: Binding(
                    get: { settingsVM.selectedStyle },
                    set: {
                        settingsVM.updateStyle($0)
                        actions.onStyleChanged($0)
                    }
                ))

                Text("Alıntılarının render edileceği görsel stili seç. Renkleri Arka Plan sayfasından özelleştirebilirsin.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, Theme.Spacing.xs)
                    .padding(.top, Theme.Spacing.xs)
            }
        }
    }
}
