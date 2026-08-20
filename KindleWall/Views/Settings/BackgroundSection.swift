import SwiftUI

/// Dynamic (time-of-day) wallpaper and the custom gradient override — the "Background" group
/// of the "Design" page.
struct BackgroundSection: View {
    @Bindable var viewModel: MainViewModel
    @Bindable var settingsVM: SettingsViewModel
    let actions: SettingsActions

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SettingsCard(
                title: "Dynamic Wallpaper",
                footnote: "When on, the wallpaper is written as a six-frame HEIC instead of a single image, and macOS shifts the colors through the day by itself — even while the app is closed. How often the quote changes is a separate setting; this affects colors only."
            ) {
                VStack(spacing: 0) {
                    SettingsRow(
                        icon: "sun.horizon.fill",
                        iconColor: .orange,
                        title: "Shift Colors Through the Day",
                        subtitle: "Separate frames for dawn, sunrise, noon, afternoon, sunset and night"
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
                title: "Custom Gradient",
                footnote: "Replace the selected style's background with colors of your own. The text color adjusts itself for legibility."
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
                        Button("Reset to Default") {
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
            Text("Today's frames")
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
