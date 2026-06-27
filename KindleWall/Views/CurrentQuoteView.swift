import SwiftUI

/// The hero screen: a large wallpaper preview with a glass quote bar, plus a typography inspector.
struct CurrentQuoteView: View {
    @Bindable var viewModel: MainViewModel
    @State private var showTypographyPanel = false

    private var hasNoClippings: Bool {
        viewModel.clippings.isEmpty && !viewModel.isLoading
    }

    var body: some View {
        Group {
            if hasNoClippings {
                NoFileEmptyStateView {
                    let panel = NSOpenPanel()
                    panel.title = "My Clippings.txt Dosyasını Seçin"
                    panel.allowedContentTypes = [.plainText]
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        viewModel.loadClippings(from: url)
                    }
                }
            } else {
                hero
            }
        }
        .navigationTitle("Şu Anki Alıntı")
        .toolbar { toolbarContent }
        .inspector(isPresented: $showTypographyPanel) {
            TypographyPanelView(
                typography: Binding(
                    get: { viewModel.typography },
                    set: { viewModel.updateTypography($0) }
                ),
                onReset: { viewModel.updateTypography(.default) }
            )
            .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        // Wrapped in a ScrollView so a long quote text never overflows the window vertically.
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                preview
                    .frame(maxWidth: 720)
                    .padding(.horizontal, Theme.Spacing.xxl)
                    .padding(.top, Theme.Spacing.xl)

                if let clipping = viewModel.currentClipping {
                    quoteText(for: clipping)
                    quoteBar(for: clipping)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, Theme.Spacing.xl)
        }
    }

    /// The full quote text, shown as readable, selectable text beneath the preview.
    private func quoteText(for clipping: Clipping) -> some View {
        Text(clipping.text)
            .font(.system(.title3, design: .serif))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .lineSpacing(5)
            .textSelection(.enabled)
            .frame(maxWidth: 620)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.Spacing.xl)
    }

    @ViewBuilder private var preview: some View {
        if let image = viewModel.currentWallpaperImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 12)
        } else {
            RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                .fill(.quaternary)
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay { ProgressView() }
        }
    }

    /// Compact source strip beneath the quote text: book · author plus date/page metadata.
    private func quoteBar(for clipping: Clipping) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(clipping.bookTitle)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let author = clipping.author {
                    Text("— \(author)")
                        .font(.callout)
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let meta = metadataLine(for: clipping) {
                Text(meta)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
        .frame(maxWidth: 560)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.card))
        .padding(.horizontal, Theme.Spacing.xl)
    }

    /// Date · page/location line for the caption strip, mirroring `ClippingCard`'s metadata.
    private func metadataLine(for clipping: Clipping) -> String? {
        var parts: [String] = []
        if let date = clipping.dateAdded {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        switch (clipping.page, clipping.location) {
        case let (p?, l?): parts.append("Sayfa \(p) · Konum \(l)")
        case let (p?, nil): parts.append("Sayfa \(p)")
        case let (nil, l?): parts.append("Konum \(l)")
        default: break
        }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                viewModel.applyWallpaper()
            } label: {
                Group {
                    if viewModel.isApplying {
                        Label("Uygulanıyor...", systemImage: "arrow.clockwise")
                    } else if viewModel.applySuccess {
                        Label("Uygulandı", systemImage: "checkmark.circle.fill")
                    } else {
                        Label("Uygula", systemImage: Constants.Icons.wallpaper)
                    }
                }
                .animation(Theme.Motion.snappy, value: viewModel.isApplying)
                .animation(Theme.Motion.snappy, value: viewModel.applySuccess)
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.borderedProminent)
            .tint(viewModel.applySuccess ? .green : .accentColor)
            .disabled(viewModel.isApplying)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Bu alıntıyı masaüstü duvar kağıdı olarak uygula")
            .accessibilityLabel("Duvar kağıdı olarak uygula")
        }

        ToolbarItemGroup(placement: .secondaryAction) {
            Picker("", selection: Binding(
                get: { viewModel.selectedStyle },
                set: { viewModel.updateStyle($0) }
            )) {
                ForEach(WallpaperStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .frame(width: 140)
            .accessibilityLabel("Wallpaper stili")

            Button {
                showTypographyPanel.toggle()
            } label: {
                Image(systemName: "textformat.size")
            }
            .help("Tipografi Ayarları")
            .accessibilityLabel("Tipografi ayarları")
            .keyboardShortcut("t", modifiers: .command)

            Button {
                viewModel.toggleFavorite()
            } label: {
                Image(systemName: viewModel.isCurrentFavorite ? Constants.Icons.favoriteFilled : Constants.Icons.favorite)
            }
            .help("Favori")
            .accessibilityLabel(viewModel.isCurrentFavorite ? "Favorilerden çıkar" : "Favorilere ekle")
            .keyboardShortcut("d", modifiers: .command)

            Button {
                viewModel.selectRandomClipping()
            } label: {
                Label("Yeni Alıntı", systemImage: Constants.Icons.newQuote)
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }
}
