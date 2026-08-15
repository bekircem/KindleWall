import SwiftUI

/// Dynamic (time-of-day) wallpaper and the custom gradient override — the "Arka Plan" group
/// of the "Tasarım" page.
struct BackgroundSection: View {
    @Bindable var viewModel: MainViewModel
    @Bindable var settingsVM: SettingsViewModel
    let actions: SettingsActions

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SettingsCard(
                title: "Dinamik Duvar Kağıdı",
                footnote: "Açıkken duvar kağıdı tek bir görüntü yerine altı kareli bir HEIC olarak yazılır ve macOS gün içinde renkleri kendisi değiştirir — uygulama kapalıyken bile. Alıntının ne sıklıkla değişeceği ayrı bir ayar; bu yalnızca renkleri etkiler."
            ) {
                VStack(spacing: 0) {
                    SettingsRow(
                        icon: "sun.horizon.fill",
                        iconColor: .orange,
                        title: "Gün İçinde Renkler Değişsin",
                        subtitle: "Şafak, gündoğumu, öğlen, ikindi, günbatımı ve gece için ayrı kareler"
                    ) {
                        Toggle("", isOn: $settingsVM.dynamicWallpaperEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    if settingsVM.dynamicWallpaperEnabled {
                        RowDivider()
                        SolarScheduleRow()
                    }
                }
            }
            .onChange(of: settingsVM.dynamicWallpaperEnabled) {
                settingsVM.updateDynamicWallpaperEnabled()
                // Through the design funnel, not `onApplyNow` — that one also picks a new
                // quote, so turning this toggle on used to jump you to a different highlight.
                viewModel.externalDesignSettingChanged()
            }

            SettingsCard(
                title: "Özel Gradient",
                footnote: "Seçili stilin arka planını özel renklerle değiştir. Metin rengi otomatik olarak okunabilirliğe göre ayarlanır."
            ) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    // Bound straight to the owner: the setter persists and refreshes the
                    // preview itself, so the page no longer needs onChange observers that
                    // wrote the gradient a second time.
                    GradientPicker(
                        startColor: $viewModel.backgroundStartColor,
                        endColor: $viewModel.backgroundEndColor
                    )

                    HStack {
                        Spacer()
                        Button("Varsayılana Dön") {
                            viewModel.resetBackgroundGradient()
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(!viewModel.hasCustomGradient)
                    }
                }
                .padding(Theme.Spacing.l)
            }
        }
    }
}

/// Shows the actual times today's frames are anchored to.
///
/// The times come from the day's real sunrise and sunset, so they shift with the season — which
/// is invisible unless it is shown. Location is derived from the system time zone; no Location
/// Services permission is involved.
private struct SolarScheduleRow: View {
    /// Computed, not stored: as a `let` it was fixed when the view struct was first built, so
    /// leaving the app open past midnight left yesterday's times on screen.
    private var phases: [SolarPhaseTime] {
        SunCalculator().phases(for: Date(), at: GeoCoordinate.fromSystemTimeZone())
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Bugünün kareleri")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: Theme.Spacing.m) {
                ForEach(phases, id: \.phase) { phaseTime in
                    VStack(spacing: 2) {
                        Text(phaseTime.phase.displayName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(Self.formatter.string(from: phaseTime.date))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
