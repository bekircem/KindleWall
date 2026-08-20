import SwiftUI

/// "Schedule" section — how often the wallpaper changes, plus a manual "change now" action.
/// A section of the consolidated `BehaviorSettingsPage` (no `SettingsPage` chrome of its own).
struct ScheduleSection: View {
    @Bindable var settingsVM: SettingsViewModel
    let actions: SettingsActions

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            SettingsCard(
                footnote: String(localized: "Choose how often the wallpaper changes on its own.")
            ) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Picker("Change Interval", selection: Binding(
                        get: { settingsVM.scheduleInterval },
                        set: {
                            settingsVM.updateSchedule($0)
                            actions.onScheduleChanged($0, settingsVM.customScheduleDate)
                        }
                    )) {
                        ForEach(ScheduleInterval.allCases) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    if settingsVM.scheduleInterval == .custom {
                        DatePicker(
                            "Custom Time",
                            selection: $settingsVM.customScheduleDate,
                            displayedComponents: .hourAndMinute
                        )
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .onChange(of: settingsVM.customScheduleDate) {
                actions.onScheduleChanged(settingsVM.scheduleInterval, settingsVM.customScheduleDate)
            }

            Button {
                actions.onApplyNow()
            } label: {
                Label("Change Now", systemImage: "arrow.clockwise.circle")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.glass)
            .help("Picks a new quote using the current rotation and applies it as the wallpaper")
        }
    }
}
