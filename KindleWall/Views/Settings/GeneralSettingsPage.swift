import SwiftUI

/// "General" page — launch, menu bar, notifications, spaces, and restore-previous-wallpaper.
struct GeneralSettingsPage: View {
    @Bindable var settingsVM: SettingsViewModel
    let canRestorePreviousWallpaper: Bool
    let actions: SettingsActions

    /// Same key the app scene watches, so clearing it swaps the window back to setup at once.
    @AppStorage(Constants.StorageKeys.hasCompletedOnboarding) private var hasCompletedOnboarding = false

    var body: some View {
        SettingsPage(title: "General") {
            SettingsCard(footnote: settingsVM.loginItemError) {
                SettingsRow(icon: "power", iconColor: .green, title: "Open at Login") {
                    Toggle("", isOn: $settingsVM.launchAtLogin).labelsHidden()
                }
                RowDivider()
                SettingsRow(icon: "menubar.rectangle", iconColor: .indigo, title: "Show in Menu Bar") {
                    Toggle("", isOn: $settingsVM.showInMenuBar).labelsHidden()
                }
                RowDivider()
                SettingsRow(icon: "bell.fill", iconColor: .red, title: "Send Notifications") {
                    Toggle("", isOn: $settingsVM.showNotifications).labelsHidden()
                }
                RowDivider()
                SettingsRow(
                    icon: "rectangle.on.rectangle", iconColor: .blue,
                    title: "Apply to All Spaces",
                    subtitle: "Other Mission Control spaces update the first time you visit them."
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
                title: "Immediate Sync",
                footnote: "When on, every desktop changes at once. The only way to do that is to write macOS's own wallpaper store and restart the wallpaper service — which is what the Settings panel does too. The format is undocumented by Apple, so this is off by default. The store is backed up before the first write."
            ) {
                SettingsRow(
                    icon: "square.on.square.dashed", iconColor: .orange,
                    title: "Sync All Desktops Immediately",
                    subtitle: "When off, each space updates the first time you visit it."
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

            SettingsCard(title: "Wallpaper") {
                SettingsRow(
                    icon: "arrow.uturn.backward", iconColor: Color(.systemGray),
                    title: "Restore Previous Wallpaper",
                    subtitle: canRestorePreviousWallpaper ? nil : "No wallpaper has been replaced yet"
                ) {
                    Button("Restore") {
                        actions.onRestorePreviousWallpaper()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canRestorePreviousWallpaper)
                }
            }

            SettingsCard(
                title: "Kurulum",
                footnote: "Reopens the welcome flow. Your quotes, favorites and settings stay as they are."
            ) {
                SettingsRow(
                    icon: "sparkles", iconColor: .indigo,
                    title: "Show the Intro Again"
                ) {
                    Button("Begin") {
                        hasCompletedOnboarding = false
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}
