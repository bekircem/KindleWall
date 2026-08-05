import SwiftUI

@main
struct KindleWallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var importState: ImportState
    @State private var authState: AuthState
    @State private var authService: AuthService
    @State private var syncState: SyncState
    @State private var cloudKitSync: CloudKitSyncService
    @State private var viewModel: MainViewModel
    @State private var showOnboarding = !StorageService().hasCompletedOnboarding
    @AppStorage(Constants.StorageKeys.showInMenuBar) private var showInMenuBar: Bool = true

    init() {
        let importSt = ImportState()
        let authSt = AuthState()
        let syncSt = SyncState()
        let storage = StorageService()
        _importState = State(initialValue: importSt)
        _authState = State(initialValue: authSt)
        _authService = State(initialValue: AuthService(authState: authSt))
        _syncState = State(initialValue: syncSt)
        _cloudKitSync = State(initialValue: CloudKitSyncService(syncState: syncSt, storage: storage))
        _viewModel = State(initialValue: MainViewModel(importState: importSt))
    }

    var body: some Scene {
        // Main window
        WindowGroup {
            Group {
                if showOnboarding {
                    OnboardingView { fileURL, style, interval in
                        let storage = StorageService()
                        storage.hasCompletedOnboarding = true
                        storage.selectedStyle = style
                        storage.scheduleInterval = interval

                        viewModel.loadClippings(from: fileURL)
                        viewModel.updateStyle(style)
                        viewModel.selectRandomClipping()
                        viewModel.applyWallpaper()
                        viewModel.startScheduler()

                        showOnboarding = false
                    }
                } else {
                    MainView(viewModel: viewModel)
                        .environment(importState)
                        .environment(authState)
                        .environment(authService)
                        .environment(syncState)
                        .environment(cloudKitSync)
                        .onAppear {
                            viewModel.startScheduler()
                            viewModel.sweepOrphanedWallpapers()
                            AppEnvironment.shared.mainViewModel = viewModel
                        }
                        .task {
                            await authService.checkCredentialState()
                            if authState.isAuthenticated {
                                cloudKitSync.start()
                            }
                        }
                        .onChange(of: authState.isAuthenticated) { _, isAuth in
                            if isAuth {
                                cloudKitSync.start()
                            } else {
                                cloudKitSync.stop()
                            }
                        }
                }
            }
            // Dark-first signature identity — the refreshed UI is designed for dark surfaces.
            .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 940, height: 640)

        // Menu bar extra — visibility controlled by user preference via isInserted binding
        MenuBarExtra(isInserted: $showInMenuBar) {
            MenuBarView(viewModel: viewModel) {
                NSApplication.shared.activate(ignoringOtherApps: true)
                if let window = NSApplication.shared.windows.first {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            .preferredColorScheme(.dark)
        } label: {
            Image(systemName: Constants.Icons.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
