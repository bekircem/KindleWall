import SwiftUI
import Observation
import ServiceManagement

/// Manages the state for the settings view.
@Observable
final class SettingsViewModel {
    // MARK: - State

    var selectedStyle: WallpaperStyle
    var scheduleInterval: ScheduleInterval
    var customScheduleDate: Date
    var launchAtLogin: Bool
    var showInMenuBar: Bool
    var showNotifications: Bool
    var applyToAllSpaces: Bool
    var clippingsFilePath: String?
    var decorativeStyle: TypographySettings.DecorationStyle
    var backgroundStartColor: Color
    var backgroundEndColor: Color
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
        self.selectedStyle = storage.selectedStyle
        self.scheduleInterval = storage.scheduleInterval
        self.customScheduleDate = storage.customScheduleDate ?? Date()
        let smStatus = SMAppService.mainApp.status
        let isRegistered = smStatus == .enabled || smStatus == .requiresApproval
        self.launchAtLogin = isRegistered
        self.showInMenuBar = storage.showInMenuBar
        self.showNotifications = storage.showNotifications
        self.applyToAllSpaces = storage.applyToAllSpaces
        self.clippingsFilePath = storage.resolveClippingsFileURL()?.path
        let t = storage.typography
        self.decorativeStyle = t.decorativeStyle
        self.backgroundStartColor = t.backgroundStartColorHex.flatMap { Color(hex: $0) } ?? Color(hex: "667EEA") ?? .purple
        self.backgroundEndColor   = t.backgroundEndColorHex.flatMap   { Color(hex: $0) } ?? Color(hex: "764BA2") ?? .indigo
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

    /// Saves all current settings to storage.
    func saveSettings() {
        storage.selectedStyle = selectedStyle
        storage.scheduleInterval = scheduleInterval
        storage.customScheduleDate = customScheduleDate
        storage.launchAtLogin = launchAtLogin
        storage.showInMenuBar = showInMenuBar
        storage.showNotifications = showNotifications
        storage.applyToAllSpaces = applyToAllSpaces

        updateLoginItem()
    }

    /// Saves the selected style and notifies.
    func updateStyle(_ style: WallpaperStyle) {
        selectedStyle = style
        storage.selectedStyle = style
    }

    /// Re-reads the typography values this view model mirrors.
    ///
    /// Needed because picking a wallpaper style now rewrites typography in `MainViewModel`;
    /// without this the Tipografi controls would keep showing the pre-change decoration.
    func reloadTypographyFromStorage() {
        decorativeStyle = storage.typography.decorativeStyle
    }

    /// Saves the selected decoration style to storage.
    func updateDecorativeStyle(_ style: TypographySettings.DecorationStyle) {
        decorativeStyle = style
        var t = storage.typography
        t.decorativeStyle = style
        storage.typography = t
    }

    /// Saves the custom background gradient colors to storage.
    func updateBackgroundGradient() {
        var t = storage.typography
        t.backgroundStartColorHex = backgroundStartColor.hexString
        t.backgroundEndColorHex   = backgroundEndColor.hexString
        storage.typography = t
    }

    /// Clears the custom background gradient; style defaults are restored.
    func resetBackgroundGradient() {
        var t = storage.typography
        t.backgroundStartColorHex = nil
        t.backgroundEndColorHex   = nil
        storage.typography = t
        backgroundStartColor = Color(hex: "667EEA") ?? .purple
        backgroundEndColor   = Color(hex: "764BA2") ?? .indigo
    }

    /// Updates the schedule interval.
    func updateSchedule(_ interval: ScheduleInterval) {
        scheduleInterval = interval
        storage.scheduleInterval = interval
    }

    /// Persists the selected rotation mode.
    func updateRotationMode(_ mode: RotationMode) {
        rotationMode = mode
        storage.rotationMode = mode
    }

    /// Toggles a book title's pinned status and persists the updated list.
    func togglePinnedBook(_ title: String) {
        if pinnedBookTitles.contains(title) {
            pinnedBookTitles.remove(title)
        } else {
            pinnedBookTitles.insert(title)
        }
        storage.pinnedBookTitles = Array(pinnedBookTitles).sorted()
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
