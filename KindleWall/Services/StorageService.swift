import Foundation

// MARK: - Protocol

/// Protocol for persisting user preferences and application state.
protocol StorageServiceProtocol {
    /// The security-scoped bookmark data for the clippings file.
    var clippingsFileBookmark: Data? { get set }

    /// The selected wallpaper style.
    var selectedStyle: WallpaperStyle { get set }

    /// The schedule interval for wallpaper changes.
    var scheduleInterval: ScheduleInterval { get set }

    /// Custom schedule date (for .custom interval).
    var customScheduleDate: Date? { get set }

    /// IDs of clippings that have already been shown.
    var shownClippingIDs: Set<UUID> { get set }

    /// IDs of favorite clippings.
    var favoriteClippingIDs: Set<UUID> { get set }

    /// The URL of the wallpaper that was active before KindleWall.
    var previousWallpaperURL: URL? { get set }

    /// Whether the app should launch at login.
    var launchAtLogin: Bool { get set }

    /// Whether to show the menu bar icon.
    var showInMenuBar: Bool { get set }

    /// Whether to show notifications on wallpaper change.
    var showNotifications: Bool { get set }

    /// Whether the user has completed onboarding.
    var hasCompletedOnboarding: Bool { get set }

    /// Typography settings for wallpaper rendering.
    var typography: TypographySettings { get set }

    /// Whether to apply wallpaper to all Mission Control spaces (not just the active one).
    var applyToAllSpaces: Bool { get set }

    /// User-supplied metadata corrections keyed by original parsed book title.
    var bookMetadataOverrides: [String: BookMetadataOverride] { get set }

    /// IDs of all clippings seen across imports (for incremental merge detection).
    var persistedClippingIDs: Set<UUID> { get set }

    /// Manually entered clippings (not parsed from My Clippings.txt).
    var manualClippings: [Clipping] { get set }

    /// The active rotation mode for clipping selection.
    var rotationMode: RotationMode { get set }

    /// The book title currently being exhausted in bookByBook mode.
    var currentBookTitle: String? { get set }

    /// Raw book titles pinned by the user for pinnedBooks mode.
    var pinnedBookTitles: [String] { get set }

    /// Long-quote handling settings (auto-tighten + optional skip filter).
    var longQuote: LongQuoteSettings { get set }

    /// Key code for the global text-capture hotkey (default: 40 = K).
    var hotkeyKeyCode: Int { get set }

    /// Raw modifier flags for the global text-capture hotkey (default: ⌃⌥ = 786432).
    var hotkeyModifiers: Int { get set }

    /// Resolves the security-scoped bookmark to a file URL.
    /// - Returns: The resolved file URL, or nil if resolution fails.
    func resolveClippingsFileURL() -> URL?

    /// Creates and stores a security-scoped bookmark for the given URL.
    /// - Parameter url: The file URL to bookmark.
    /// - Throws: KindleWallError if bookmark creation fails.
    func saveClippingsFileBookmark(for url: URL) throws
}

// MARK: - Implementation

