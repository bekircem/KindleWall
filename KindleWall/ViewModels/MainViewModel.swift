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

    /// Set when a style change overwrote the user's typography; drives the undo banner.
    /// Cleared on undo, on the next style change that changes nothing, or after a few seconds.
    private(set) var styleTypographyUndo: StyleTypographyUndo?

    /// What a style change replaced, so it can be put back.
    struct StyleTypographyUndo: Equatable {
        let styleName: String
        let previous: TypographySettings
    }

    // MARK: - Dependencies

    private let parser: ClippingsParserProtocol
    private let generator: WallpaperGeneratorProtocol
    private let wallpaperManager: WallpaperManagerProtocol
    private var scheduler: SchedulerServiceProtocol
    private var storage: StorageServiceProtocol
    private let notificationService: NotificationServiceProtocol
    private let sunCalculator: SunCalculatorProtocol
    private let composer: DynamicWallpaperComposerProtocol
    private let heicEncoder: HEICWallpaperEncoderProtocol
    let importState: ImportState

    // MARK: - Preview task management

    private var previewTask: Task<Void, Never>?
    private var previewGeneration: Int = 0
    private var typographyUpdateTask: Task<Void, Never>?
    private var styleUndoDismissTask: Task<Void, Never>?

    // MARK: - Apply task management

    private var applyTask: Task<Void, Never>?
    private var applyGeneration: Int = 0

    // MARK: - Import task management

    private var importTask: Task<Void, Never>?

    // MARK: - Notification observers

    private var captureTextObserver: NSObjectProtocol?

    // MARK: - Init

    init(
        parser: ClippingsParserProtocol = ClippingsParser(),
        generator: WallpaperGeneratorProtocol = WallpaperGenerator(),
        wallpaperManager: WallpaperManagerProtocol? = nil,
        scheduler: SchedulerServiceProtocol = SchedulerService(),
        storage: StorageServiceProtocol = StorageService(),
        importState: ImportState = ImportState(),
        notificationService: NotificationServiceProtocol = NotificationService(),
        sunCalculator: SunCalculatorProtocol = SunCalculator(),
        composer: DynamicWallpaperComposerProtocol = DynamicWallpaperComposer(),
        heicEncoder: HEICWallpaperEncoderProtocol = HEICWallpaperEncoder()
    ) {
        self.parser = parser
        self.generator = generator
        self.storage = storage
        self.scheduler = scheduler
        self.notificationService = notificationService
        self.sunCalculator = sunCalculator
        self.composer = composer
        self.heicEncoder = heicEncoder
        self.selectedStyle = storage.selectedStyle
        self.typography = storage.typography
        self.pinnedBookTitles = Set(storage.pinnedBookTitles)
        self.importState = importState

        if let wm = wallpaperManager {
            self.wallpaperManager = wm
        } else {
            self.wallpaperManager = WallpaperManager(storageService: storage)
        }

        AppEnvironment.shared.mainViewModel = self

        // Restore stored schedule interval so the scheduler fires at the user's configured cadence
        self.scheduler.interval = storage.scheduleInterval
        if let customDate = storage.customScheduleDate {
            self.scheduler.customDate = customDate
        }

        // Listen for text captured via Services menu or global hotkey
        captureTextObserver = NotificationCenter.default.addObserver(
            forName: Constants.Notifications.captureText,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.pendingCaptureText = notification.userInfo?["text"] as? String
        }
    }

    deinit {
        if let observer = captureTextObserver {
            NotificationCenter.default.removeObserver(observer)
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
        } else if let resolved = storage.resolveClippingsFileURL(),
                  FileManager.default.fileExists(atPath: resolved.path) {
            // Prefer the original when it is reachable — it may hold newer highlights.
            fileURL = resolved
        } else if let cached = storage.localClippingsFileURL() {
            // Kindle unplugged (or the bookmark went stale). Fall back to our own copy instead
            // of leaving the app with zero clippings, which is what used to happen: nothing to
            // display, nothing to render, and an error where the quote should be.
            fileURL = cached
        } else {
            errorMessage = "Lütfen My Clippings.txt dosyasını seçin."
            return
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

                // Only cache after a successful parse, and only while the security scope is
                // still held — so we never persist a file we could not read.
                self.storage.cacheClippingsFile(from: fileURL)

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

        // Now that there is something to render, retry the blank-desktop repair the launch
        // attempt could not perform.
        rerenderIfDesktopIsBlank()
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
        let pool = filteredClippings()
        guard !pool.isEmpty else {
            errorMessage = "Filtreye uyan alıntı yok. Uzun alıntı eşiğini yükseltin."
            return
        }
        errorMessage = nil
        switch storage.rotationMode {
        case .allRandom:   selectAllRandom(pool: pool)
        case .bookByBook:  selectBookByBook(pool: pool)
        case .pinnedBooks: selectFromPinnedBooks(pool: pool)
        case .favorites:   selectFromFavorites(pool: pool)
        }
        generatePreview()
    }

    /// Returns clippings that pass the optional long-quote skip filter.
    private func filteredClippings() -> [Clipping] {
        let settings = storage.longQuote
        guard settings.skipEnabled else { return clippings }
        let threshold = settings.skipThreshold
        return clippings.filter { settings.skipUnit.measure($0.text) <= threshold }
    }

    /// Selects a random clipping from the pool, cycling without repeat.
    private func selectAllRandom(pool: [Clipping]) {
        var shownIDs = storage.shownClippingIDs
        let unshown = pool.filter { !shownIDs.contains($0.id) }
        if let next = unshown.randomElement() {
            currentClipping = next
            shownIDs.insert(next.id)
        } else {
            // Reset shown IDs only within the current pool to preserve filtered-out state.
            let poolIDs = Set(pool.map(\.id))
            shownIDs.subtract(poolIDs)
            storage.shownClippingIDs = shownIDs
            guard let selected = pool.randomElement() else { return }
            currentClipping = selected
            shownIDs.insert(selected.id)
        }
        storage.shownClippingIDs = shownIDs
    }

    /// Selects a clipping book-by-book, exhausting all quotes in a book before moving on.
    private func selectBookByBook(pool: [Clipping]) {
        var shownIDs = storage.shownClippingIDs

        // Determine active book from pool; pick randomly if none stored or book no longer present.
        let activeBookTitle: String
        if let stored = storage.currentBookTitle,
           pool.contains(where: { $0.bookTitle == stored }) {
            activeBookTitle = stored
        } else {
            let allTitles = Array(Set(pool.map(\.bookTitle)))
            guard let picked = allTitles.randomElement() else { return }
            activeBookTitle = picked
            storage.currentBookTitle = picked
        }

        let bookClippings = pool.filter { $0.bookTitle == activeBookTitle }
        let unshown = bookClippings.filter { !shownIDs.contains($0.id) }

        if let selected = unshown.randomElement() {
            // Still have unshown quotes in the current book
            currentClipping = selected
            shownIDs.insert(selected.id)
            storage.shownClippingIDs = shownIDs
        } else {
            // Book exhausted — pick a new one from the pool
            let allTitles = Array(Set(pool.map(\.bookTitle)))
            let candidates = allTitles.count > 1
                ? allTitles.filter { $0 != activeBookTitle }
                : allTitles
            guard let newTitle = candidates.randomElement() else { return }

            storage.currentBookTitle = newTitle

            // Clear shown IDs only for the new book's clippings; preserve other books
            let newBookIDs = Set(pool.filter { $0.bookTitle == newTitle }.map(\.id))
            shownIDs.subtract(newBookIDs)
            storage.shownClippingIDs = shownIDs

            let newBookClippings = pool.filter { $0.bookTitle == newTitle }
            guard let selected = newBookClippings.randomElement() else { return }
            currentClipping = selected
            shownIDs.insert(selected.id)
            storage.shownClippingIDs = shownIDs
        }
    }

    /// Selects a clipping from favorited quotes only, cycling without repeat within that pool.
    private func selectFromFavorites(pool: [Clipping]) {
        let favoriteIDs = storage.favoriteClippingIDs
        guard !favoriteIDs.isEmpty else {
            errorMessage = "Favori alıntı yok. Kütüphaneden kalp ekleyin."
            selectAllRandom(pool: pool)
            return
        }

        let favoriteClippings = pool.filter { favoriteIDs.contains($0.id) }
        guard !favoriteClippings.isEmpty else {
            errorMessage = "Favori alıntılar bu filtreyle uyumsuz."
            selectAllRandom(pool: pool)
            return
        }

        var shownIDs = storage.shownClippingIDs
        let unshown = favoriteClippings.filter { !shownIDs.contains($0.id) }

        if let next = unshown.randomElement() {
            currentClipping = next
            shownIDs.insert(next.id)
        } else {
            // All favorites shown — reset only within the favorites pool
            let favPoolIDs = Set(favoriteClippings.map(\.id))
            shownIDs.subtract(favPoolIDs)
            storage.shownClippingIDs = shownIDs
            guard let selected = favoriteClippings.randomElement() else { return }
            currentClipping = selected
            shownIDs.insert(selected.id)
        }
        storage.shownClippingIDs = shownIDs
    }

    /// Selects a clipping from user-pinned books only, cycling without repeat within that pool.
    private func selectFromPinnedBooks(pool: [Clipping]) {
        let pinnedTitles = pinnedBookTitles
        guard !pinnedTitles.isEmpty else {
            errorMessage = "Sabitlenmiş kitap yok. Lütfen Ayarlar'dan kitap seçin."
            selectAllRandom(pool: pool)
            return
        }

        let pinnedClippings = pool.filter { pinnedTitles.contains($0.bookTitle) }
        guard !pinnedClippings.isEmpty else {
            errorMessage = "Seçili kitaplarda alıntı bulunamadı."
            selectAllRandom(pool: pool)
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

        let longQuote = storage.longQuote
        previewTask = Task.detached { [generator, selectedStyle, typography] in
            let image = generator.generateWallpaper(
                clipping: displayClipping,
                style: selectedStyle,
                screenSize: previewSize,
                typography: typography,
                longQuote: longQuote
            )
            await MainActor.run { [weak self] in
                guard let self, self.previewGeneration == generation else { return }
                self.currentWallpaperImage = image
            }
        }
    }

    /// Selects a clipping, updates the preview, and immediately applies the wallpaper.
    ///
    /// Preview and apply render independently on purpose: after the exact-pixel render change
    /// the preview is ~4× cheaper and already detached, so deriving the applied wallpaper from
    /// the preview image would couple two pipelines (different target sizes, lifetimes, and
    /// cancellation) for no real saving. Kept separate deliberately.
    func selectAndApply(_ clipping: Clipping) {
        currentClipping = clipping
        generatePreview()
        applyWallpaper()
    }

    /// Applies the wallpaper to the desktop.
    ///
    /// Full-resolution render + PNG encode + disk write now run on a detached task (mirroring
    /// `generatePreview`) so the main thread never blocks — the window stays responsive while a
    /// wallpaper is applied, including on every scheduler tick. Only the actual desktop swap
    /// (`NSWorkspace`, which must stay on the main actor) and the success/error UI run on main.
    func applyWallpaper() {
        guard let clipping = currentClipping else { return }
        guard let screen = NSScreen.main else {
            errorMessage = KindleWallError.screenNotAvailable.errorDescription
            return
        }

        // Latest-wins. The old synchronous body could not re-enter, so `guard !isApplying`
        // sufficed. Now that the render runs off-main we instead supersede any in-flight apply
        // by generation: a newer request (or scheduler tick) must not be dropped, and a slow
        // earlier render must never overwrite a newer wallpaper.
        applyTask?.cancel()
        applyGeneration &+= 1
        let generation = applyGeneration

        isApplying = true
        errorMessage = nil

        // Snapshot every input on the main actor before crossing to the background task.
        let fullSize = screen.frame.size * screen.backingScaleFactor
        let displayClipping = clippingWithOverride(clipping)
        let style = selectedStyle
        let typographySnapshot = typography
        let longQuote = storage.longQuote
        let notify = storage.showNotifications

        let dynamicEnabled = storage.dynamicWallpaperEnabled

        applyTask = Task.detached { [generator, wallpaperManager, sunCalculator, composer, heicEncoder] in
            // Render + encode + write off-main. The NSImage never crosses actors — only the
            // resulting file URL does.
            let url: URL
            var fellBackToStatic = false
            do {
                let dynamicURL = dynamicEnabled ? Self.renderDynamicWallpaper(
                    clipping: displayClipping, style: style, screenSize: fullSize,
                    typography: typographySnapshot, longQuote: longQuote,
                    generator: generator, sunCalculator: sunCalculator,
                    composer: composer, encoder: heicEncoder, manager: wallpaperManager
                ) : nil

                // A superseded apply must stop here. Falling through to the static render would
                // undo the cancellation we just honoured and do the expensive work anyway.
                if Task.isCancelled { return }

                if let dynamicURL {
                    url = dynamicURL
                } else {
                    // Either dynamic is off, or a step of the dynamic pipeline failed. Falling
                    // back keeps the wallpaper changing rather than leaving the desktop stale;
                    // the user is told once, below.
                    fellBackToStatic = dynamicEnabled
                    guard let fullImage = generator.generateWallpaper(
                        clipping: displayClipping,
                        style: style,
                        screenSize: fullSize,
                        typography: typographySnapshot,
                        longQuote: longQuote
                    ) else {
                        throw KindleWallError.wallpaperGenerationFailed(reason: "Render başarısız")
                    }
                    url = try wallpaperManager.writeWallpaperPNG(image: fullImage)
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.applyGeneration == generation else { return }
                    self.isApplying = false
                    self.errorMessage = (error as? KindleWallError)?.errorDescription ?? error.localizedDescription
                }
                return
            }

            await MainActor.run { [weak self] in
                guard let self, self.applyGeneration == generation else { return }
                do {
                    // NSWorkspace swap + captureCurrentWallpaper stay on the main actor.
                    try self.wallpaperManager.setWallpaper(fileURL: url)
                    if notify {
                        self.notificationService.sendWallpaperChangedNotification(clipping: displayClipping)
                    }
                    self.applySuccess = true
                    self.isApplying = false
                    if fellBackToStatic {
                        self.errorMessage = "Dinamik duvar kağıdı üretilemedi, statik uygulandı."
                    }
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(1.5))
                        self?.applySuccess = false
                    }
                } catch {
                    self.errorMessage = (error as? KindleWallError)?.errorDescription ?? error.localizedDescription
                    self.isApplying = false
                }
            }
        }
    }

    /// Renders the six-frame dynamic wallpaper and writes it as a single HEIC.
    ///
    /// Runs entirely off the main actor. Returns nil rather than throwing on any failure, so
    /// the caller can fall back to the static path — a wallpaper that changed is always better
    /// than an error dialog and an unchanged desktop.
    private static func renderDynamicWallpaper(
        clipping: Clipping, style: WallpaperStyle, screenSize: CGSize,
        typography: TypographySettings, longQuote: LongQuoteSettings,
        generator: WallpaperGeneratorProtocol, sunCalculator: SunCalculatorProtocol,
        composer: DynamicWallpaperComposerProtocol, encoder: HEICWallpaperEncoderProtocol,
        manager: WallpaperManagerProtocol
    ) -> URL? {
        // Cancellation is checked between every stage. Without this, superseding an apply only
        // stopped the *result* from being used — the six-frame render kept running to
        // completion, so clicking through styles piled up several ~600 ms, several-hundred-MB
        // renders at once and the UI stuttered.
        if Task.isCancelled { return nil }

        // Anchor the frames to today's real sunrise/sunset, so the colours track the season.
        let coordinate = GeoCoordinate.fromSystemTimeZone()
        let phaseTimes = sunCalculator.phases(for: Date(), at: coordinate)
        guard !phaseTimes.isEmpty else { return nil }

        // The expensive typesetting happens here, once, and is reused by every frame.
        guard let background = generator.renderBackgroundLayer(
                  clipping: clipping, style: style, screenSize: screenSize, typography: typography),
              !Task.isCancelled,
              let text = generator.renderTextLayer(
                  clipping: clipping, style: style, screenSize: screenSize,
                  typography: typography, longQuote: longQuote, invertedInk: false),
              !Task.isCancelled else { return nil }

        // A second text layer is only worth drawing when some phase actually darkens the
        // background past readability — for the dark styles, none ever does.
        let phases = phaseTimes.map(\.phase)
        let needsInvertedInk = phases.contains {
            SolarPalette.transforms(for: $0, style: style).usesInvertedInk
        }
        let invertedText = needsInvertedInk
            ? generator.renderTextLayer(clipping: clipping, style: style, screenSize: screenSize,
                                        typography: typography, longQuote: longQuote, invertedInk: true)
            : nil
        if Task.isCancelled { return nil }

        let frames = composer.compose(background: background, text: text,
                                      invertedText: invertedText,
                                      style: style, phases: phases)
        guard frames.count == phaseTimes.count, !Task.isCancelled else { return nil }

        do {
            let url = manager.wallpaperFileURL(extension: "heic")
            try manager.prepareWallpaperDirectory()
            try encoder.write(frames: frames, phaseTimes: phaseTimes, to: url)
            return url
        } catch {
            return nil
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
        applyStyleTypography(for: style)
        generatePreview()
    }

    /// Writes the style's own font and decoration into the typography settings.
    ///
    /// Styles only feel distinct if choosing one visibly changes the type, so a style always
    /// applies its character. The cost is that it overwrites whatever the user picked on the
    /// Tipografi page — which is why the previous values are snapshotted and surfaced as an
    /// undo (`styleTypographyUndo`) rather than silently discarded.
    private func applyStyleTypography(for style: WallpaperStyle) {
        var updated = typography
        updated.fontFamily = style.defaultFontFamily
        updated.decorativeStyle = style.defaultDecoration
        guard updated != typography else {
            styleTypographyUndo = nil
            return
        }

        let previous = typography
        typography = updated
        storage.typography = updated
        styleTypographyUndo = StyleTypographyUndo(styleName: style.displayName, previous: previous)

        // Auto-dismiss so the banner never becomes permanent furniture.
        styleUndoDismissTask?.cancel()
        styleUndoDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.styleTypographyUndo = nil
        }
    }

    /// Restores the typography a style change overwrote.
    func undoStyleTypography() {
        guard let undo = styleTypographyUndo else { return }
        styleUndoDismissTask?.cancel()
        styleTypographyUndo = nil
        typography = undo.previous
        storage.typography = undo.previous
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
    /// Debounced 200ms (reusing `typographyUpdateTask`) so continuous gradient color-picker
    /// drags don't flood the render pipeline now that the preview is visible on these pages.
    func reloadTypography() {
        typography = storage.typography
        typographyUpdateTask?.cancel()
        typographyUpdateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.generatePreview()
        }
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

    /// Deletes wallpapers left behind by previous runs. Called once at launch.
    ///
    /// Repair runs first: if a previous version's pruning deleted the file the desktop was
    /// pointing at, the desktop is blank and putting a wallpaper back matters more than
    /// reclaiming disk.
    func sweepOrphanedWallpapers() {
        // Restoring a surviving file needs no clippings, so it can run immediately.
        wallpaperManager.repairDesktopIfWallpaperMissing()
        wallpaperManager.sweepOrphanedWallpapers()
        rerenderIfDesktopIsBlank()
    }

    /// Renders a fresh wallpaper when the desktop points at one of our files that is gone and
    /// there is nothing left to restore from.
    ///
    /// Called both at launch and after an import finishes: at launch the clipping list is still
    /// empty (the import is async), so a launch-only attempt would silently do nothing and
    /// leave the user with a blank desktop.
    private func rerenderIfDesktopIsBlank() {
        guard wallpaperManager.isDesktopWallpaperMissing() else { return }
        if currentClipping == nil && !clippings.isEmpty { selectRandomClipping() }
        guard currentClipping != nil else { return }
        applyWallpaper()
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
