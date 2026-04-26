import SwiftUI

@main
struct KindleWallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var importState: ImportState
    @State private var authState: AuthState
    @State private var viewModel: MainViewModel
    @State private var showOnboarding = !StorageService().hasCompletedOnboarding
    @AppStorage(Constants.StorageKeys.showInMenuBar) private var showInMenuBar: Bool = true

    init() {
        let importSt = ImportState()
        let authSt = AuthState()
        _importState = State(initialValue: importSt)
        _authState = State(initialValue: authSt)
        _viewModel = State(initialValue: MainViewModel(importState: importSt))
    }

    var body: some Scene {
        // Main window
        WindowGroup {
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
                    .onAppear {
                        viewModel.startScheduler()
                        AppEnvironment.shared.mainViewModel = viewModel
                    }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 600)

        // Menu bar extra — visibility controlled by user preference via isInserted binding
        MenuBarExtra(isInserted: $showInMenuBar) {
            MenuBarView(viewModel: viewModel) {
                NSApplication.shared.activate(ignoringOtherApps: true)
                if let window = NSApplication.shared.windows.first {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        } label: {
            Image(systemName: Constants.Icons.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
