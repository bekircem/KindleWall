import SwiftUI

/// "Arka Plan" page — dynamic (time-of-day) wallpaper, and a custom gradient override.
struct BackgroundSettingsPage: View {
    @Bindable var settingsVM: SettingsViewModel
    let actions: SettingsActions

    var body: some View {
        SettingsPage(title: "Arka Plan") {
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
                actions.onApplyNow()
            }

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

/// Shows the actual times today's frames are anchored to.
///
/// The times come from the day's real sunrise and sunset, so they shift with the season — which
/// is invisible unless it is shown. Location is derived from the system time zone; no Location
/// Services permission is involved.
private struct SolarScheduleRow: View {
    private let phases: [SolarPhaseTime] = SunCalculator()
        .phases(for: Date(), at: GeoCoordinate.fromSystemTimeZone())

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
