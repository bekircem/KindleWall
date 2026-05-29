import Foundation

/// CloudKit record type and field name constants. Keeping them centralized prevents
/// stringly-typed bugs and makes schema changes traceable.
enum SyncSchema {
    static let containerIdentifier = "iCloud.com.kindlewall.app"
    static let zoneName = "KindleWallZone"
    static let subscriptionID = "kindlewall-private-db-subscription"

    enum RecordType {
        static let userState = "UserState"
        static let manualClipping = "ManualClipping"
        static let bookOverride = "BookOverride"
    }

    /// Singleton record name for `UserState` — same on every device for this user.
    static let userStateRecordName = "userState"

    enum UserStateField {
        static let selectedStyle = "selectedStyle"
        static let scheduleInterval = "scheduleInterval"
        static let customScheduleDate = "customScheduleDate"
        static let rotationMode = "rotationMode"
        static let currentBookTitle = "currentBookTitle"
        static let launchAtLogin = "launchAtLogin"
        static let showNotifications = "showNotifications"
        static let applyToAllSpaces = "applyToAllSpaces"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        // JSON-encoded blobs (Codable structs)
        static let typographyJSON = "typographyJSON"
        static let longQuoteJSON = "longQuoteJSON"
        // String arrays (UUID strings / titles)
        static let favoriteClippingIDs = "favoriteClippingIDs"
        static let shownClippingIDs = "shownClippingIDs"
        static let persistedClippingIDs = "persistedClippingIDs"
        static let pinnedBookTitles = "pinnedBookTitles"
    }

    enum ManualClippingField {
        static let bookTitle = "bookTitle"
        static let author = "author"
        static let text = "text"
        static let page = "page"
        static let location = "location"
        static let dateAdded = "dateAdded"
        static let type = "type"
    }

    enum BookOverrideField {
        static let originalTitle = "originalTitle"
        static let displayTitle = "displayTitle"
        static let displayAuthor = "displayAuthor"
    }
}
