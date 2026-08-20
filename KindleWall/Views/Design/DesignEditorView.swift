import SwiftUI

/// "Design" as an editor rather than a settings page: the wallpaper is the canvas, and the
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

    /// Was `.inspectorColumnWidth(min: 300, ideal: 340, max: 520)` — this is that ideal, now
    /// fixed. See the note on `body` for why the system inspector had to go; the drag handle
    /// went with it.
    private static let inspectorWidth: CGFloat = 340

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

    /// A plain trailing column rather than `.inspector`.
    ///
    /// `.inspector` positioned the entire split view one toolbar height too high on this page:
    /// the sidebar's first section header collided with the traffic lights, the tab picker slid
    /// under the toolbar where the Apply button drew straight over it, and the auto-apply
    /// footer fell off the bottom edge. Measured at 1072x727 — the sidebar sat at y=330 with
    /// the toolbar ending at 379, on every window height below roughly 850.
    ///
    /// Ruled out by measurement before rewriting: the window's `.hiddenTitleBar` style
    /// (removing it changed nothing), the order of `.toolbar` against `.inspector` (both
    /// orders reproduce), the inspector's own content height (the shortest tab overflows as
    /// far as the tallest), and `.inspector` as such — the typography panel on the Current
    /// Quote page is also an `.inspector` and lays out correctly at the same window size.
    ///
    /// So the trigger is something about *this* panel inside `.inspector` — a filling `VStack`
    /// with a fixed picker above and a pinned footer below a `ScrollView`. That is worth
    /// knowing but not worth another day: a plain column costs one modifier, behaves like
    /// every other page, and cannot drift out of the window again. The price is the drag
    /// handle, which `.inspectorColumnWidth` provided and a fixed width does not.
    var body: some View {
        HStack(spacing: 0) {
            canvas

            if isInspectorPresented {
                Divider()

                DesignInspector(
                    viewModel: viewModel,
                    settingsVM: settingsVM,
                    actions: actions,
                    tab: tab
                )
                // Wide enough for the style grid and the type controls; below 300 the grid
                // drops to a single column.
                .frame(width: Self.inspectorWidth)
            }
        }
        .animation(Theme.Motion.smooth, value: isInspectorPresented)
        .navigationTitle("Design")
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
            Button("New Quote", systemImage: Constants.Icons.newQuote) {
                viewModel.selectRandomClipping()
            }
            .help("Try the design with a different quote")

            Button("Controls", systemImage: "sidebar.right") {
                isInspectorPresented.toggle()
            }
            .help(isInspectorPresented ? "Hide controls" : "Show controls")
        }
    }
}
