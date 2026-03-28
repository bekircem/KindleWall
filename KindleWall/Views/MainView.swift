import SwiftUI

/// The main application window with sidebar navigation.
struct MainView: View {
    @State private var viewModel: MainViewModel
    @State private var selectedTab: SidebarTab = .currentQuote

    enum SidebarTab: String, CaseIterable {
        case currentQuote = "Şu Anki Alıntı"
        case library = "Kütüphane"
        case settings = "Ayarlar"

        var icon: String {
            switch self {
            case .currentQuote: return Constants.Icons.currentQuote
            case .library: return Constants.Icons.library
            case .settings: return Constants.Icons.settings
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
                LibraryView(
                    clippings: viewModel.clippings,
                    onSelectClipping: { clipping in
                        viewModel.currentClipping = clipping
                        viewModel.generatePreview()
                        selectedTab = .currentQuote
                    }
                )
            case .settings:
                SettingsView(onFileSelected: { url in
                    viewModel.loadClippings(from: url)
                }, onStyleChanged: { style in
                    viewModel.updateStyle(style)
                })
            }
        }
        .frame(minWidth: 800, minHeight: 550)
        .background(.ultraThinMaterial)
        .onAppear {
            viewModel.loadClippings()
            if viewModel.currentClipping == nil && !viewModel.clippings.isEmpty {
                viewModel.selectRandomClipping()
            }
        }
    }
}

// MARK: - Current Quote View

/// Displays the current wallpaper preview and quote controls.
struct CurrentQuoteView: View {
    @Bindable var viewModel: MainViewModel

    var body: some View {
        VStack(spacing: 20) {
            // Wallpaper preview
            if let image = viewModel.currentWallpaperImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 8)
                    .padding(.horizontal)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary)
                    .aspectRatio(16/10, contentMode: .fit)
                    .overlay {
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Text("Alıntı seçilmedi")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
            }

            // Quote info
            if let clipping = viewModel.currentClipping {
                VStack(spacing: 8) {
                    Text(clipping.text)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(.horizontal)

                    HStack(spacing: 4) {
                        Text(clipping.bookTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let author = clipping.author {
                            Text("— \(author)")
                                .font(.subheadline)
                                .italic()
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            // Controls
            HStack(spacing: 12) {
                Button {
                    viewModel.selectRandomClipping()
                } label: {
                    Label("Yeni Alıntı", systemImage: Constants.Icons.newQuote)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button {
                    viewModel.toggleFavorite()
                } label: {
                    Label(
                        "Favori",
                        systemImage: viewModel.isCurrentFavorite ? Constants.Icons.favoriteFilled : Constants.Icons.favorite
                    )
                }

                Picker("Stil", selection: Binding(
                    get: { viewModel.selectedStyle },
                    set: { viewModel.updateStyle($0) }
                )) {
                    ForEach(WallpaperStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .frame(width: 160)

                Button {
                    viewModel.applyWallpaper()
                } label: {
                    Label("Wallpaper Olarak Uygula", systemImage: Constants.Icons.wallpaper)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom)

            // Error message
            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding()
    }
}

#Preview {
    MainView(viewModel: MainViewModel())
}
