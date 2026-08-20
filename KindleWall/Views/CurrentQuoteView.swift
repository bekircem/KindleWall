import SwiftUI

/// The hero screen: a large wallpaper preview with a glass quote bar, plus a typography inspector.
struct CurrentQuoteView: View {
    @Bindable var viewModel: MainViewModel
    @State private var showTypographyPanel = false

    private var hasNoClippings: Bool {
        // `isLoading` was never assigned by anything, so this used to be a plain emptiness
        // check that flashed the "pick a file" screen during every import. The import's real
        // state lives on `ImportState`.
        viewModel.clippings.isEmpty && !viewModel.importState.isRunning
    }

    var body: some View {
        Group {
            if hasNoClippings {
                if viewModel.hasClippingsSource {
                    // A file was chosen and produced nothing — usually the wrong text file.
                    NoFileEmptyStateView(
                        symbol: "doc.text.magnifyingglass",
                        title: "No Quotes Found",
                        message: "There are no readable quotes in that file.\nMake sure you picked My Clippings.txt\nfrom your Kindle.",
                        actionTitle: "Choose Another File…",
                        onSelectFile: chooseClippingsFile
                    )
                } else {
                    NoFileEmptyStateView(onSelectFile: chooseClippingsFile)
                }
            } else {
                hero
            }
        }
        .navigationTitle("Current Quote")
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

    private func chooseClippingsFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose Your My Clippings.txt File"
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.loadClippings(from: url)
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
                    quoteCard(for: clipping)
                }

                // Errors are no longer drawn here — `AlertBanner` shows them on every page,
                // instead of only on the one the user might not be looking at.
                nextChangeLine
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, Theme.Spacing.xl)
        }
    }

    /// When the next rotation lands. The scheduler already knew this; nothing showed it, so the
    /// wallpaper appeared to change at random moments.
    @ViewBuilder private var nextChangeLine: some View {
        if viewModel.isSchedulerPaused {
            Label("Automatic rotation paused", systemImage: Constants.Icons.pause)
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else if let next = viewModel.nextWallpaperDate {
            Text("Next quote at \(next, format: .dateTime.hour().minute())")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }

    /// The quote as selectable text plus its source, in one card.
    ///
    /// These used to be two separate centered blocks stacked under the preview, which — with
    /// the preview already showing the same words — made the screen read as three repetitions
    /// of one thing. Sharing a surface makes the text and its attribution one object, and the
    /// screen two: the wallpaper, and what is on it.
    private func quoteCard(for clipping: Clipping) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            Text(clipping.text)
                .font(.system(.title3, design: .serif))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .frame(maxWidth: Theme.ruleWidth)

            source(for: clipping)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.l)
        .frame(maxWidth: 620)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.hero))
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

    /// Attribution inside the quote card: book · author over date/page metadata.
    private func source(for clipping: Clipping) -> some View {
        VStack(spacing: 4) {
            // Wraps instead of truncating: inside a 620-wide card a long title and author
            // together overflow one line, and losing the author to an ellipsis costs more
            // than a second line does.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    bookTitleText(clipping)
                    authorText(clipping)
                }
                VStack(spacing: 2) {
                    bookTitleText(clipping)
                    authorText(clipping)
                }
            }
            .multilineTextAlignment(.center)

            if let meta = metadataLine(for: clipping) {
                Text(meta)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func bookTitleText(_ clipping: Clipping) -> some View {
        Text(clipping.bookTitle)
            .font(.callout)
            .fontWeight(.medium)
            .foregroundStyle(.primary)
            .lineLimit(2)
    }

    @ViewBuilder private func authorText(_ clipping: Clipping) -> some View {
        if let author = clipping.author {
            Text("— \(author)")
                .font(.callout)
                .italic()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
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
            ApplyToolbarButton(viewModel: viewModel)
        }

        ToolbarItemGroup(placement: .secondaryAction) {
            Picker("Stil", selection: Binding(
                get: { viewModel.selectedStyle },
                set: { viewModel.updateStyle($0) }
            )) {
                ForEach(WallpaperStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .labelsHidden()
            .frame(width: 140)
            .help("Wallpaper style")
            .accessibilityLabel("Wallpaper style")

            Button {
                showTypographyPanel.toggle()
            } label: {
                Image(systemName: "textformat.size")
            }
            .help("Typography Settings")
            .accessibilityLabel("Typography settings")
            .keyboardShortcut("t", modifiers: .command)

            Button {
                viewModel.toggleFavorite()
            } label: {
                Image(systemName: viewModel.isCurrentFavorite ? Constants.Icons.favoriteFilled : Constants.Icons.favorite)
            }
            .help("Favori")
            .accessibilityLabel(viewModel.isCurrentFavorite ? "Remove from favorites" : "Add to favorites")
            .keyboardShortcut("d", modifiers: .command)

            Button {
                viewModel.selectRandomClipping()
            } label: {
                Label("New Quote", systemImage: Constants.Icons.newQuote)
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }
}
