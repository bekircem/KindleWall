import SwiftUI

/// "Genel" page — launch, menu bar, notifications, spaces, and restore-previous-wallpaper.
struct GeneralSettingsPage: View {
    @Bindable var settingsVM: SettingsViewModel
    let canRestorePreviousWallpaper: Bool
    let actions: SettingsActions

    var body: some View {
        SettingsPage(title: "Genel") {
            SettingsCard(footnote: settingsVM.loginItemError) {
                SettingsRow(icon: "power", iconColor: .green, title: "Başlangıçta Aç") {
                    Toggle("", isOn: $settingsVM.launchAtLogin).labelsHidden()
                }
                RowDivider()
                SettingsRow(icon: "menubar.rectangle", iconColor: .indigo, title: "Menü Çubuğunda Göster") {
                    Toggle("", isOn: $settingsVM.showInMenuBar).labelsHidden()
                }
                RowDivider()
                SettingsRow(icon: "bell.fill", iconColor: .red, title: "Bildirim Gönder") {
                    Toggle("", isOn: $settingsVM.showNotifications).labelsHidden()
                }
                RowDivider()
                SettingsRow(
                    icon: "rectangle.on.rectangle", iconColor: .blue,
                    title: "Tüm Alanlara Uygula",
                    subtitle: "Mission Control'deki tüm çalışma alanlarının duvar kağıdını değiştirir."
                ) {
                    Toggle("", isOn: $settingsVM.applyToAllSpaces).labelsHidden()
                }
            }
            // Batched: any of the four general toggles persists settings in one observer.
            .onChange(of: [settingsVM.launchAtLogin, settingsVM.showInMenuBar,
                           settingsVM.showNotifications, settingsVM.applyToAllSpaces]) {
                settingsVM.saveSettings()
            }

            SettingsCard(title: "Duvar Kağıdı") {
                SettingsRow(
                    icon: "arrow.uturn.backward", iconColor: Color(.systemGray),
                    title: "Önceki Duvar Kağıdına Dön",
                    subtitle: canRestorePreviousWallpaper ? nil : "Henüz değiştirilmiş bir duvar kağıdı yok"
                ) {
                    Button("Geri Yükle") {
                        actions.onRestorePreviousWallpaper()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canRestorePreviousWallpaper)
                }
            }
        }
    }
}
