import AppKit
import ServiceManagement

/// Manages NSApplication lifecycle and login item registration.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure the wallpapers directory exists
        ensureDirectoriesExist()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep the app running in menu bar even when the window is closed
        return false
    }

    // MARK: - Private

    private func ensureDirectoriesExist() {
        let fm = FileManager.default
        let dirs = [
            Constants.Paths.appSupportDirectory,
            Constants.Paths.wallpapersDirectory
        ]
        for dir in dirs {
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }
}
