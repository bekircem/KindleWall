import SwiftUI

@main
struct KindleWallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var importState: ImportState
    @State private var syncState: SyncState
    @State private var cloudKitSync: CloudKitSyncService
    @State private var viewModel: MainViewModel
    /// Owned here, not inside `MainView`, so setup and the main window edit the same object.
    @State private var settingsVM = SettingsViewModel()

    /// Backed by the same key `StorageService` writes, so clearing it from Ayarlar re-runs
    /// setup immediately. It used to be a `@State` read once in `App.init`, which is why there
    /// was no way to see onboarding again short of deleting the preference and relaunching.
    @AppStorage(Constants.StorageKeys.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @AppStorage(Constants.StorageKeys.showInMenuBar) private var showInMenuBar: Bool = true

    init() {
        let importSt = ImportState()
        let syncSt = SyncState()
        let storage = StorageService()
        _importState = State(initialValue: importSt)
        _syncState = State(initialValue: syncSt)
        _cloudKitSync = State(initialValue: CloudKitSyncService(syncState: syncSt, storage: storage))
        _viewModel = State(initialValue: MainViewModel(importState: importSt))
    }

    var body: some Scene {
        // Main window
        WindowGroup {
            Group {
                if !hasCompletedOnboarding {
                    // Setup drives the real view model, so every choice is already committed by
                    // the time it finishes. The old flow kicked off an *async* import and then
                    // synchronously asked for a quote and an apply, so at that instant there
                    // were no clippings yet: the apply bailed out and the first wallpaper never
                    // appeared.
                    OnboardingView(viewModel: viewModel, settingsVM: settingsVM) {
                        hasCompletedOnboarding = true
                    }
                    .environment(importState)
                } else {
                    MainView(viewModel: viewModel, settingsVM: settingsVM)
                        .environment(importState)
                        .environment(syncState)
                        .environment(cloudKitSync)
                        .onAppear {
                            viewModel.startScheduler()
                            viewModel.sweepOrphanedWallpapers()
                            AppEnvironment.shared.mainViewModel = viewModel
                        }
                        // Sync is gated on the iCloud account and nothing else. It used to be
                        // gated on Sign in with Apple as well, which was always redundant —
                        // `CloudKitSyncService` checks `CKContainer.accountStatus()` itself and
                        // reports every unavailable case — and Apple does not issue Developer ID
                        // provisioning profiles for apps requesting that capability at all.
                        .task {
                            cloudKitSync.start()
                        }
                }
            }
            // Dark-first signature identity — the refreshed UI is designed for dark surfaces.
            .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1060, height: 700)

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
