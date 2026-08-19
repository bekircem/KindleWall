import SwiftUI

/// "Tasarım" as an editor rather than a settings page: the wallpaper is the canvas, and the
/// controls that shape it live in a tabbed inspector beside it.
///
/// It used to be a scrolling form — auto-apply card, then a style grid, then background, then
/// typography — with the preview squeezed into a side panel. That inverted the subject and the
/// tools: the thing being designed was the smallest element on screen, and reaching the type
/// controls meant scrolling the style grid off the top. This is the shape macOS uses for
/// anything you edit visually.
struct DesignEditorView: View {
    @Bindable var viewModel: MainViewModel
    @Bindable var settingsVM: SettingsViewModel
    let actions: SettingsActions

    @AppStorage(Constants.StorageKeys.designInspectorTab)
    private var storedTab = DesignTab.style.rawValue
    @AppStorage(Constants.StorageKeys.designInspectorVisible)
    private var isInspectorPresented = true

    private var tab: Binding<DesignTab> {
        Binding(
            get: { DesignTab(rawValue: storedTab) ?? .style },
            set: { storedTab = $0.rawValue }
        )
    }

    var body: some View {
        canvas
            .navigationTitle("Tasarım")
            .inspector(isPresented: $isInspectorPresented) {
                DesignInspector(
                    viewModel: viewModel,
                    settingsVM: settingsVM,
                    actions: actions,
                    tab: tab
                )
                // Wider than the old preview panel: this column now holds the style grid and
                // the type controls, and below 300 the grid drops to a single column.
                .inspectorColumnWidth(min: 300, ideal: 340, max: 520)
            }
            .toolbar { toolbarContent }
            .onAppear {
                // The canvas is the whole point of this screen; never let it open empty.
                if viewModel.currentWallpaperImage == nil {
                    viewModel.generatePreview()
                }
            }
    }

    // MARK: - Canvas

    /// Vertically centered on purpose — and it works here because, unlike the old page, this
    /// is not inside a `ScrollView`, so the stack really does get the pane's full height.
    private var canvas: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer(minLength: 0)

            WallpaperPreviewView(image: viewModel.currentWallpaperImage,
                                 cornerRadius: Theme.Radius.hero)
                .shadow(color: .black.opacity(0.45), radius: 28, x: 0, y: 14)
                .frame(maxWidth: 900)

            if let clipping = viewModel.currentClipping {
                caption(for: clipping)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xxl)
        .background(Theme.Palette.canvas)
    }

    /// Which quote the canvas is currently showing — otherwise a design decision gets judged
    /// against an unidentified highlight.
    private func caption(for clipping: Clipping) -> some View {
        VStack(spacing: 2) {
            Text(clipping.bookTitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let author = clipping.author {
                Text(author)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.top, Theme.Spacing.xs)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            ApplyToolbarButton(viewModel: viewModel)
        }

        ToolbarItemGroup(placement: .secondaryAction) {
            // Was buried as a bare glyph in the old preview panel's header, where it read as
            // decoration rather than as the way to test a design against another quote.
            Button("Yeni Alıntı", systemImage: Constants.Icons.newQuote) {
                viewModel.selectRandomClipping()
            }
            .help("Tasarımı başka bir alıntıyla dene")

            Button("Kontroller", systemImage: "sidebar.right") {
                isInspectorPresented.toggle()
            }
            .help(isInspectorPresented ? "Kontrolleri gizle" : "Kontrolleri göster")
        }
    }
}
