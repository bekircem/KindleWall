import SwiftUI

/// The main application window: Loop-style grouped sidebar navigation with focused detail pages.
struct MainView: View {
    @State private var viewModel: MainViewModel
    @State private var settingsVM = SettingsViewModel()
    @State private var selection: SidebarItem = .currentQuote

    init(viewModel: MainViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 840, minHeight: 560)
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

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(SidebarSection.allCases) { section in
                Section(section.rawValue) {
                    ForEach(SidebarItem.items(in: section)) { item in
                        Label {
                            Text(item.title)
                        } icon: {
                            IconTile(symbol: item.icon, color: item.color, size: 22)
                        }
                        .tag(item)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 210, ideal: 230)
    }

    // MARK: - Detail

    @ViewBuilder private var detail: some View {
        switch selection {
        case .currentQuote:
            CurrentQuoteView(viewModel: viewModel)

        case .library:
            NavigationStack {
                LibraryView(
                    clippings: viewModel.clippings,
                    onSelectClipping: { clipping in
                        viewModel.currentClipping = clipping
                        viewModel.generatePreview()
                        selection = .currentQuote
                    },
                    onApplyClipping: { clipping in
                        viewModel.selectAndApply(clipping)
                        selection = .currentQuote
                    },
                    onAddManualClipping: { title, author, text, page in
                        viewModel.addManualClipping(bookTitle: title, author: author, text: text, page: page)
                    },
                    onDeleteManualClipping: { viewModel.deleteManualClipping($0) },
                    onUpdateManualClipping: { viewModel.updateManualClipping($0) }
                )
            }

        case .style:
            StyleSettingsPage(viewModel: viewModel, settingsVM: settingsVM, actions: actions)
                .livePreviewInspector(viewModel: viewModel)

        case .typography:
            TypographySettingsPage(viewModel: viewModel, settingsVM: settingsVM, actions: actions)
                .livePreviewInspector(viewModel: viewModel)

        case .background:
            BackgroundSettingsPage(settingsVM: settingsVM, actions: actions)
                .livePreviewInspector(viewModel: viewModel)

        case .behavior:
            BehaviorSettingsPage(viewModel: viewModel, settingsVM: settingsVM, actions: actions)

        case .general:
            GeneralSettingsPage(settingsVM: settingsVM, canRestorePreviousWallpaper: viewModel.canRestorePreviousWallpaper, actions: actions)

        case .shortcuts:
            ShortcutsSettingsPage()

        case .account:
            AccountView()

        case .about:
            AboutPage()
        }
    }

    // MARK: - Settings wiring

    /// Closures that forward settings-page changes into the live wallpaper view model.
    private var actions: SettingsActions {
        SettingsActions(
            onFileSelected: { viewModel.loadClippings(from: $0) },
            onStyleChanged: { viewModel.updateStyle($0) },
            onTypographyChanged: { viewModel.reloadTypography() },
            onScheduleChanged: { interval, customDate in
                viewModel.updateScheduleInterval(interval, customDate: customDate)
            },
            onRotationModeChanged: { viewModel.updateRotationMode($0) },
            onPinnedBooksChanged: { viewModel.updatePinnedBooks($0) },
            onRestorePreviousWallpaper: { viewModel.restorePreviousWallpaper() },
            onApplyNow: {
                viewModel.selectRandomClipping()
                viewModel.applyWallpaper()
            }
        )
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
