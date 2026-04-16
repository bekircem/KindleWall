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
    var onRestorePreviousWallpaper: () -> Void = {}

    @State private var viewModel = SettingsViewModel()
    @State private var bookSearchText: String = ""

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
                            pinnedBooksSection
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
                        ForEach(TypographySettings.DecorationStyle.allCases, id: \.self) { style in
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
    }

    // MARK: - Decoration Style Chip

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

    // MARK: - Pinned Books List

    @ViewBuilder
    private var pinnedBooksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if availableBooks.isEmpty {
                Text("Henüz alıntı yüklenmedi. Önce bir Clippings dosyası seçin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // ── Arama + Toplu İşlem ──────────────────────────────────────
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        TextField("Kitap ara…", text: $bookSearchText)
                            .textFieldStyle(.plain)
                            .font(.callout)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7)
                        .fill(Color.secondary.opacity(0.1)))

                    if viewModel.pinnedBookTitles.isEmpty {
                        Button("Tümünü Seç") {
                            for book in availableBooks where !viewModel.isBookPinned(book.title) {
                                viewModel.togglePinnedBook(book.title)
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    } else {
                        Button("Seçimi Temizle") {
                            for book in availableBooks where viewModel.isBookPinned(book.title) {
                                viewModel.togglePinnedBook(book.title)
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }

                // ── Kitap Listesi ────────────────────────────────────────────
                let filtered = availableBooks.filter {
                    bookSearchText.isEmpty ||
                    $0.title.localizedCaseInsensitiveContains(bookSearchText) ||
                    ($0.author?.localizedCaseInsensitiveContains(bookSearchText) ?? false)
                }
                let sorted = filtered.sorted {
                    let aSelected = viewModel.isBookPinned($0.title)
                    let bSelected = viewModel.isBookPinned($1.title)
                    if aSelected != bSelected { return aSelected }
                    return $0.title < $1.title
                }

                if sorted.isEmpty {
                    Text("Sonuç bulunamadı.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(sorted, id: \.title) { book in
                                Button {
                                    viewModel.togglePinnedBook(book.title)
                                } label: {
                                    HStack {
                                        Image(systemName: viewModel.isBookPinned(book.title)
                                            ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(viewModel.isBookPinned(book.title)
                                                ? Color.accentColor : Color.secondary)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(book.title)
                                                .font(.callout)
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            if let author = book.author {
                                                Text(author)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.07)))
                }

                // ── Durum satırı ─────────────────────────────────────────────
                if viewModel.pinnedBookTitles.isEmpty {
                    Text("Hiç kitap seçilmedi — tümünden rastgele gösterilecek.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else {
                    Text("\(viewModel.pinnedBookTitles.count) kitap seçildi.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
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
