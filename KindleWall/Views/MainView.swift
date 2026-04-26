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
                        },
                        onAddManualClipping: { title, author, text, page in
                            viewModel.addManualClipping(bookTitle: title, author: author,
                                                        text: text, page: page)
                        },
                        onDeleteManualClipping: { viewModel.deleteManualClipping($0) },
                        onUpdateManualClipping: { viewModel.updateManualClipping($0) }
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
                    onPinnedBooksChanged: { titles in
                        viewModel.updatePinnedBooks(titles)
                    },
                    onRestorePreviousWallpaper: {
                        viewModel.restorePreviousWallpaper()
                    },
                    onApplyNow: {
                        viewModel.selectRandomClipping()
                        viewModel.applyWallpaper()
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
        .sheet(isPresented: Binding(
            get: { viewModel.pendingCaptureText != nil },
            set: { if !$0 { viewModel.pendingCaptureText = nil } }
        )) {
            ManualClippingFormView(
                prefilledText: viewModel.pendingCaptureText ?? "",
                existingBooks: captureExistingBooks,
                onSave: { title, author, text, page in
                    viewModel.addManualClipping(bookTitle: title, author: author, text: text, page: page)
                    viewModel.pendingCaptureText = nil
                },
                onCancel: { viewModel.pendingCaptureText = nil }
            )
        }
        .onAppear {
            viewModel.loadClippings()
            if viewModel.currentClipping == nil && !viewModel.clippings.isEmpty {
                viewModel.selectRandomClipping()
            }
        }
    }

    private var captureExistingBooks: [(title: String, author: String?)] {
        var seen = Set<String>()
        return viewModel.clippings.compactMap { c in
            guard !seen.contains(c.bookTitle) else { return nil }
            seen.insert(c.bookTitle)
            return (title: c.bookTitle, author: c.author)
        }.sorted { $0.title < $1.title }
    }
}

#Preview {
    MainView(viewModel: MainViewModel())
}
