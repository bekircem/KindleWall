import SwiftUI
import Observation
import ServiceManagement

/// Application-level preferences: launch, menu bar, notifications, spaces, schedule cadence,
/// rotation and long-quote handling.
///
/// Deliberately owns **no design state**. Style, typography, decoration and the background
/// gradient live on `MainViewModel` alone. When both view models mirrored them, they drifted:
/// picking a style from the menu bar left this one stale, and `saveSettings()` could write that
/// stale value back over the user's real choice.
@Observable
final class SettingsViewModel {
    // MARK: - State

    var scheduleInterval: ScheduleInterval
    var customScheduleDate: Date
    var launchAtLogin: Bool
    var showInMenuBar: Bool
    var showNotifications: Bool
    var applyToAllSpaces: Bool
    var syncAllSpaces: Bool
    var dynamicWallpaperEnabled: Bool
    var clippingsFilePath: String?
    var loginItemError: String? = nil
    var rotationMode: RotationMode
    var pinnedBookTitles: Set<String>

    // Long-quote handling
    var autoTightenLongQuotes: Bool
    var skipLongQuotesEnabled: Bool
    var longQuoteThreshold: Int
    var longQuoteUnit: LengthUnit
    var tightenThreshold: Int
    var tightenUnit: LengthUnit
    var tightenMinFontPt: Double
    var tightenLineSpacingMultiplier: Double

    // MARK: - Dependencies

    private var storage: StorageServiceProtocol

    init(storage: StorageServiceProtocol = StorageService()) {
        self.storage = storage
        self.scheduleInterval = storage.scheduleInterval
        self.customScheduleDate = storage.customScheduleDate ?? Date()
        let smStatus = SMAppService.mainApp.status
        let isRegistered = smStatus == .enabled || smStatus == .requiresApproval
        self.launchAtLogin = isRegistered
        self.showInMenuBar = storage.showInMenuBar
        self.showNotifications = storage.showNotifications
        self.applyToAllSpaces = storage.applyToAllSpaces
        self.syncAllSpaces = storage.syncAllSpaces
        self.dynamicWallpaperEnabled = storage.dynamicWallpaperEnabled
        self.clippingsFilePath = storage.resolveClippingsFileURL()?.path
        self.rotationMode = storage.rotationMode
        self.pinnedBookTitles = Set(storage.pinnedBookTitles)

        let longQuote = storage.longQuote
        self.autoTightenLongQuotes          = longQuote.autoTightenEnabled
        self.skipLongQuotesEnabled          = longQuote.skipEnabled
        self.longQuoteThreshold             = longQuote.skipThreshold
        self.longQuoteUnit                  = longQuote.skipUnit
        self.tightenThreshold               = longQuote.tightenThreshold
        self.tightenUnit                    = longQuote.tightenUnit
        self.tightenMinFontPt               = longQuote.minFontPt
        self.tightenLineSpacingMultiplier   = longQuote.lineSpacingMultiplier

        // Must come after all stored properties are initialized (uses self).
        self.storage.launchAtLogin = isRegistered
    }

    // MARK: - Actions

    /// Saves the app-level toggles to storage.
    ///
    /// Style and schedule are deliberately absent: they are written by whoever owns them
    /// (`MainViewModel`), so a General-page toggle can no longer flush a stale copy of either.
    func saveSettings() {
        storage.launchAtLogin = launchAtLogin
        storage.showInMenuBar = showInMenuBar
        storage.showNotifications = showNotifications
        storage.applyToAllSpaces = applyToAllSpaces
        storage.syncAllSpaces = syncAllSpaces

        updateLoginItem()
    }

    /// Persists the dynamic-wallpaper toggle.
    func updateDynamicWallpaperEnabled() {
        storage.dynamicWallpaperEnabled = dynamicWallpaperEnabled
    }

    /// Mirrors the schedule interval for the picker. Persisting is `MainViewModel`'s job, since
    /// it also has to retune the running scheduler.
    func updateSchedule(_ interval: ScheduleInterval) {
        scheduleInterval = interval
    }

    /// Mirrors the rotation mode for the picker; `MainViewModel` persists it and resets the
    /// book-by-book cursor.
    func updateRotationMode(_ mode: RotationMode) {
        rotationMode = mode
    }

    /// Toggles a book title's pinned status. Persisted by `MainViewModel` via the
    /// `onPinnedBooksChanged` action, so the list is only ever written once.
    func togglePinnedBook(_ title: String) {
        if pinnedBookTitles.contains(title) {
            pinnedBookTitles.remove(title)
        } else {
            pinnedBookTitles.insert(title)
        }
    }

