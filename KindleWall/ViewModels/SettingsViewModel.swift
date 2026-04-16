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
        self.backgroundStartColor = t.backgroundStartColorHex.flatMap { Color(hex: $0) } ?? Color(hex: "667EEA")!
        self.backgroundEndColor   = t.backgroundEndColorHex.flatMap   { Color(hex: $0) } ?? Color(hex: "764BA2")!
        self.rotationMode = storage.rotationMode
        self.pinnedBookTitles = Set(storage.pinnedBookTitles)
        self.storage.launchAtLogin = isRegistered  // UserDefaults'u gerçek SMAppService durumuna hizala
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
        backgroundStartColor = Color(hex: "667EEA")!
        backgroundEndColor   = Color(hex: "764BA2")!
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
