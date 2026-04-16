import SwiftUI

/// Content displayed in the menu bar dropdown.
struct MenuBarView: View {
    @Bindable var viewModel: MainViewModel
    var onOpenWindow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnailSection
            quoteSection
            Divider().padding(.vertical, 8)
            actionRow
            Divider().padding(.vertical, 8)
            stylePicker
            Divider().padding(.vertical, 8)
            schedulerRow
            Divider().padding(.vertical, 8)
            systemActions
        }
        .padding(12)
        .frame(width: 280)
    }

    // MARK: - Thumbnail

    private var thumbnailSection: some View {
        Group {
            if let image = viewModel.currentWallpaperImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            } else {
                RoundedRectangle(cornerRadius: 8)
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
            }
        }
        .padding(.bottom, 2)
    }

    // MARK: - Action Row

    private var actionRow: some View {
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
            .buttonStyle(.bordered)
            .disabled(viewModel.currentClipping == nil)
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
            }
            .buttonStyle(.plain)

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
        VStack(alignment: .leading, spacing: 4) {
            Button {
                onOpenWindow()
            } label: {
                Label("Pencereyi Aç", systemImage: "macwindow")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Çıkış", systemImage: "xmark.circle")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
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
