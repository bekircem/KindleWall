import SwiftUI

/// Live wallpaper preview shown as a collapsible trailing inspector on the "Tasarım" page.
///
/// Reuses the preview image `MainViewModel` already renders, so editing controls update it
/// in place with no extra render pipeline. The mirror image of `CurrentQuoteView`, where the
/// preview is the hero and typography lives in the inspector.
struct WallpaperPreviewInspector: View {
    // Plain `let` is enough: reading an @Observable's properties inside `body` is tracked
    // automatically. @Bindable would only be needed to derive bindings.
    let viewModel: MainViewModel

    var body: some View {
        // A 16:10 preview in a tall, portrait inspector is width-bound. Keep it top-aligned
        // (right under the title) and wrapped in a ScrollView, so it never overflows the panel
        // at small window sizes. The column's width (see inspectorColumnWidth) — not vertical
        // centering — is the lever that makes the preview bigger.
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                header

                WallpaperPreviewView(
                    image: viewModel.currentWallpaperImage,
                    cornerRadius: Theme.Radius.card
                )

                if let clipping = viewModel.currentClipping {
                    caption(for: clipping)
                }

                // This line used to promise only what the *panel* did, which is how it came to
                // read as a promise about the desktop that the app did not keep.
                Text("Değişiklikler önce burada görünür, sonra masaüstüne uygulanır.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
        .onAppear {
            // Safety net: guarantee an image the first time the panel is shown, even if the
            // user navigated straight here without touching a control yet.
            if viewModel.currentWallpaperImage == nil {
                viewModel.generatePreview()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Canlı Önizleme")
                .font(.headline)
            Spacer()
            Button {
                // Same action as the hero screen's "Yeni Alıntı" — sample the design across quotes.
                viewModel.selectRandomClipping()
            } label: {
                Image(systemName: Constants.Icons.newQuote)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Yeni alıntı dene")
            .accessibilityLabel("Yeni alıntı dene")
        }
    }

    // MARK: - Caption

    /// Compact source line under the preview: book title + author.
    private func caption(for clipping: Clipping) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(clipping.bookTitle)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let author = clipping.author {
                Text(author)
                    .font(.caption2)
                    .italic()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Reusable Inspector Modifier

/// Adds a collapsible trailing live-preview inspector plus the shared apply button.
/// Applied to the design page so edits are visible in place.
private struct LivePreviewInspectorModifier: ViewModifier {
    let viewModel: MainViewModel
    // Shared across the three appearance pages and persisted across launches.
    // Defaults open — the whole point is that the preview should be visible by default.
    @AppStorage(Constants.StorageKeys.appearancePreviewVisible) private var isPresented = true

    func body(content: Content) -> some View {
        content
            .inspector(isPresented: $isPresented) {
                WallpaperPreviewInspector(viewModel: viewModel)
                    // 300 was too greedy once this page also had to hold the style grid: at
                    // small window sizes sidebar + content + inspector exceeded the window and
                    // the split view pushed the sidebar off the left edge, clipping its labels.
                    .inspectorColumnWidth(min: 240, ideal: 320, max: 520)
            }
            .toolbar {
                // `.primaryAction` is reserved app-wide for "Uygula"; the preview toggle is a
                // secondary control and moved out of that slot.
                ToolbarItem(placement: .primaryAction) {
                    ApplyToolbarButton(viewModel: viewModel)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        isPresented.toggle()
                    } label: {
                        Label("Önizleme", systemImage: "sidebar.right")
                    }
                    .help(isPresented ? "Önizlemeyi gizle" : "Önizlemeyi göster")
                    .accessibilityLabel(isPresented ? "Önizlemeyi gizle" : "Önizlemeyi göster")
                }
            }
    }
}

extension View {
    /// Attaches the live wallpaper-preview inspector (trailing, collapsible) and its toolbar toggle.
    func livePreviewInspector(viewModel: MainViewModel) -> some View {
        modifier(LivePreviewInspectorModifier(viewModel: viewModel))
    }
}