/// Persists user preferences using UserDefaults and security-scoped bookmarks.
final class StorageService: StorageServiceProtocol {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.cleanupRemovedFeatureKeys(in: defaults)
    }

    /// Removes orphaned UserDefaults keys left over from removed features.
    /// Idempotent — `removeObject` is a no-op when the key is absent.
    private static func cleanupRemovedFeatureKeys(in defaults: UserDefaults) {
        let removedKeys = ["liveWallpaperSettings"]
        for key in removedKeys {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Clippings File Bookmark

    var clippingsFileBookmark: Data? {
        get { defaults.data(forKey: Constants.StorageKeys.clippingsFileBookmark) }
        set { defaults.set(newValue, forKey: Constants.StorageKeys.clippingsFileBookmark) }
    }

    func resolveClippingsFileURL() -> URL? {
        guard let bookmarkData = clippingsFileBookmark else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale {
            // Try to refresh the bookmark
            if let newBookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                clippingsFileBookmark = newBookmark
            }
        }

        return url
    }

    func saveClippingsFileBookmark(for url: URL) throws {
        guard let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            throw KindleWallError.bookmarkCreationFailed
        }
        clippingsFileBookmark = bookmarkData
    }

    // MARK: - Style

    var selectedStyle: WallpaperStyle {
        get {
            guard let raw = defaults.string(forKey: Constants.StorageKeys.selectedStyle),
                  let style = WallpaperStyle(rawValue: raw) else {
                return .minimalDark
            }
            return style
        }
        set {
            defaults.set(newValue.rawValue, forKey: Constants.StorageKeys.selectedStyle)
            postUserStateChanged()
        }
    }

    // MARK: - Schedule

    var scheduleInterval: ScheduleInterval {
        get {
            guard let raw = defaults.string(forKey: Constants.StorageKeys.scheduleInterval),
                  let interval = ScheduleInterval(rawValue: raw) else {
                return .hourly
            }
            return interval
        }
        set {
            defaults.set(newValue.rawValue, forKey: Constants.StorageKeys.scheduleInterval)
            postUserStateChanged()
        }
    }

    var customScheduleDate: Date? {
        get { defaults.object(forKey: Constants.StorageKeys.customScheduleDate) as? Date }
        set {
            defaults.set(newValue, forKey: Constants.StorageKeys.customScheduleDate)
            postUserStateChanged()
        }
    }

    // MARK: - Shown Clippings

    var shownClippingIDs: Set<UUID> {
        get {
            guard let array = defaults.stringArray(forKey: Constants.StorageKeys.shownClippingIDs) else { return [] }
            return Set(array.compactMap { UUID(uuidString: $0) })
        }
        set {
            defaults.set(Array(newValue.map { $0.uuidString }), forKey: Constants.StorageKeys.shownClippingIDs)
            postUserStateChanged()
        }
    }

    // MARK: - Favorites

    var favoriteClippingIDs: Set<UUID> {
        get {
            guard let array = defaults.stringArray(forKey: Constants.StorageKeys.favoriteClippingIDs) else { return [] }
            return Set(array.compactMap { UUID(uuidString: $0) })
        }
        set {
            defaults.set(Array(newValue.map { $0.uuidString }), forKey: Constants.StorageKeys.favoriteClippingIDs)
            // Invariant: empty favorites cannot coexist with .favorites rotation mode.
            if newValue.isEmpty && rotationMode == .favorites {
                rotationMode = .allRandom
            }
            postUserStateChanged()
        }
    }

    // MARK: - Previous Wallpaper

    var previousWallpaperURL: URL? {
        get {
            guard let path = defaults.string(forKey: Constants.StorageKeys.previousWallpaperPath) else { return nil }
            return URL(fileURLWithPath: path)
        }
        set { defaults.set(newValue?.path, forKey: Constants.StorageKeys.previousWallpaperPath) }
    }

    // MARK: - General Settings

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Constants.StorageKeys.launchAtLogin) }
        set {
            defaults.set(newValue, forKey: Constants.StorageKeys.launchAtLogin)
            postUserStateChanged()
        }
    }

    var showInMenuBar: Bool {
        get { defaults.object(forKey: Constants.StorageKeys.showInMenuBar) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Constants.StorageKeys.showInMenuBar) }
    }

    var showNotifications: Bool {
        get { defaults.object(forKey: Constants.StorageKeys.showNotifications) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: Constants.StorageKeys.showNotifications)
            postUserStateChanged()
        }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Constants.StorageKeys.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Constants.StorageKeys.hasCompletedOnboarding) }
    }

    // MARK: - Spaces

    var applyToAllSpaces: Bool {
        get { defaults.object(forKey: Constants.StorageKeys.applyToAllSpaces) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: Constants.StorageKeys.applyToAllSpaces)
            postUserStateChanged()
        }
    }

    // MARK: - Book Metadata Overrides

    var bookMetadataOverrides: [String: BookMetadataOverride] {
        get {
            guard let data = defaults.data(forKey: Constants.StorageKeys.bookMetadataOverrides),
                  let overrides = try? JSONDecoder().decode([String: BookMetadataOverride].self, from: data)
            else { return [:] }
            return overrides
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Constants.StorageKeys.bookMetadataOverrides)
            }
            NotificationCenter.default.post(name: Constants.Notifications.bookOverridesChanged, object: nil)
        }
    }

    // MARK: - Persisted Clipping IDs

    var persistedClippingIDs: Set<UUID> {
        get {
            guard let array = defaults.stringArray(forKey: Constants.StorageKeys.persistedClippingIDs) else { return [] }
            return Set(array.compactMap { UUID(uuidString: $0) })
        }
        set {
            defaults.set(Array(newValue.map { $0.uuidString }), forKey: Constants.StorageKeys.persistedClippingIDs)
            postUserStateChanged()
        }
    }

    // MARK: - Manual Clippings

    var manualClippings: [Clipping] {
        get {
            guard let data = defaults.data(forKey: Constants.StorageKeys.manualClippings),
                  let clippings = try? JSONDecoder().decode([Clipping].self, from: data)
            else { return [] }
            return clippings
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Constants.StorageKeys.manualClippings)
            }
            NotificationCenter.default.post(name: Constants.Notifications.manualClippingsChanged, object: nil)
        }
    }

    // MARK: - Rotation Mode

    var rotationMode: RotationMode {
        get {
            guard let raw = defaults.string(forKey: Constants.StorageKeys.rotationMode),
                  let mode = RotationMode(rawValue: raw) else { return .allRandom }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Constants.StorageKeys.rotationMode)
            postUserStateChanged()
        }
    }

    // MARK: - Current Book (bookByBook state)

    var currentBookTitle: String? {
        get { defaults.string(forKey: Constants.StorageKeys.currentBookTitle) }
        set {
            defaults.set(newValue, forKey: Constants.StorageKeys.currentBookTitle)
            postUserStateChanged()
        }
    }

    // MARK: - Pinned Book Titles

    var pinnedBookTitles: [String] {
        get { defaults.stringArray(forKey: Constants.StorageKeys.pinnedBookTitles) ?? [] }
        set {
            defaults.set(newValue, forKey: Constants.StorageKeys.pinnedBookTitles)
            postUserStateChanged()
        }
    }

    // MARK: - Global Hotkey

    var hotkeyKeyCode: Int {
        get { defaults.object(forKey: Constants.StorageKeys.hotkeyKeyCode) != nil
                ? defaults.integer(forKey: Constants.StorageKeys.hotkeyKeyCode)
                : 40 }
        set {
            defaults.set(newValue, forKey: Constants.StorageKeys.hotkeyKeyCode)
            postUserStateChanged()
        }
    }

    var hotkeyModifiers: Int {
        get { defaults.object(forKey: Constants.StorageKeys.hotkeyModifiers) != nil
                ? defaults.integer(forKey: Constants.StorageKeys.hotkeyModifiers)
                : 786432 /* NSEvent.ModifierFlags([.control, .option]).rawValue */ }
        set {
            defaults.set(newValue, forKey: Constants.StorageKeys.hotkeyModifiers)
            postUserStateChanged()
        }
    }

    // MARK: - Long Quote Settings

    var longQuote: LongQuoteSettings {
        get {
            guard let data = defaults.data(forKey: Constants.StorageKeys.longQuoteSettings),
                  let settings = try? JSONDecoder().decode(LongQuoteSettings.self, from: data)
            else { return .default }
            return settings
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Constants.StorageKeys.longQuoteSettings)
            }
            postUserStateChanged()
        }
    }

    // MARK: - Typography

    var typography: TypographySettings {
        get {
            guard let data = defaults.data(forKey: Constants.StorageKeys.typographySettings),
                  let settings = try? JSONDecoder().decode(TypographySettings.self, from: data) else {
                return .default
            }
            return settings
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Constants.StorageKeys.typographySettings)
            }
            postUserStateChanged()
        }
    }

    // MARK: - Sync notifications

    private func postUserStateChanged() {
        NotificationCenter.default.post(name: Constants.Notifications.userStateChanged, object: nil)
    }
}
