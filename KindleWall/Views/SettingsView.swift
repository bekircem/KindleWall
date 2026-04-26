import SwiftUI

/// Application settings panel.
struct SettingsView: View {
    var clippingsCount: Int
    var canRestorePreviousWallpaper: Bool = false
    var availableBooks: [(title: String, author: String?)] = []
    var onFileSelected: (URL) -> Void
    var onStyleChanged: (WallpaperStyle) -> Void
    var onTypographyChanged: (() -> Void)? = nil
    var onScheduleChanged: ((ScheduleInterval, Date?) -> Void)? = nil
    var onRotationModeChanged: ((RotationMode) -> Void)? = nil
    var onPinnedBooksChanged: ((Set<String>) -> Void)? = nil
    var onRestorePreviousWallpaper: () -> Void = {}
    var onApplyNow: () -> Void = {}

    @State private var viewModel = SettingsViewModel()
    @State private var accessibilityGranted = AXIsProcessTrusted()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // MARK: - Dosya
                settingsSection("Dosya") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("My Clippings.txt")
                                .font(.headline)
                            if let path = viewModel.clippingsFilePath {
                                Text(path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if clippingsCount > 0 {
                                    Text("\(clippingsCount) alıntı yüklendi")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
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
                        set: {
                            viewModel.updateSchedule($0)
                            onScheduleChanged?($0, viewModel.customScheduleDate)
                        }
                    )) {
                        ForEach(ScheduleInterval.allCases) { interval in
                            Text(interval.rawValue).tag(interval)
                        }
                    }
                    .pickerStyle(.segmented)

                    if viewModel.scheduleInterval == .custom {
                        DatePicker("Özel Zaman", selection: $viewModel.customScheduleDate, displayedComponents: .hourAndMinute)
                    }

                    HStack {
                        Spacer()
                        Button {
                            onApplyNow()
                        } label: {
                            Label("Şimdi Değiştir", systemImage: "arrow.clockwise.circle")
                        }
                        .help("Mevcut döngü moduna göre yeni alıntı seçer ve wallpaper olarak uygular")
                    }
                }

                // MARK: - Döngü Modu
                settingsSection("Döngü Modu") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Mod", selection: Binding(
                            get: { viewModel.rotationMode },
                            set: {
                                viewModel.updateRotationMode($0)
                                onRotationModeChanged?($0)
                            }
                        )) {
                            ForEach(RotationMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(viewModel.rotationMode.modeDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if viewModel.rotationMode == .pinnedBooks {
                            PinnedBooksSectionView(viewModel: viewModel, availableBooks: availableBooks)
                        }
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

                // MARK: - Süsleme
                settingsSection("Süsleme") {
                    HStack(spacing: 8) {
                        ForEach(TypographySettings.DecorationStyle.allCases) { style in
                            DecorationStyleChip(
                                style: style,
                                isSelected: viewModel.decorativeStyle == style
                            ) {
                                viewModel.updateDecorativeStyle(style)
                                onTypographyChanged?()
                            }
                        }
                    }
                }

                // MARK: - Özel Gradient
                settingsSection("Özel Gradient") {
                    GradientPicker(
                        startColor: $viewModel.backgroundStartColor,
                        endColor: $viewModel.backgroundEndColor
                    )
                    HStack {
                        Spacer()
                        Button("Varsayılana Dön") {
                            viewModel.resetBackgroundGradient()
                            onTypographyChanged?()
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: viewModel.backgroundStartColor) { _, _ in
                    viewModel.updateBackgroundGradient()
                    onTypographyChanged?()
                }
                .onChange(of: viewModel.backgroundEndColor) { _, _ in
                    viewModel.updateBackgroundGradient()
                    onTypographyChanged?()
                }

                // MARK: - Genel
                settingsSection("Genel") {
                    VStack(alignment: .leading, spacing: 3) {
                        Toggle("Başlangıçta Aç", isOn: $viewModel.launchAtLogin)
                        if let err = viewModel.loginItemError {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    Toggle("Menü Çubuğunda Göster", isOn: $viewModel.showInMenuBar)
                    Toggle("Bildirim Gönder", isOn: $viewModel.showNotifications)
                    VStack(alignment: .leading, spacing: 3) {
                        Toggle("Tüm Alanlara Uygula", isOn: $viewModel.applyToAllSpaces)
                        Text("Mission Control'deki tüm çalışma alanlarının duvar kağıdını değiştirir.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Önceki Duvar Kağıdına Dön") {
                        onRestorePreviousWallpaper()
                    }
                    .disabled(!canRestorePreviousWallpaper)
                    .help(canRestorePreviousWallpaper
                        ? "KindleWall'dan önceki duvar kağıdını geri yükler"
                        : "Henüz değiştirilmiş bir duvar kağıdı yok")
                }

                // MARK: - Klavye Kısayolları
                settingsSection("Klavye Kısayolları") {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Metin Yakalama")
                                .font(.headline)
                            Text("Herhangi bir uygulamada metin seçip kısayola basınca QuickCapture paneli açılır.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        HotkeyRecorderButton()
                    }

                    // Accessibility — optional enhancement for selected text pre-fill
                    HStack(spacing: 6) {
                        if accessibilityGranted {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("Erişilebilirlik izni var — seçili metin otomatik doldurulur")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "info.circle").foregroundStyle(.secondary)
                            Text("Opsiyonel: Erişilebilirlik izni verilirse seçili metin panele otomatik gelir")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("İzin Ver") {
                                GlobalHotkeyManager.shared.openAccessibilitySettings()
                            }
                            .font(.caption).buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                    .onAppear { accessibilityGranted = AXIsProcessTrusted() }
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
        .onChange(of: viewModel.applyToAllSpaces) { _, _ in viewModel.saveSettings() }
        .onChange(of: viewModel.customScheduleDate) { _, newDate in
            onScheduleChanged?(viewModel.scheduleInterval, newDate)
        }
        .onChange(of: viewModel.pinnedBookTitles) { _, newTitles in
            onPinnedBooksChanged?(newTitles)
        }
    }

    // MARK: - Components

    private struct DecorationStyleChip: View {
        let style: TypographySettings.DecorationStyle
        let isSelected: Bool
        let action: () -> Void

        var symbol: String {
            switch style {
            case .classicQuote: return "\u{201C}"
            case .minimalDots:  return "⁝"
            case .line:         return "—"
            case .none:         return "∅"
            }
        }

        var label: String {
            switch style {
            case .classicQuote: return "Tırnak"
            case .minimalDots:  return "Minimal"
            case .line:         return "Çizgi"
            case .none:         return "Yok"
            }
        }

        var body: some View {
            Button(action: action) {
                VStack(spacing: 4) {
                    Text(symbol)
                        .font(.title2)
                        .fontDesign(.serif)
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                .frame(width: 60, height: 52)
                .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                                lineWidth: isSelected ? 1.5 : 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
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
