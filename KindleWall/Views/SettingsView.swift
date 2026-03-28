import SwiftUI

/// Application settings panel.
struct SettingsView: View {
    var onFileSelected: (URL) -> Void
    var onStyleChanged: (WallpaperStyle) -> Void

    @State private var viewModel = SettingsViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // MARK: - Dosya
                settingsSection("Dosya") {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("My Clippings.txt")
                                .font(.headline)
                            if let path = viewModel.clippingsFilePath {
                                Text(path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } else {
                                Text("Henüz dosya seçilmedi")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Button("Dosya Seç") {
                            if let url = viewModel.selectClippingsFile() {
                                onFileSelected(url)
                            }
                        }

                        Button {
                            if let url = viewModel.selectClippingsFile() {
                                onFileSelected(url)
                            }
                        } label: {
                            Image(systemName: Constants.Icons.refresh)
                        }
                        .help("Yeniden Yükle")
                    }
                }

                // MARK: - Zamanlama
                settingsSection("Zamanlama") {
                    Picker("Değişim Sıklığı", selection: Binding(
                        get: { viewModel.scheduleInterval },
                        set: { viewModel.updateSchedule($0) }
                    )) {
                        ForEach(ScheduleInterval.allCases) { interval in
                            Text(interval.rawValue).tag(interval)
                        }
                    }
                    .pickerStyle(.segmented)

                    if viewModel.scheduleInterval == .custom {
                        DatePicker("Özel Zaman", selection: $viewModel.customScheduleDate, displayedComponents: .hourAndMinute)
                    }
                }

                // MARK: - Stil
                settingsSection("Wallpaper Stili") {
                    StylePickerView(
                        selectedStyle: Binding(
                            get: { viewModel.selectedStyle },
                            set: {
                                viewModel.updateStyle($0)
                                onStyleChanged($0)
                            }
                        )
                    )
                }

                // MARK: - Genel
                settingsSection("Genel") {
                    Toggle("Başlangıçta Aç", isOn: $viewModel.launchAtLogin)
                    Toggle("Menü Çubuğunda Göster", isOn: $viewModel.showInMenuBar)
                    Toggle("Bildirim Gönder", isOn: $viewModel.showNotifications)
                }

                // MARK: - Hakkında
                settingsSection("Hakkında") {
                    HStack {
                        Text("KindleWall")
                            .font(.headline)
                        Text("v\(Constants.App.version)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .onChange(of: viewModel.launchAtLogin) { _, _ in viewModel.saveSettings() }
        .onChange(of: viewModel.showInMenuBar) { _, _ in viewModel.saveSettings() }
        .onChange(of: viewModel.showNotifications) { _, _ in viewModel.saveSettings() }
    }

    @ViewBuilder
    private func settingsSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background))
    }
}
