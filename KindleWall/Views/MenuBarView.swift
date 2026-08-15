import SwiftUI

/// Content displayed in the menu bar dropdown.
struct MenuBarView: View {
    @Bindable var viewModel: MainViewModel
    var onOpenWindow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnailSection
            quoteSection
            Divider().padding(.vertical, Theme.Spacing.s)
            actionRow
            Divider().padding(.vertical, Theme.Spacing.s)
            stylePicker
            Divider().padding(.vertical, Theme.Spacing.s)
            schedulerRow
            Divider().padding(.vertical, Theme.Spacing.s)
            systemActions
        }
        .padding(Theme.Spacing.m)
        .frame(width: 280)
    }

    // MARK: - Thumbnail

    private var thumbnailSection: some View {
        Group {
            if let image = viewModel.currentWallpaperImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .fill(.quaternary)
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .overlay {
                        Image(systemName: Constants.Icons.currentQuote)
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .padding(.bottom, 10)
    }

    // MARK: - Quote Info + Favorite

    private var quoteSection: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                if let clipping = viewModel.currentClipping {
                    Text(clipping.text.truncated(to: 120))
                        .font(.callout)
                        .lineLimit(2)
                    Text(metaText(for: clipping))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Alıntı yüklenmedi")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if viewModel.currentClipping != nil {
                Button {
                    viewModel.toggleFavorite()
                } label: {
                    Image(systemName: viewModel.isCurrentFavorite
                          ? Constants.Icons.favoriteFilled
                          : Constants.Icons.favorite)
                        .foregroundStyle(viewModel.isCurrentFavorite ? Color.red : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(viewModel.isCurrentFavorite ? "Favoriden Çıkar" : "Favoriye Ekle")
                .accessibilityLabel(viewModel.isCurrentFavorite ? "Favorilerden çıkar" : "Favorilere ekle")
            }
        }
        .padding(.bottom, 2)
    }

    // MARK: - Action Row

    private var actionRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    viewModel.selectRandomClipping()
                    viewModel.applyWallpaper()
                } label: {
                    Label("Yeni Alıntı", systemImage: Constants.Icons.newQuote)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    viewModel.applyWallpaper()
                } label: {
                    Label("Uygula", systemImage: Constants.Icons.wallpaper)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.currentClipping == nil)
            }

            Button {
                GlobalHotkeyManager.shared.showCapture()
            } label: {
                Label("Alıntı Ekle", systemImage: Constants.Icons.captureIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Style Picker

    private var stylePicker: some View {
        Picker("Stil", selection: Binding(
            get: { viewModel.selectedStyle },
            set: { viewModel.updateStyle($0) }
        )) {
            ForEach(WallpaperStyle.allCases) { style in
                Text(style.displayName).tag(style)
            }
        }
        .pickerStyle(.menu)
    }

    // MARK: - Scheduler Row

    private var schedulerRow: some View {
        HStack {
            Button {
                viewModel.toggleSchedulerPause()
            } label: {
                Label(
                    viewModel.isSchedulerPaused ? "Devam Et" : "Durakla",
                    systemImage: viewModel.isSchedulerPaused
                        ? Constants.Icons.play
                        : Constants.Icons.pause
                )
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight()
            .accessibilityLabel(viewModel.isSchedulerPaused ? "Zamanlayıcıyı devam ettir" : "Zamanlayıcıyı durdur")

            Spacer()

            if let nextDate = viewModel.nextWallpaperDate {
                Text("Sonraki: \(nextDate.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - System Actions

    private var systemActions: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                onOpenWindow()
            } label: {
                Label("Pencereyi Aç", systemImage: "macwindow")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.s)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight()
            .accessibilityLabel("Pencereyi aç")

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Çıkış", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.s)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight()
            .accessibilityLabel("Uygulamadan çık")
        }
    }

    // MARK: - Helpers

    private func metaText(for clipping: Clipping) -> String {
        if let author = clipping.author {
            return "\(clipping.bookTitle) — \(author)"
        }
        return clipping.bookTitle
    }
}
