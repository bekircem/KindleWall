import SwiftUI
import Observation

/// Manages the state for the main application view and coordinates services.
@Observable
final class MainViewModel {
    // MARK: - Published State

    var currentClipping: Clipping?
    var currentWallpaperImage: NSImage?
    var selectedStyle: WallpaperStyle
    var typography: TypographySettings = .default
    var isLoading: Bool = false
    var isApplying: Bool = false
    var applySuccess: Bool = false
    var errorMessage: String?
    var clippings: [Clipping] = []
    var pinnedBookTitles: Set<String> = []
    private(set) var isSchedulerPaused: Bool = false
    var pendingCaptureText: String? = nil

    // MARK: - Dependencies

    private let parser: ClippingsParserProtocol
    private let generator: WallpaperGeneratorProtocol
    private let wallpaperManager: WallpaperManagerProtocol
    private var scheduler: SchedulerServiceProtocol
    private var storage: StorageServiceProtocol
    private let notificationService: NotificationServiceProtocol
    let importState: ImportState

    // MARK: - Preview task management

    private var previewTask: Task<Void, Never>?
    private var previewGeneration: Int = 0
    private var typographyUpdateTask: Task<Void, Never>?

    // MARK: - Import task management

    private var importTask: Task<Void, Never>?

    // MARK: - Init

    init(
        parser: ClippingsParserProtocol = ClippingsParser(),
        generator: WallpaperGeneratorProtocol = WallpaperGenerator(),
        wallpaperManager: WallpaperManagerProtocol? = nil,
        scheduler: SchedulerServiceProtocol = SchedulerService(),
        storage: StorageServiceProtocol = StorageService(),
        importState: ImportState = ImportState(),
        notificationService: NotificationServiceProtocol = NotificationService()
    ) {
        self.parser = parser
        self.generator = generator
        self.storage = storage
        self.scheduler = scheduler
        self.notificationService = notificationService
        self.selectedStyle = storage.selectedStyle
        self.typography = storage.typography
        self.pinnedBookTitles = Set(storage.pinnedBookTitles)
        self.importState = importState

        if let wm = wallpaperManager {
            self.wallpaperManager = wm
        } else {
            self.wallpaperManager = WallpaperManager(storageService: storage)
        }

        // Restore stored schedule interval so the scheduler fires at the user's configured cadence
        self.scheduler.interval = storage.scheduleInterval
        if let customDate = storage.customScheduleDate {
            self.scheduler.customDate = customDate
        }

        // Listen for text captured via Services menu or global hotkey
        NotificationCenter.default.addObserver(
            forName: Constants.Notifications.captureText,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.pendingCaptureText = notification.userInfo?["text"] as? String
        }
    }

    // MARK: - Import

