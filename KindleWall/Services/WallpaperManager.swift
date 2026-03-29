import AppKit
import Foundation

// MARK: - Protocol

/// Protocol for applying wallpaper images to the desktop.
protocol WallpaperManagerProtocol {
    /// Sets the desktop wallpaper from an NSImage on all screens.
    /// - Parameter image: The wallpaper image to apply.
    /// - Throws: KindleWallError if the wallpaper cannot be applied.
    func setWallpaper(image: NSImage) throws

    /// Sets the desktop wallpaper from a file URL on all screens.
    /// - Parameter fileURL: The URL of the wallpaper image file.
    /// - Throws: KindleWallError if the wallpaper cannot be applied.
    func setWallpaper(fileURL: URL) throws

    /// Returns the URL of the current desktop wallpaper (before KindleWall changed it).
    var previousWallpaperURL: URL? { get }

    /// Restores the wallpaper to the one before KindleWall last changed it.
    /// - Throws: KindleWallError if restoring fails.
    func restorePreviousWallpaper() throws
}

// MARK: - Implementation

/// Manages applying and restoring desktop wallpapers using NSWorkspace.
final class WallpaperManager: WallpaperManagerProtocol {
    private var storageService: StorageServiceProtocol

    private(set) var previousWallpaperURL: URL?

    init(storageService: StorageServiceProtocol) {
        self.storageService = storageService
        self.previousWallpaperURL = storageService.previousWallpaperURL
    }

    func setWallpaper(image: NSImage) throws {
        // Save image to disk first
        let fileName = "kindlewall_\(UUID().uuidString).png"
        let fileURL = Constants.Paths.wallpapersDirectory.appendingPathComponent(fileName)

        try ensureWallpaperDirectoryExists()
        try image.savePNG(to: fileURL)
        try setWallpaper(fileURL: fileURL)
    }

    func setWallpaper(fileURL: URL) throws {
        // Capture current wallpaper before changing
        captureCurrentWallpaper()

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            throw KindleWallError.screenNotAvailable
        }

        for screen in screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(fileURL, for: screen, options: [:])
            } catch {
                throw KindleWallError.wallpaperApplyFailed(underlying: error)
            }
        }
    }

    func restorePreviousWallpaper() throws {
        guard let previousURL = previousWallpaperURL else { return }
        let screens = NSScreen.screens
        for screen in screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(previousURL, for: screen, options: [:])
            } catch {
                throw KindleWallError.wallpaperApplyFailed(underlying: error)
            }
        }
    }

    // MARK: - Private

    private func captureCurrentWallpaper() {
        if let screen = NSScreen.main {
            let currentURL = NSWorkspace.shared.desktopImageURL(for: screen)
            previousWallpaperURL = currentURL
            storageService.previousWallpaperURL = currentURL
        }
    }

    private func ensureWallpaperDirectoryExists() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: Constants.Paths.wallpapersDirectory.path) {
            do {
                try fm.createDirectory(at: Constants.Paths.wallpapersDirectory, withIntermediateDirectories: true)
            } catch {
                throw KindleWallError.directoryCreationFailed(underlying: error)
            }
        }
    }
}
