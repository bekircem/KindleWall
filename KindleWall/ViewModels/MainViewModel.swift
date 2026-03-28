import SwiftUI
import Observation

/// Manages the state for the main application view and coordinates services.
@Observable
final class MainViewModel {
    // MARK: - Published State

    var currentClipping: Clipping?
    var currentWallpaperImage: NSImage?
    var selectedStyle: WallpaperStyle
    var isLoading: Bool = false
    var errorMessage: String?
    var clippings: [Clipping] = []

    // MARK: - Dependencies

    private let parser: ClippingsParserProtocol
    private let generator: WallpaperGeneratorProtocol
    private let wallpaperManager: WallpaperManagerProtocol
    private let scheduler: SchedulerServiceProtocol
    private let storage: StorageServiceProtocol

    // MARK: - Init

    init(
        parser: ClippingsParserProtocol = ClippingsParser(),
        generator: WallpaperGeneratorProtocol = WallpaperGenerator(),
        wallpaperManager: WallpaperManagerProtocol? = nil,
        scheduler: SchedulerServiceProtocol = SchedulerService(),
        storage: StorageServiceProtocol = StorageService()
    ) {
        self.parser = parser
        self.generator = generator
        self.storage = storage
        self.scheduler = scheduler
        self.selectedStyle = storage.selectedStyle

        if let wm = wallpaperManager {
            self.wallpaperManager = wm
        } else {
            self.wallpaperManager = WallpaperManager(storageService: storage)
        }
    }

    // MARK: - Actions

    /// Loads clippings from the stored file bookmark.
    func loadClippings() {
        guard let fileURL = storage.resolveClippingsFileURL() else {
            errorMessage = "Lütfen My Clippings.txt dosyasını seçin."
            return
        }

        isLoading = true
        errorMessage = nil

        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { fileURL.stopAccessingSecurityScopedResource() }
        }

        do {
            clippings = try parser.parse(fileURL: fileURL)
            if clippings.isEmpty {
                errorMessage = "Dosyada alıntı bulunamadı."
            }
        } catch {
            errorMessage = (error as? KindleWallError)?.errorDescription ?? error.localizedDescription
        }

        isLoading = false
    }

    /// Loads clippings from a specific file URL (e.g., from onboarding).
    func loadClippings(from url: URL) {
        do {
            try storage.saveClippingsFileBookmark(for: url)
        } catch {
            errorMessage = (error as? KindleWallError)?.errorDescription ?? error.localizedDescription
            return
        }
        loadClippings()
    }

    /// Selects a random unshown clipping and generates a wallpaper preview.
    func selectRandomClipping() {
        guard !clippings.isEmpty else {
            errorMessage = "Yüklü alıntı yok."
            return
        }

        var shownIDs = storage.shownClippingIDs
        let unshown = clippings.filter { !shownIDs.contains($0.id) }

        let selected: Clipping
        if let next = unshown.randomElement() {
            selected = next
        } else {
            // All shown — reset and pick again
            shownIDs.removeAll()
            storage.shownClippingIDs = shownIDs
            selected = clippings.randomElement()!
        }

        currentClipping = selected
        shownIDs.insert(selected.id)
        storage.shownClippingIDs = shownIDs

        generatePreview()
    }

    /// Generates a wallpaper preview for the current clipping and style.
    func generatePreview() {
        guard let clipping = currentClipping else { return }
        guard let screen = NSScreen.main else {
            errorMessage = KindleWallError.screenNotAvailable.errorDescription
            return
        }

        let screenSize = screen.frame.size * screen.backingScaleFactor

        Task.detached { [generator, selectedStyle] in
            let image = generator.generateWallpaper(
                clipping: clipping,
                style: selectedStyle,
                screenSize: screenSize
            )
            await MainActor.run { [weak self] in
                self?.currentWallpaperImage = image
            }
        }
    }

    /// Applies the current wallpaper preview to the desktop.
    func applyWallpaper() {
        guard let image = currentWallpaperImage else { return }

        do {
            try wallpaperManager.setWallpaper(image: image)
        } catch {
            errorMessage = (error as? KindleWallError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Updates the wallpaper style and regenerates the preview.
    func updateStyle(_ style: WallpaperStyle) {
        selectedStyle = style
        storage.selectedStyle = style
        generatePreview()
    }

    /// Toggles the favorite status of the current clipping.
    func toggleFavorite() {
        guard let clipping = currentClipping else { return }
        var favorites = storage.favoriteClippingIDs
        if favorites.contains(clipping.id) {
            favorites.remove(clipping.id)
        } else {
            favorites.insert(clipping.id)
        }
        storage.favoriteClippingIDs = favorites
    }

    /// Returns whether the current clipping is a favorite.
    var isCurrentFavorite: Bool {
        guard let clipping = currentClipping else { return false }
        return storage.favoriteClippingIDs.contains(clipping.id)
    }

    /// Starts the automatic wallpaper change scheduler.
    func startScheduler() {
        scheduler.start { [weak self] in
            self?.selectRandomClipping()
            self?.applyWallpaper()
        }
    }

    /// Stops the scheduler.
    func stopScheduler() {
        scheduler.stop()
    }
}

// MARK: - CGSize Helper

private extension CGSize {
    static func * (lhs: CGSize, rhs: CGFloat) -> CGSize {
        CGSize(width: lhs.width * rhs, height: lhs.height * rhs)
    }
}
