import SwiftUI

@main
struct KindleWallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var viewModel = MainViewModel()
    @State private var showOnboarding = !StorageService().hasCompletedOnboarding

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
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 600)

        // Menu bar extra
        MenuBarExtra {
            MenuBarView(viewModel: viewModel) {
                NSApplication.shared.activate(ignoringOtherApps: true)
                // Open or bring main window to front
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