    /// Returns true if the given book title is currently pinned.
    func isBookPinned(_ title: String) -> Bool {
        pinnedBookTitles.contains(title)
    }

    /// True when the user has at least one favorited clipping.
    var hasFavorites: Bool {
        !storage.favoriteClippingIDs.isEmpty
    }

    /// Total favorited clipping count, for the description label.
    var favoriteCount: Int {
        storage.favoriteClippingIDs.count
    }

    /// Opens a file panel to select the My Clippings.txt file.
    /// - Returns: The selected file URL, or nil if cancelled.
    func selectClippingsFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "My Clippings.txt Dosyasını Seçin"
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        do {
            try storage.saveClippingsFileBookmark(for: url)
            clippingsFilePath = url.path
            return url
        } catch {
            return nil
        }
    }

    /// Persists the current long-quote handling settings to storage.
    func updateLongQuoteSettings() {
        clampLongQuoteValues()
        storage.longQuote = LongQuoteSettings(
            skipEnabled: skipLongQuotesEnabled,
            skipThreshold: longQuoteThreshold,
            skipUnit: longQuoteUnit,
            autoTightenEnabled: autoTightenLongQuotes,
            tightenThreshold: tightenThreshold,
            tightenUnit: tightenUnit,
            minFontPt: tightenMinFontPt,
            lineSpacingMultiplier: tightenLineSpacingMultiplier
        )
    }

    /// Switches the skip threshold unit and clamps the threshold to the new unit's typical range.
    func updateLongQuoteUnit(_ unit: LengthUnit) {
        longQuoteUnit = unit
        let range = longQuoteRange(for: unit)
        if !range.contains(longQuoteThreshold) {
            longQuoteThreshold = unit == .characters ? 500 : 100
        }
        updateLongQuoteSettings()
    }

    /// Switches the auto-tighten unit and clamps the threshold to the new unit's typical range.
    func updateTightenUnit(_ unit: LengthUnit) {
        tightenUnit = unit
        let range = tightenThresholdRange(for: unit)
        if !range.contains(tightenThreshold) {
            tightenThreshold = unit == .characters ? 250 : 50
        }
        updateLongQuoteSettings()
    }

    /// Resets only the tightening typography (min font + line spacing) — threshold is preserved.
    func resetLongQuoteTypography() {
        tightenMinFontPt = LongQuoteSettings.default.minFontPt
        tightenLineSpacingMultiplier = LongQuoteSettings.default.lineSpacingMultiplier
        updateLongQuoteSettings()
    }

    /// Sensible Stepper / TextField bounds per unit for the skip threshold.
    func longQuoteRange(for unit: LengthUnit) -> ClosedRange<Int> {
        switch unit {
        case .characters: return 100...5000
        case .words:      return 20...1000
        }
    }

    /// Stepper increment per unit (skip threshold).
    func longQuoteStep(for unit: LengthUnit) -> Int {
        switch unit {
        case .characters: return 50
        case .words:      return 10
        }
    }

    /// Sensible Stepper / TextField bounds per unit for the tighten threshold.
    func tightenThresholdRange(for unit: LengthUnit) -> ClosedRange<Int> {
        switch unit {
        case .characters: return 50...3000
        case .words:      return 10...600
        }
    }

    /// Stepper increment per unit (tighten threshold).
    func tightenThresholdStep(for unit: LengthUnit) -> Int {
        switch unit {
        case .characters: return 25
        case .words:      return 5
        }
    }

    /// Clamps numeric fields to their valid ranges before persisting.
    /// Protects against the user typing values outside the supported range.
    private func clampLongQuoteValues() {
        let skipRange = longQuoteRange(for: longQuoteUnit)
        longQuoteThreshold = min(max(longQuoteThreshold, skipRange.lowerBound), skipRange.upperBound)

        let tightRange = tightenThresholdRange(for: tightenUnit)
        tightenThreshold = min(max(tightenThreshold, tightRange.lowerBound), tightRange.upperBound)

        tightenMinFontPt = min(max(tightenMinFontPt, 10.0), 20.0)
        tightenLineSpacingMultiplier = min(max(tightenLineSpacingMultiplier, 0.15), 0.45)
    }

    // MARK: - Private

    private func updateLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = "Başlangıç ayarı güncellenemedi: \(error.localizedDescription)"
            launchAtLogin = !launchAtLogin
            storage.launchAtLogin = launchAtLogin
        }
    }
}
