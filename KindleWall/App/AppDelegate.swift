import AppKit
import CloudKit
import ServiceManagement
import UserNotifications

/// Manages NSApplication lifecycle and login item registration.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure the wallpapers directory exists
        ensureDirectoriesExist()

        // Set delegate so notifications appear while the app is in the foreground.
        // Without this, macOS silently suppresses notifications from the active app.
        UNUserNotificationCenter.current().delegate = self

        // Request authorization on every launch — no-op if already granted or denied.
        Task {
            _ = await NotificationService().requestAuthorization()
        }

        // Start listening for the global ⌃⌥K hotkey
        GlobalHotkeyManager.shared.start()

        // Register Services menu so macOS discovers this handler
        NSApplication.shared.servicesProvider = self
        NSUpdateDynamicServices()

        // Register for silent CloudKit push notifications (CKDatabaseSubscription).
        NSApplication.shared.registerForRemoteNotifications()
    }

    // MARK: - Remote notifications (CloudKit silent push)

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else { return }
        NotificationCenter.default.post(name: Constants.Notifications.cloudKitRemotePush, object: nil)
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Sync gracefully degrades to manual + launch-only without push.
        // No-op: CloudKitSyncService will still work via syncNow() and full pull on launch.
    }

    // MARK: - macOS Services Menu

    /// Invoked when the user selects "KindleWall'a Alıntı Ekle" from the Services menu.
    /// macOS passes the selected text via `pasteboard`.
    @objc func addClippingFromService(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.windows.first(where: { !($0 is NSPanel) }) {
            window.makeKeyAndOrderFront(nil)
        }
        // Brief delay so the window is visible before the sheet presents
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(
                name: Constants.Notifications.captureText,
                object: nil,
                userInfo: ["text": text]
            )
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotkeyManager.shared.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep the app running in menu bar even when the window is closed
        return false
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Shows notification banners even when KindleWall is the active application.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
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
