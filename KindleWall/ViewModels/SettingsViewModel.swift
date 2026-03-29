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
    var clippingsFilePath: String?
    var clippingsCount: Int = 0

    // MARK: - Dependencies

    private var storage: StorageServiceProtocol

    init(storage: StorageServiceProtocol = StorageService()) {
        self.storage = storage
        self.selectedStyle = storage.selectedStyle
        self.scheduleInterval = storage.scheduleInterval
        self.customScheduleDate = storage.customScheduleDate ?? Date()
        self.launchAtLogin = storage.launchAtLogin
        self.showInMenuBar = storage.showInMenuBar
        self.showNotifications = storage.showNotifications
        self.clippingsFilePath = storage.resolveClippingsFileURL()?.path
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

        updateLoginItem()
    }

    /// Saves the selected style and notifies.
    func updateStyle(_ style: WallpaperStyle) {
        selectedStyle = style
        storage.selectedStyle = style
    }

    /// Updates the schedule interval.
    func updateSchedule(_ interval: ScheduleInterval) {
        scheduleInterval = interval
        storage.scheduleInterval = interval
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
        if launchAtLogin {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }
}