    /// Imports clippings from a file URL (or the stored bookmark). Runs async with
    /// progress reporting and incremental merge.
    func importClippings(from url: URL? = nil) {
        guard !importState.isRunning else { return }

        let fileURL: URL
        if let url {
            do {
                try storage.saveClippingsFileBookmark(for: url)
            } catch {
                errorMessage = (error as? KindleWallError)?.errorDescription ?? error.localizedDescription
                return
            }
            fileURL = url
        } else {
            guard let resolved = storage.resolveClippingsFileURL() else {
                errorMessage = "Lütfen My Clippings.txt dosyasını seçin."
                return
            }
            fileURL = resolved
        }

        let started = Date()
        importState.phase = .running
        importState.progress = 0
        importState.summary = nil
        importState.currentBook = nil
        errorMessage = nil

        importTask?.cancel()
        importTask = Task { [weak self] in
            guard let self else { return }

            let accessing = fileURL.startAccessingSecurityScopedResource()
            defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }

            do {
                let parsed = try await self.parser.parse(fileURL: fileURL) { progress, book in
                    self.importState.progress = progress
                    self.importState.currentBook = book
                }

                await MainActor.run {
                    self.mergeClippings(parsed, started: started)
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.importState.phase = .idle
                }
            } catch {
                await MainActor.run {
                    let message = (error as? KindleWallError)?.errorDescription ?? error.localizedDescription
                    self.importState.phase = .failed(message)
                    self.errorMessage = message
                }
            }
        }
    }

    /// Merges parsed clippings with existing data, computing new vs. known counts.
    @MainActor
    private func mergeClippings(_ incoming: [Clipping], started: Date) {
        let knownIDs = storage.persistedClippingIDs
        let existingBookTitles = Set(clippings.map(\.bookTitle))

        let newClippings = incoming.filter { !knownIDs.contains($0.id) }

        let manual = storage.manualClippings
        let combined = incoming + manual
        clippings = combined
        storage.persistedClippingIDs = Set(combined.map(\.id))

        let newBookTitles = Set(newClippings.map(\.bookTitle)).subtracting(existingBookTitles)

        importState.summary = ImportSummary(
            totalClippings: incoming.count,
            newClippings: newClippings.count,
            totalBooks: Set(incoming.map(\.bookTitle)).count,
            newBooks: newBookTitles.count,
            duration: Date().timeIntervalSince(started)
        )
        importState.phase = .completed
        importState.progress = 1.0

        if currentClipping == nil && !clippings.isEmpty {
            selectRandomClipping()
        }
    }

    // MARK: - Legacy loaders (redirect to importClippings)

    /// Loads clippings from the stored file bookmark.
    func loadClippings() {
        // Pre-populate with manual clippings so they show even when no Kindle file is set
        let manual = storage.manualClippings
        if !manual.isEmpty && clippings.isEmpty {
            clippings = manual
        }
        importClippings()
    }

    /// Loads clippings from a specific file URL (e.g., from onboarding).
    func loadClippings(from url: URL) {
        importClippings(from: url)
    }

    // MARK: - Actions

    /// Selects the next clipping according to the active rotation mode and generates a preview.
    func selectRandomClipping() {
        guard !clippings.isEmpty else {
            errorMessage = "Yüklü alıntı yok."
            return
        }
        errorMessage = nil
        switch storage.rotationMode {
        case .allRandom:   selectAllRandom()
        case .bookByBook:  selectBookByBook()
        case .pinnedBooks: selectFromPinnedBooks()
        }
        generatePreview()
    }

    /// Selects a random clipping from all loaded clippings, cycling without repeat.
    private func selectAllRandom() {
        var shownIDs = storage.shownClippingIDs
        let unshown = clippings.filter { !shownIDs.contains($0.id) }
        if let next = unshown.randomElement() {
            currentClipping = next
            shownIDs.insert(next.id)
        } else {
            shownIDs.removeAll()
            storage.shownClippingIDs = shownIDs
            guard let selected = clippings.randomElement() else { return }
            currentClipping = selected
            shownIDs.insert(selected.id)
        }
        storage.shownClippingIDs = shownIDs
    }

    /// Selects a clipping book-by-book, exhausting all quotes in a book before moving on.
    private func selectBookByBook() {
        var shownIDs = storage.shownClippingIDs

        // Determine active book; pick randomly if none stored or book no longer exists
        let activeBookTitle: String
        if let stored = storage.currentBookTitle,
           clippings.contains(where: { $0.bookTitle == stored }) {
            activeBookTitle = stored
        } else {
            let allTitles = Array(Set(clippings.map(\.bookTitle)))
            guard let picked = allTitles.randomElement() else { return }
            activeBookTitle = picked
            storage.currentBookTitle = picked
        }

        let bookClippings = clippings.filter { $0.bookTitle == activeBookTitle }
        let unshown = bookClippings.filter { !shownIDs.contains($0.id) }

        if let selected = unshown.randomElement() {
            // Still have unshown quotes in the current book
            currentClipping = selected
            shownIDs.insert(selected.id)
            storage.shownClippingIDs = shownIDs
        } else {
            // Book exhausted — pick a new one
            let allTitles = Array(Set(clippings.map(\.bookTitle)))
            let candidates = allTitles.count > 1
                ? allTitles.filter { $0 != activeBookTitle }
                : allTitles
            guard let newTitle = candidates.randomElement() else { return }

            storage.currentBookTitle = newTitle

            // Clear shown IDs only for the new book's clippings; preserve other books
            let newBookIDs = Set(clippings.filter { $0.bookTitle == newTitle }.map(\.id))
            shownIDs.subtract(newBookIDs)
            storage.shownClippingIDs = shownIDs

            let newBookClippings = clippings.filter { $0.bookTitle == newTitle }
            guard let selected = newBookClippings.randomElement() else { return }
            currentClipping = selected
            shownIDs.insert(selected.id)
            storage.shownClippingIDs = shownIDs
        }
    }

    /// Selects a clipping from user-pinned books only, cycling without repeat within that pool.
    private func selectFromPinnedBooks() {
        let pinnedTitles = pinnedBookTitles
        guard !pinnedTitles.isEmpty else {
            errorMessage = "Sabitlenmiş kitap yok. Lütfen Ayarlar'dan kitap seçin."
            selectAllRandom()
            return
        }

        let pinnedClippings = clippings.filter { pinnedTitles.contains($0.bookTitle) }
        guard !pinnedClippings.isEmpty else {
            errorMessage = "Seçili kitaplarda alıntı bulunamadı."
            selectAllRandom()
            return
        }

        var shownIDs = storage.shownClippingIDs
        let unshown = pinnedClippings.filter { !shownIDs.contains($0.id) }

        if let next = unshown.randomElement() {
            currentClipping = next
            shownIDs.insert(next.id)
        } else {
            // All pinned clippings shown — reset only within the pinned pool
            let pinnedIDs = Set(pinnedClippings.map(\.id))
            shownIDs.subtract(pinnedIDs)
            storage.shownClippingIDs = shownIDs
            guard let selected = pinnedClippings.randomElement() else { return }
            currentClipping = selected
            shownIDs.insert(selected.id)
        }
        storage.shownClippingIDs = shownIDs
    }

    /// Generates a low-resolution wallpaper preview for the app UI.
    func generatePreview() {
        guard let clipping = currentClipping else { return }
        guard let screen = NSScreen.main else {
            errorMessage = KindleWallError.screenNotAvailable.errorDescription
            return
        }

        // Cancel any in-flight preview render before starting a new one
        previewTask?.cancel()
        previewGeneration &+= 1
        let generation = previewGeneration

        // Use 1x screen size for preview (not Retina) — much faster and readable in the app
        let previewSize = screen.frame.size
        let displayClipping = clippingWithOverride(clipping)

        previewTask = Task.detached { [generator, selectedStyle, typography] in
            let image = generator.generateWallpaper(
                clipping: displayClipping,
                style: selectedStyle,
                screenSize: previewSize,
                typography: typography
            )
            await MainActor.run { [weak self] in
                guard let self, self.previewGeneration == generation else { return }
                self.currentWallpaperImage = image
            }
        }
    }

    /// Selects a clipping, updates the preview, and immediately applies the wallpaper.
    func selectAndApply(_ clipping: Clipping) {
        currentClipping = clipping
        generatePreview()
        applyWallpaper()
    }

    /// Applies the wallpaper to the desktop at full Retina resolution.
    func applyWallpaper() {
        guard let clipping = currentClipping else { return }
        guard !isApplying else { return }
        guard let screen = NSScreen.main else {
            errorMessage = KindleWallError.screenNotAvailable.errorDescription
            return
        }

        isApplying = true
        errorMessage = nil

        let fullSize = screen.frame.size * screen.backingScaleFactor
        let displayClipping = clippingWithOverride(clipping)

        // Render at full resolution for actual wallpaper
        guard let fullImage = generator.generateWallpaper(
            clipping: displayClipping,
            style: selectedStyle,
            screenSize: fullSize,
            typography: typography
        ) else {
            isApplying = false
            errorMessage = KindleWallError.wallpaperGenerationFailed(reason: "Render başarısız").errorDescription
            return
        }

        do {
            try wallpaperManager.setWallpaper(image: fullImage)
            if storage.showNotifications {
                notificationService.sendWallpaperChangedNotification(clipping: displayClipping)
            }
            isApplying = false
            applySuccess = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                applySuccess = false
            }
        } catch {
            isApplying = false
            errorMessage = (error as? KindleWallError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Returns a copy of the clipping with title/author replaced by the user's saved override, if any.
    private func clippingWithOverride(_ clipping: Clipping) -> Clipping {
        guard let ov = storage.bookMetadataOverrides[clipping.bookTitle] else { return clipping }
        return Clipping(
            id: clipping.id,
            bookTitle: ov.displayTitle,
            author: ov.displayAuthor,
            text: clipping.text,
            page: clipping.page,
            location: clipping.location,
            dateAdded: clipping.dateAdded,
            type: clipping.type
        )
    }

    /// Updates the wallpaper style and regenerates the preview.
    func updateStyle(_ style: WallpaperStyle) {
        selectedStyle = style
        storage.selectedStyle = style
        generatePreview()
    }

    /// Updates typography settings, persists them, and regenerates the preview.
    /// Debounced 250ms so rapid slider changes don't flood the render pipeline.
    func updateTypography(_ settings: TypographySettings) {
        typography = settings
        storage.typography = settings
        typographyUpdateTask?.cancel()
        typographyUpdateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.generatePreview()
        }
    }

    /// Updates the rotation mode and clears bookByBook state so the next selection starts fresh.
    func updateRotationMode(_ mode: RotationMode) {
        storage.rotationMode = mode
        storage.currentBookTitle = nil
    }

    /// Updates the in-memory pinned book titles and persists them.
    /// Called via callback whenever the user toggles a book in SettingsView.
    func updatePinnedBooks(_ titles: Set<String>) {
        pinnedBookTitles = titles
        storage.pinnedBookTitles = Array(titles).sorted()
    }

    /// Sorted list of unique books (title + first found author) from loaded clippings.
    var availableBooks: [(title: String, author: String?)] {
        var seen: [String: String?] = [:]
        for clipping in clippings where seen[clipping.bookTitle] == nil {
            seen[clipping.bookTitle] = clipping.author
        }
        return seen.map { (title: $0.key, author: $0.value) }
            .sorted { $0.title < $1.title }
    }

    /// Re-reads typography from storage and regenerates the preview.
    /// Called when SettingsView changes decoration style or gradient colors.
    func reloadTypography() {
        typography = storage.typography
        generatePreview()
    }

    /// Updates the scheduler interval (and optional custom date) from SettingsView.
    func updateScheduleInterval(_ interval: ScheduleInterval, customDate: Date?) {
        scheduler.interval = interval
        storage.scheduleInterval = interval
        if let date = customDate {
            scheduler.customDate = date
            storage.customScheduleDate = date
        }
    }

    // MARK: - Manual Clipping CRUD

    func addManualClipping(bookTitle: String, author: String?, text: String, page: String?) {
        let id = Clipping.deterministicID(bookTitle: bookTitle, text: text)
        guard !clippings.contains(where: { $0.id == id }) else { return }
        let clipping = Clipping(
            id: id,
            bookTitle: bookTitle,
            author: author.flatMap { $0.isEmpty ? nil : $0 },
            text: text,
            page: page.flatMap { $0.isEmpty ? nil : $0 },
            dateAdded: Date(),
            isManualEntry: true
        )
        var manual = storage.manualClippings
        manual.append(clipping)
        storage.manualClippings = manual
        clippings.append(clipping)
        storage.persistedClippingIDs.insert(clipping.id)
    }

    func updateManualClipping(_ updated: Clipping) {
        var manual = storage.manualClippings
        guard let idx = manual.firstIndex(where: { $0.id == updated.id }) else { return }
        manual[idx] = updated
        storage.manualClippings = manual
        if let listIdx = clippings.firstIndex(where: { $0.id == updated.id }) {
            clippings[listIdx] = updated
        }
        if currentClipping?.id == updated.id {
            currentClipping = updated
            generatePreview()
        }
    }

    func deleteManualClipping(_ clipping: Clipping) {
        storage.manualClippings.removeAll { $0.id == clipping.id }
        clippings.removeAll { $0.id == clipping.id }
        storage.persistedClippingIDs.remove(clipping.id)
        storage.favoriteClippingIDs.remove(clipping.id)
        storage.shownClippingIDs.remove(clipping.id)
        if currentClipping?.id == clipping.id {
            currentClipping = clippings.first
            generatePreview()
        }
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

    /// Returns true if there is a previous wallpaper URL available to restore.
    var canRestorePreviousWallpaper: Bool {
        wallpaperManager.previousWallpaperURL != nil
    }

    /// Restores the desktop wallpaper to the one before KindleWall last changed it.
    func restorePreviousWallpaper() {
        do {
            try wallpaperManager.restorePreviousWallpaper()
        } catch {
            errorMessage = (error as? KindleWallError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Starts the automatic wallpaper change scheduler.
    func startScheduler() {
        isSchedulerPaused = false
        scheduler.start { [weak self] in
            self?.selectRandomClipping()
            self?.applyWallpaper()
        }
    }

    /// Stops the scheduler.
    func stopScheduler() {
        scheduler.stop()
    }

    /// Pauses or resumes the automatic wallpaper scheduler.
    func toggleSchedulerPause() {
        scheduler.togglePause()
        isSchedulerPaused = !scheduler.isActive
    }

    /// The next scheduled wallpaper change date.
    var nextWallpaperDate: Date? { scheduler.nextChangeDate }
}

// MARK: - CGSize Helper

private extension CGSize {
    static func * (lhs: CGSize, rhs: CGFloat) -> CGSize {
        CGSize(width: lhs.width * rhs, height: lhs.height * rhs)
    }
}
