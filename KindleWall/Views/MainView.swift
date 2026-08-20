import SwiftUI

/// The main application window: Loop-style grouped sidebar navigation with focused detail pages.
struct MainView: View {
    @State private var viewModel: MainViewModel
    /// Injected rather than created here, so onboarding and the main window share one instance.
    @Bindable var settingsVM: SettingsViewModel
    @State private var selection: SidebarItem = .currentQuote

    init(viewModel: MainViewModel, settingsVM: SettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
        self.settingsVM = settingsVM
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        // The design page puts a sidebar, a style grid and the preview inspector side by side.
        // Below this width they cannot all fit, and `NavigationSplitView` resolves that by
        // pushing the sidebar off the left edge — its labels end up clipped mid-word rather
        // than the inspector giving way. Measured at 940: ~60pt short.
        .frame(minWidth: 1000, minHeight: 600)
        .overlay(alignment: .bottom) {
            // Both float in the same corner so status has one home, whichever page is open.
            VStack(spacing: Theme.Spacing.s) {
                AlertBanner(viewModel: viewModel)
                ApplyStatusBar(viewModel: viewModel)
                ImportProgressBanner()
                    .frame(maxWidth: 420)
            }
            .padding(.bottom, 12)
            .padding(.horizontal, 16)
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
                Section(section.title) {
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
        .background(sidebarShortcuts)
    }

    /// ⌘1…⌘8 jump straight to a sidebar destination.
    ///
    /// Zero-sized buttons because a `List` row carries a selection tag, not an action, so there
    /// is nothing there to hang a shortcut on.
    private var sidebarShortcuts: some View {
        ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { index, item in
            Button("") { selection = item }
                .keyboardShortcut(
                    KeyEquivalent(Character("\(index + 1)")),
                    modifiers: .command
                )
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
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
                    onUpdateManualClipping: { viewModel.updateManualClipping($0) },
                    onChooseFile: {
                        if let url = settingsVM.selectClippingsFile() {
                            viewModel.loadClippings(from: url)
                        }
                    }
                )
            }

        case .design:
            DesignEditorView(viewModel: viewModel, settingsVM: settingsVM, actions: actions)

        case .behavior:
            BehaviorSettingsPage(viewModel: viewModel, settingsVM: settingsVM, actions: actions)

        case .settings:
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
            },
            onApplyDesignNow: { viewModel.applyDesignNow() }
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
    MainView(viewModel: MainViewModel(), settingsVM: SettingsViewModel())
}
