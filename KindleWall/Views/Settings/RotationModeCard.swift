import SwiftUI

/// The four rotation modes as a list of described choices.
///
/// They were a segmented control with a single footnote underneath, so the only way to learn
/// what a mode did was to switch to it and read — which also changed the setting. As rows all
/// four explanations are on screen at once and reading costs nothing.
struct RotationModeCard: View {
    @Bindable var settingsVM: SettingsViewModel
    let actions: SettingsActions

    var body: some View {
        SettingsCard {
            VStack(spacing: 0) {
                ForEach(Array(RotationMode.allCases.enumerated()), id: \.element) { index, mode in
                    if index > 0 { RowDivider() }
                    row(for: mode)
                }
            }
        }
    }

    private func row(for mode: RotationMode) -> some View {
        let isSelected = settingsVM.rotationMode == mode
        // Favorites used to be filtered out of the picker entirely when nothing was
        // favorited, which hid the feature from exactly the people who had not found it yet.
        // Disabled and explained beats absent.
        let isAvailable = mode != .favorites || settingsVM.hasFavorites

        return Button {
            settingsVM.updateRotationMode(mode)
            actions.onRotationModeChanged(mode)
        } label: {
            SettingsRow(
                icon: mode.icon,
                // One hue for the group, because these are four alternatives rather than four
                // categories; the accent marks which one is live.
                iconColor: isSelected ? Theme.Palette.accent : Theme.Palette.neutralTile,
                title: mode.displayName,
                subtitle: isAvailable
                    ? mode.modeDescription
                    : "Kullanmak için önce Kütüphane'den alıntılara kalp ekle."
            ) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Palette.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .hoverHighlight(cornerRadius: Theme.Radius.control)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
