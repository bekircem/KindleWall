import SwiftUI

/// The main application window with sidebar navigation.
struct MainView: View {
    @State private var viewModel: MainViewModel
    @State private var selectedTab: SidebarTab = .currentQuote

    enum SidebarTab: String, CaseIterable {
        case currentQuote = "Şu Anki Alıntı"
        case library = "Kütüphane"
        case settings = "Ayarlar"
        case account = "Hesap"

        var icon: String {
            switch self {
            case .currentQuote: return Constants.Icons.currentQuote
            case .library: return Constants.Icons.library
            case .settings: return Constants.Icons.settings
            case .account: return "person.crop.circle"
            }
        }
    }

    init(viewModel: MainViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationSplitView {
            List(SidebarTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch selectedTab {
            case .currentQuote:
                CurrentQuoteView(viewModel: viewModel)
            case .library:
                NavigationStack {
                    LibraryView(
                        clippings: viewModel.clippings,
                        onSelectClipping: { clipping in
                            viewModel.currentClipping = clipping
                            viewModel.generatePreview()
                            selectedTab = .currentQuote
                        },
                        onApplyClipping: { clipping in
                            viewModel.selectAndApply(clipping)
                            selectedTab = .currentQuote
                        }
                    )
                }
            case .settings:
                SettingsView(
                    clippingsCount: viewModel.clippings.count,
                    canRestorePreviousWallpaper: viewModel.canRestorePreviousWallpaper,
                    availableBooks: viewModel.availableBooks,
                    onFileSelected: { url in
                        viewModel.loadClippings(from: url)
                    },
                    onStyleChanged: { style in
                        viewModel.updateStyle(style)
                    },
                    onTypographyChanged: {
                        viewModel.reloadTypography()
                    },
                    onScheduleChanged: { interval, customDate in
                        viewModel.updateScheduleInterval(interval, customDate: customDate)
                    },
                    onRotationModeChanged: { mode in
                        viewModel.updateRotationMode(mode)
                    },
                    onRestorePreviousWallpaper: {
                        viewModel.restorePreviousWallpaper()
                    }
                )
            case .account:
                AccountView()
            }
        }
        .frame(minWidth: 800, minHeight: 550)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            ImportProgressBanner()
                .padding(.bottom, 12)
                .padding(.horizontal, 16)
                .frame(maxWidth: 420)
        }
        .onAppear {
            viewModel.loadClippings()
            if viewModel.currentClipping == nil && !viewModel.clippings.isEmpty {
                viewModel.selectRandomClipping()
            }
        }
    }
}

// MARK: - Current Quote View

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

                        Button {
                            viewModel.applyWallpaper()
                        } label: {
                            Label("Uygula", systemImage: Constants.Icons.wallpaper)
                        }
                        .buttonStyle(.borderedProminent)
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

// MARK: - Typography Panel

/// Side panel with sliders for adjusting wallpaper typography.
struct TypographyPanelView: View {
    @Binding var typography: TypographySettings
    var onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Tipografi")
                    .font(.headline)
                Spacer()
                Button("Sıfırla") {
                    onReset()
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                // Font size
                SliderRow(
                    title: "Yazı Boyutu",
                    icon: "textformat.size",
                    value: $typography.fontScale,
                    range: 0.6...1.6,
                    defaultValue: 1.0
                )

                // Vertical position
                SliderRow(
                    title: "Dikey Konum",
                    icon: "arrow.up.arrow.down",
                    value: $typography.verticalPosition,
                    range: -0.8...0.8,
                    defaultValue: 0.0
                )

                // Padding
                SliderRow(
                    title: "Kenar Boşluğu",
                    icon: "arrow.left.and.right",
                    value: $typography.paddingScale,
                    range: 0.5...1.8,
                    defaultValue: 1.0
                )

                // Line spacing
                SliderRow(
                    title: "Satır Aralığı",
                    icon: "line.3.horizontal",
                    value: $typography.lineSpacingScale,
                    range: 0.6...1.6,
                    defaultValue: 1.0
                )
            }

            Spacer()
        }
        .padding()
        .background(.background)
    }
}

/// A labeled slider row for typography settings.
struct SliderRow: View {
    let title: String
    let icon: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Text(title)
                    .font(.caption)
                Spacer()
                Text(String(format: "%.0f%%", value * 100))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range)
                .controlSize(.small)
                .onDoubleClick {
                    value = defaultValue
                }
        }
    }
}

// MARK: - Double Click Modifier

extension View {
    func onDoubleClick(perform action: @escaping () -> Void) -> some View {
        self.onTapGesture(count: 2, perform: action)
    }
}

// MARK: - No File Empty State

/// Full-panel empty state shown when no Kindle clippings file has been selected.
struct NoFileEmptyStateView: View {
    var onSelectFile: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "book.closed.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            Text("Kindle Dosyası Seçilmedi")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("My Clippings.txt dosyanızı seçerek\nKindle alıntılarınızı duvar kağıdına\ndönüştürmeye başlayın.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                onSelectFile()
            } label: {
                Label("Dosya Seç", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    MainView(viewModel: MainViewModel())
}
