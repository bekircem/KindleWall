import SwiftUI

/// "Genel" page — launch, menu bar, notifications, spaces, and restore-previous-wallpaper.
struct GeneralSettingsPage: View {
    @Bindable var settingsVM: SettingsViewModel
    let canRestorePreviousWallpaper: Bool
    let actions: SettingsActions

    /// Same key the app scene watches, so clearing it swaps the window back to setup at once.
    @AppStorage(Constants.StorageKeys.hasCompletedOnboarding) private var hasCompletedOnboarding = false

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
                    subtitle: "Diğer Mission Control alanları ilk ziyaret edildiklerinde güncellenir."
                ) {
                    Toggle("", isOn: $settingsVM.applyToAllSpaces).labelsHidden()
                }
            }
            // Batched: any of the four general toggles persists settings in one observer.
            .onChange(of: [settingsVM.launchAtLogin, settingsVM.showInMenuBar,
                           settingsVM.showNotifications, settingsVM.applyToAllSpaces]) {
                settingsVM.saveSettings()
            }

            SettingsCard(
                title: "Anında Eşitleme",
                footnote: "Açıkken tüm masaüstleri aynı anda değişir. Bunu yapmanın tek yolu macOS'un kendi duvar kağıdı kaydını yazıp duvar kağıdı servisini yeniden başlatmak — Ayarlar panelinin yaptığı da budur. Biçim Apple tarafından belgelenmemiştir, bu yüzden varsayılan kapalı. İlk kullanımda kaydın yedeği alınır."
            ) {
                SettingsRow(
                    icon: "square.on.square.dashed", iconColor: .orange,
                    title: "Tüm Masaüstlerini Anında Eşitle",
                    subtitle: "Kapalıyken her alan ilk ziyaret edildiğinde güncellenir."
                ) {
                    Toggle("", isOn: $settingsVM.syncAllSpaces).labelsHidden()
                }
            }
            .onChange(of: settingsVM.syncAllSpaces) {
                settingsVM.saveSettings()
                // Apply straight away, so switching the toggle on visibly does something instead
                // of waiting for the next rotation — but re-apply the *same* quote. This used to
                // call `onApplyNow`, which also rolled a new one, so a spaces toggle silently
                // changed which highlight you were reading.
                if settingsVM.syncAllSpaces { actions.onApplyDesignNow() }
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

            SettingsCard(
                title: "Kurulum",
                footnote: "Karşılama akışını yeniden açar. Alıntıların, favorilerin ve ayarların olduğu gibi kalır."
            ) {
                SettingsRow(
                    icon: "sparkles", iconColor: .indigo,
                    title: "Tanıtımı Yeniden Göster"
                ) {
                    Button("Başlat") {
                        hasCompletedOnboarding = false
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}
