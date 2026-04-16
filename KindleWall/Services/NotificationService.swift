import UserNotifications
import Foundation

// MARK: - Protocol

/// Handles local notification permission requests and delivery.
protocol NotificationServiceProtocol {
    /// Requests local notification authorization. Returns true if granted.
    func requestAuthorization() async -> Bool
    /// Sends a notification announcing a new wallpaper clipping.
    func sendWallpaperChangedNotification(clipping: Clipping)
}

// MARK: - Implementation

final class NotificationService: NotificationServiceProtocol {

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert])
        } catch {
            return false
        }
    }

    func sendWallpaperChangedNotification(clipping: Clipping) {
        let content = UNMutableNotificationContent()
        content.title = clipping.bookTitle
        if let author = clipping.author {
            content.subtitle = author
        }
        // Truncate long quotes so the notification banner stays readable
        content.body = String(clipping.text.prefix(200))
        content.sound = nil  // wallpaper rotation is a silent event

        // Use clipping ID as identifier — same clipping delivered again replaces the old one
        let request = UNNotificationRequest(
            identifier: "wallpaper-\(clipping.id.uuidString)",
            content: content,
            trigger: nil  // deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }
}
