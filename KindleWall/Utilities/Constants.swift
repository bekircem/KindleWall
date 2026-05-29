import Foundation
import SwiftUI

/// Application-wide constants.
enum Constants {
    /// App metadata
    enum App {
        static let name = "KindleWall"
        static let bundleIdentifier = "com.kindlewall.app"
        static let version = "1.1.0"
    }

    /// Directory and file paths
    enum Paths {
        static let appSupportDirectory: URL = {
            let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            return paths[0].appendingPathComponent(Constants.App.name)
        }()

        static let wallpapersDirectory: URL = {
            appSupportDirectory.appendingPathComponent("wallpapers")
        }()

        static let coversDirectory: URL = {
            appSupportDirectory.appendingPathComponent("covers")
        }()
    }

    /// Wallpaper rendering constants
    enum Wallpaper {
        static let paddingRatio: CGFloat = 0.17
        static let minFontSize: CGFloat = 18
        static let absoluteMinFontSize: CGFloat = 14
        static let maxFontSize: CGFloat = 48
        static let decorativeQuoteFontSize: CGFloat = 120
        static let decorativeQuoteOpacity: CGFloat = 0.15
        static let metaFontSizeRange: ClosedRange<CGFloat> = 16...20

    }

    /// Storage keys for UserDefaults
    enum StorageKeys {
        static let clippingsFileBookmark = "clippingsFileBookmark"
        static let selectedStyle = "selectedStyle"
        static let scheduleInterval = "scheduleInterval"
        static let customScheduleDate = "customScheduleDate"
        static let shownClippingIDs = "shownClippingIDs"
        static let favoriteClippingIDs = "favoriteClippingIDs"
        static let previousWallpaperPath = "previousWallpaperPath"
        static let launchAtLogin = "launchAtLogin"
        static let showInMenuBar = "showInMenuBar"
        static let showNotifications = "showNotifications"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let typographySettings = "typographySettings"
        static let applyToAllSpaces = "applyToAllSpaces"
        static let bookMetadataOverrides = "bookMetadataOverrides"
        static let persistedClippingIDs = "persistedClippingIDs"
        static let rotationMode         = "rotationMode"
        static let currentBookTitle     = "currentBookTitle"
        static let pinnedBookTitles     = "pinnedBookTitles"
        static let manualClippings      = "manualClippings"
        static let hotkeyKeyCode        = "hotkeyKeyCode"
        static let hotkeyModifiers      = "hotkeyModifiers"
        static let longQuoteSettings    = "longQuoteSettings"

        // CloudKit sync engine state (not synced — bookkeeping only)
        static let cloudKitChangeToken          = "cloudKitChangeToken"
        static let cloudKitZoneCreated          = "cloudKitZoneCreated"
        static let cloudKitSubscriptionCreated  = "cloudKitSubscriptionCreated"
        static let cloudKitLastSyncedAt         = "cloudKitLastSyncedAt"
        /// Last-pushed snapshot of synced sets/lists — used to compute deletion diffs.
        static let cloudKitSyncSnapshot         = "cloudKitSyncSnapshot"
    }

    /// Internal notification names
    enum Notifications {
        static let captureText = Notification.Name("kindlewall.captureText")

        /// Posted when any UserState property (settings + ID sets) changes locally.
        /// CloudKitSyncService listens to schedule a debounced push.
        static let userStateChanged = Notification.Name("kindlewall.userStateChanged")

        /// Posted when the manualClippings array changes.
        static let manualClippingsChanged = Notification.Name("kindlewall.manualClippingsChanged")

        /// Posted when the bookMetadataOverrides dictionary changes.
        static let bookOverridesChanged = Notification.Name("kindlewall.bookOverridesChanged")

        /// Posted by AppDelegate when a CKNotification remote push arrives.
        static let cloudKitRemotePush = Notification.Name("kindlewall.cloudKitRemotePush")
    }

    /// Menu bar icon name (SF Symbols)
    enum Icons {
        static let menuBarIcon  = "text.quote"
        static let captureIcon  = "text.badge.plus"
        static let newQuote = "dice"
        static let favorite = "heart"
        static let favoriteFilled = "heart.fill"
        static let settings = "gear"
        static let library = "books.vertical"
        static let currentQuote = "quote.opening"
        static let pause = "pause.circle"
        static let play = "play.circle"
        static let refresh = "arrow.clockwise"
        static let wallpaper = "photo"
    }
}
