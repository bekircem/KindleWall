import SwiftUI

/// "Zamanlama" section — how often the wallpaper changes, plus a manual "change now" action.
/// A section of the consolidated `BehaviorSettingsPage` (no `SettingsPage` chrome of its own).
struct ScheduleSection: View {
    @Bindable var settingsVM: SettingsViewModel
    let actions: SettingsActions

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            SettingsCard(
                footnote: "Duvar kağıdının otomatik olarak ne sıklıkla değişeceğini seç."
            ) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Picker("Değişim Sıklığı", selection: Binding(
                        get: { settingsVM.scheduleInterval },
                        set: {
                            settingsVM.updateSchedule($0)
                            actions.onScheduleChanged($0, settingsVM.customScheduleDate)
                        }
                    )) {
                        ForEach(ScheduleInterval.allCases) { interval in
                            Text(interval.rawValue).tag(interval)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    if settingsVM.scheduleInterval == .custom {
                        DatePicker(
                            "Özel Zaman",
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
                Label("Şimdi Değiştir", systemImage: "arrow.clockwise.circle")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.glass)
            .help("Mevcut döngü moduna göre yeni alıntı seçer ve wallpaper olarak uygular")
        }
    }
}
