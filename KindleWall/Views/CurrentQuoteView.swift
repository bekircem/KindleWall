import SwiftUI

/// Displays the current wallpaper preview with typography controls.
struct CurrentQuoteView: View {
    @Bindable var viewModel: MainViewModel
    @State private var showTypographyPanel = false

    private var hasNoClippings: Bool {
        viewModel.clippings.isEmpty && !viewModel.isLoading
    }

    var body: some View {
        HSplitView {
            // Left: Preview + actions (or empty state)
            VStack(spacing: 16) {
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
                    // Wallpaper preview (large)
                    Group {
                        if let image = viewModel.currentWallpaperImage {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
                        } else {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.quaternary)
                                .aspectRatio(16/10, contentMode: .fit)
                                .overlay {
                                    ProgressView()
                                }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    // Quote info (below preview)
                    if let clipping = viewModel.currentClipping {
                        VStack(spacing: 6) {
                            Text(clipping.text)
                                .font(.callout)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .foregroundStyle(.primary)

                            HStack(spacing: 4) {
                                Text(clipping.bookTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let author = clipping.author {
                                    Text("— \(author)")
                                        .font(.caption)
                                        .italic()
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    Spacer()

                    // Action buttons
                    HStack(spacing: 10) {
                        Button {
                            viewModel.selectRandomClipping()
                        } label: {
                            Label("Yeni Alıntı", systemImage: Constants.Icons.newQuote)
                        }
                        .keyboardShortcut("n", modifiers: .command)

                        Button {
                            viewModel.toggleFavorite()
                        } label: {
                            Image(systemName: viewModel.isCurrentFavorite ? Constants.Icons.favoriteFilled : Constants.Icons.favorite)
                        }
                        .help("Favori")
                        .keyboardShortcut("d", modifiers: .command)

                        Picker("", selection: Binding(
                            get: { viewModel.selectedStyle },
                            set: { viewModel.updateStyle($0) }
                        )) {
                            ForEach(WallpaperStyle.allCases) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        .frame(width: 150)

                        Button {
                            withAnimation(.spring(duration: 0.2)) {
                                showTypographyPanel.toggle()
                            }
                        } label: {
                            Image(systemName: "textformat.size")
                        }
                        .help("Tipografi Ayarları")
                        .keyboardShortcut("t", modifiers: .command)

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
                            .animation(.easeInOut(duration: 0.2), value: viewModel.isApplying)
                            .animation(.easeInOut(duration: 0.2), value: viewModel.applySuccess)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(viewModel.applySuccess ? .green : .accentColor)
                        .disabled(viewModel.isApplying)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .padding(.bottom, 4)
                    }
                }
            }
            .frame(minWidth: 400)

            // Right: Typography panel (collapsible)
            if showTypographyPanel {
                TypographyPanelView(
                    typography: Binding(
                        get: { viewModel.typography },
                        set: { viewModel.updateTypography($0) }
                    ),
                    onReset: {
                        viewModel.updateTypography(.default)
                    }
                )
                .frame(width: 220)
                .transition(.move(edge: .trailing))
            }
        }
    }
}
