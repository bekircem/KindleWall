import SwiftUI
import Observation

/// Manages the state for the main application view and coordinates services.
///
/// Main-actor isolated: every stored property here is read by SwiftUI during layout, so the
/// only safe home for them is the actor SwiftUI already runs on. The two expensive paths that
/// must not block the UI — preview render and apply render — are `Task.detached` and capture
/// the services they need rather than `self`, so isolating the class does not put rendering
/// back on the main thread.
@Observable
@MainActor
final class MainViewModel {
    // MARK: - Published State

    var currentClipping: Clipping?
    var currentWallpaperImage: NSImage?
    var selectedStyle: WallpaperStyle
    var typography: TypographySettings = .default
    /// Where the desktop stands relative to the design on screen. The single thing every
    /// surface reads to answer "did my change actually take?".
    private(set) var applyStatus: ApplyStatus = .idle

    var isApplying: Bool { applyStatus.isApplying }
    var applySuccess: Bool { applyStatus.isApplied }

    /// Whether editing the design pushes it to the desktop on its own.
    ///
    /// Stored rather than forwarded to `storage`, because a computed passthrough to a
    /// non-observable service would not tell SwiftUI the toggle moved.
    var autoApplyDesignChanges: Bool {
        didSet {
            guard autoApplyDesignChanges != oldValue else { return }
            storage.autoApplyDesignChanges = autoApplyDesignChanges
            if autoApplyDesignChanges {
                // Turning it on should settle the difference the user is already looking at.
                if applyStatus.needsManualApply { applyDesignNow() }
            } else {
                autoApplyTask?.cancel()
                autoApplyTask = nil
            }
        }
    }

    var errorMessage: String?
    var clippings: [Clipping] = []
    var pinnedBookTitles: Set<String> = []
    private(set) var isSchedulerPaused: Bool = false
    var pendingCaptureText: String? = nil

    /// When the scheduler will next change the wallpaper.
    ///
    /// Stored rather than forwarded to `scheduler.nextChangeDate`: `SchedulerService` is not
    /// `@Observable`, so a computed passthrough never told SwiftUI anything had changed and
    /// every view showing the countdown sat frozen until some unrelated redraw.
    private(set) var nextWallpaperDate: Date?

    /// Whether a pre-KindleWall wallpaper is on file to restore. Stored for the same reason —
    /// `WallpaperManager` is not observable either, so the "Geri Yükle" button used to keep
    /// whatever enabled state it happened to be built with.
    private(set) var canRestorePreviousWallpaper: Bool = false

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
    private var previewDebounceTask: Task<Void, Never>?
    private var styleUndoDismissTask: Task<Void, Never>?

    // MARK: - Apply task management

    private var applyTask: Task<Void, Never>?
    private var applyGeneration: Int = 0

    /// Waits out the settle delay, then applies a design edit on its own.
    private var autoApplyTask: Task<Void, Never>?
    /// Returns `applyStatus` to `.idle` after a finished state has been on screen long enough.
    private var statusDwellTask: Task<Void, Never>?
    /// Defers the all-Spaces propagation until editing stops — see `Self.syncSettleDelay`.
    private var autoSyncSettleTask: Task<Void, Never>?

    // MARK: - Auto-apply tuning

    /// How long the design has to hold still before it applies itself.
    ///
    /// Chosen against the cadence of *deliberate* clicks, not slider drags: a drag emits every
    /// 8–16 ms, so almost any delay coalesces it, while comparing styles takes roughly
    /// 400–700 ms per click. Below that, every click during a browse would cost a full apply.
    /// At 900 ms — plus the 150 ms coalesce inside `applyWallpaper` and ~215 ms of render and
    /// write — the desktop follows about 1.3 s after the user stops, and the live preview has
    /// already reacted long before that.
    static let autoApplyDelay: TimeInterval = 0.9

    /// Extra quiet time before pushing the wallpaper to every Space.
    ///
    /// Propagating is far more expensive than applying — it rewrites macOS's wallpaper store
    /// and restarts `WallpaperAgent`, reloading the wallpaper on every Space. The generation
    /// coalescing in `WallpaperManager` only helps when syncs overlap, and at this cadence each
    /// finishes before the next begins, so browsing six styles would otherwise mean six
    /// full-system reloads.
    static let syncSettleDelay: TimeInterval = 3

    /// What a design change replaced, so the whole change-set can be put back.
    struct DesignSnapshot: Equatable {
        let style: WallpaperStyle
        let typography: TypographySettings
    }

    /// The design as it was before the current run of edits began.
    ///
    /// Captured when a burst *starts* and deliberately not overwritten while it is in flight:
    /// after clicking through six styles the user means "put it back how it was", not "back
    /// one click".
    private(set) var designUndo: DesignSnapshot?

    // MARK: - Import task management

    private var importTask: Task<Void, Never>?

    // MARK: - Notification observers

    /// Written once in `init`, read once in `deinit`, never touched in between.
    ///
    /// `nonisolated(unsafe)` because `deinit` is not actor-isolated and this is the one property
    /// it must reach. The exemption is sound rather than convenient: a deinit runs only after the
    /// last reference is gone, so by construction nothing else can be touching this token.
    /// Block-based observers are not auto-removed the way selector-based ones are, so the deinit
    /// has to stay.
    /// Written once in `init`, read once in `deinit`, never touched in between.
    ///
    /// `@ObservationIgnored` keeps the `@Observable` macro from turning it into a tracked
    /// computed property — `nonisolated` cannot be applied to one, and no view observes an
    /// observer token anyway. `nonisolated(unsafe)` is then sound rather than convenient:
    /// `deinit` is not actor-isolated and runs only after the last reference is gone, so by
    /// construction nothing else can be touching this token. The deinit has to stay because
    /// block-based observers are not auto-removed the way selector-based ones are.
    @ObservationIgnored
    private nonisolated(unsafe) var captureTextObserver: NSObjectProtocol?

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
        self.autoApplyDesignChanges = storage.autoApplyDesignChanges
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
        self.nextWallpaperDate = self.scheduler.nextChangeDate
        self.canRestorePreviousWallpaper = self.wallpaperManager.previousWallpaperURL != nil

        // Listen for text captured via Services menu or global hotkey
        captureTextObserver = NotificationCenter.default.addObserver(
            forName: Constants.Notifications.captureText,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let text = notification.userInfo?["text"] as? String
            // `queue: .main` guarantees this body runs on the main thread, but the closure is
            // typed `@Sendable` so the compiler cannot see that. Asserting the isolation we
            // already have is cheaper and safer than hopping to a Task, which would let two
            // captures arrive out of order.
            MainActor.assumeIsolated { self?.pendingCaptureText = text }
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

    /// Seeds the library with a few public-domain highlights, for someone setting the app up
    /// without their Kindle to hand. Stored as manual clippings so they survive a relaunch and
    /// can be deleted one by one from the library.
    func loadSampleClippings() {
        var manual = storage.manualClippings
        let existing = Set(manual.map(\.id))
        let fresh = SampleLibrary.clippings.filter { !existing.contains($0.id) }
        guard !fresh.isEmpty || !clippings.isEmpty else { return }

        manual.append(contentsOf: fresh)
        storage.manualClippings = manual
        clippings.append(contentsOf: fresh)
        storage.persistedClippingIDs.formUnion(fresh.map(\.id))

        if currentClipping == nil { selectRandomClipping() }
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

        // The preview is shown in a hero view a few hundred points wide, so rendering it at the
        // screen's full point size (1920×1280 here) was ~2.3× more pixels than anything on
        // screen could use — paid on every style click, every typography nudge and every quote
        // change, while the apply render was often running too.
        let previewSize = Self.previewSize(for: screen.frame.size)
        let displayClipping = clippingWithOverride(clipping)

        let longQuote = storage.longQuote
        previewTask = Task.detached(priority: .utility) { [generator, selectedStyle, typography] in
            let image = Perf.measure("preview.render") { generator.generateWallpaper(
                clipping: displayClipping,
                style: selectedStyle,
                screenSize: previewSize,
                typography: typography,
                longQuote: longQuote
            ) }
            await MainActor.run { [weak self] in
                guard let self, self.previewGeneration == generation else { return }
                self.currentWallpaperImage = image
            }
        }
    }

    /// Preview render size: the screen's aspect ratio capped to a width no on-screen preview
    /// can exceed. Rendering more pixels than the panel can show is pure cost.
    private static func previewSize(for screenSize: CGSize) -> CGSize {
        let maxWidth: CGFloat = 1280
        guard screenSize.width > maxWidth, screenSize.width > 0 else { return screenSize }
        let scale = maxWidth / screenSize.width
        return CGSize(width: maxWidth, height: (screenSize.height * scale).rounded())
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

    // MARK: - Apply status

    /// The one place `applyStatus` is ever written.
    ///
    /// Invariant: only code already inside an `applyGeneration == generation` guard may call
    /// this, plus the synchronous entry in `applyWallpaper`, which is the newest generation by
    /// construction. That is what stops a slow, superseded apply from narrating over a newer
    /// one's state.
    private func transition(to status: ApplyStatus) {
        statusDwellTask?.cancel()
        applyStatus = status

        // Only settled states fade on their own. `.unapplied` waits for the user, and
        // `.pending` / `.applying` are ended by the apply itself.
        let dwell: Duration?
        switch status {
        case let .applied(_, reason, _):             dwell = reason.completionDwell
        case .failed:                                dwell = .seconds(6)
        case .idle, .pending, .applying, .unapplied: dwell = nil
        }
        guard let dwell else { return }

        statusDwellTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: dwell)
            guard !Task.isCancelled else { return }
            self?.applyStatus = .idle
            self?.designUndo = nil
        }
    }

    /// How urgently a design edit needs the preview refreshed.
    enum DesignChangeKind {
        /// One deliberate action — a style click, a decoration chip, an undo. Refresh now:
        /// putting a blanket debounce in front of these made the app feel laggy.
        case discrete
        /// A drag — slider or colour picker. Refresh once it stops moving.
        case continuous
    }

    /// The single point every design edit funnels through.
    ///
    /// Before this, four mutators each rolled their own debounce, and two of them shared one
    /// task handle — so a decoration chip could cancel an in-flight slider debounce and vice
    /// versa. Now one place refreshes the preview and one place decides whether the desktop
    /// should follow.
    private func designDidChange(_ kind: DesignChangeKind, undoing previous: DesignSnapshot? = nil) {
        previewDebounceTask?.cancel()
        switch kind {
        case .discrete:
            generatePreview()
        case .continuous:
            previewDebounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                self?.generatePreview()
            }
        }

        // Editing invalidates any deferred propagation: it would push a design the user has
        // already moved past out to every Space.
        autoSyncSettleTask?.cancel()

        guard storage.autoApplyDesignChanges else {
            autoApplyTask?.cancel()
            autoApplyTask = nil
            transition(to: .unapplied)
            return
        }

        // Only the first edit of a burst records where to go back to.
        if designUndo == nil, let previous { designUndo = previous }

        autoApplyTask?.cancel()
        transition(to: .pending(reason: .automatic,
                                deadline: Date().addingTimeInterval(Self.autoApplyDelay)))
        autoApplyTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.autoApplyDelay))
            guard !Task.isCancelled, let self else { return }
            self.autoApplyTask = nil
            self.applyWallpaper(reason: .automatic)
        }
    }

    /// A design-affecting setting that lives outside this view model changed — the dynamic
    /// wallpaper toggle is the one case. Refreshes the preview and lets the desktop follow,
    /// without touching the quote.
    func externalDesignSettingChanged() {
        designDidChange(.discrete)
    }

    /// A snapshot of the design as it stands right now.
    private var currentDesign: DesignSnapshot {
        DesignSnapshot(style: selectedStyle, typography: typography)
    }

    /// Puts the whole design back to where the current run of edits started.
    func undoDesign() {
        guard let snapshot = designUndo else { return }
        designUndo = nil
        styleUndoDismissTask?.cancel()
        styleTypographyUndo = nil

        selectedStyle = snapshot.style
        typography = snapshot.typography
        storage.selectedStyle = snapshot.style
        storage.typography = snapshot.typography

        generatePreview()
        applyWallpaper(reason: .manual)
    }

    /// Applies the design to the desktop now, regardless of the auto-apply preference.
    func applyDesignNow() {
        autoApplyTask?.cancel()
        autoApplyTask = nil
        applyWallpaper(reason: .manual)
    }

    /// Pushes the applied wallpaper out to every Space once the design has held still.
    private func scheduleAllSpacesSync() {
        autoSyncSettleTask?.cancel()
        autoSyncSettleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.syncSettleDelay))
            guard !Task.isCancelled, let self else { return }
            self.autoSyncSettleTask = nil
            self.wallpaperManager.syncCurrentWallpaperToAllSpaces()
        }
    }

    /// Applies the wallpaper to the desktop.
    ///
    /// Full-resolution render + PNG encode + disk write now run on a detached task (mirroring
    /// `generatePreview`) so the main thread never blocks — the window stays responsive while a
    /// wallpaper is applied, including on every scheduler tick. Only the actual desktop swap
    /// (`NSWorkspace`, which must stay on the main actor) and the success/error UI run on main.
    func applyWallpaper(reason: ApplyReason = .manual) {
        guard let clipping = currentClipping else { return }
        guard let screen = NSScreen.main else {
            errorMessage = KindleWallError.screenNotAvailable.errorDescription
            return
        }

        // Any apply already carries the user's in-progress design, because every design
        // mutator commits its state synchronously and defers only the render. So a pending
        // auto-apply has nothing left to contribute — including when a scheduler tick lands
        // in the middle of an edit.
        autoApplyTask?.cancel()
        autoApplyTask = nil

        // Latest-wins. The old synchronous body could not re-enter, so `guard !isApplying`
        // sufficed. Now that the render runs off-main we instead supersede any in-flight apply
        // by generation: a newer request (or scheduler tick) must not be dropped, and a slow
        // earlier render must never overwrite a newer wallpaper.
        applyTask?.cancel()
        applyGeneration &+= 1
        let generation = applyGeneration

        transition(to: .applying(reason: reason))
        errorMessage = nil

        // An automatic apply writes the active Space immediately but defers the all-Spaces
        // propagation, which is orders of magnitude more expensive. Manual and scheduled
        // applies keep the original behaviour exactly.
        let propagateNow = reason != .automatic

        // Snapshot every input on the main actor before crossing to the background task.
        let fullSize = screen.frame.size * screen.backingScaleFactor
        let displayClipping = clippingWithOverride(clipping)
        let style = selectedStyle
        let typographySnapshot = typography
        let longQuote = storage.longQuote
        let notify = storage.showNotifications

        let dynamicEnabled = storage.dynamicWallpaperEnabled
        // When the next rotation will rewrite this file, frames scheduled after it are encoded,
        // written and decoded by the system only to be thrown away unseen.
        let rewriteHorizon = scheduler.isActive ? scheduler.nextChangeDate : nil

        applyTask = Task.detached(priority: .utility) { [generator, wallpaperManager, sunCalculator, composer, heicEncoder] in
            // Coalesce bursts. A settings toggle, the "Şimdi Değiştir" button and a scheduler
            // tick can land within milliseconds of each other; each one used to start a full
            // multi-hundred-megabyte render before being superseded by the next.
            try? await Task.sleep(for: .milliseconds(150))
            if Task.isCancelled { return }

            let applyClock = Perf.Clock("apply.total")

            // Render + encode + write off-main. The NSImage never crosses actors — only the
            // resulting file URL does.
            let url: URL
            var fellBackToStatic = false
            do {
                let dynamicURL = dynamicEnabled ? Self.renderDynamicWallpaper(
                    clipping: displayClipping, style: style, screenSize: fullSize,
                    typography: typographySnapshot, longQuote: longQuote,
                    rewriteHorizon: rewriteHorizon,
                    generator: generator, sunCalculator: sunCalculator,
                    composer: composer, encoder: heicEncoder, manager: wallpaperManager
                ) : nil

                // A superseded apply must stop here. Falling through to the static render would
                // undo the cancellation we just honoured and do the expensive work anyway.
                if Task.isCancelled {
                    if let dynamicURL { wallpaperManager.discardPendingWallpaper(at: dynamicURL) }
                    return
                }

                if let dynamicURL {
                    url = dynamicURL
                } else {
                    // Either dynamic is off, or a step of the dynamic pipeline failed. Falling
                    // back keeps the wallpaper changing rather than leaving the desktop stale;
                    // the user is told once, below.
                    fellBackToStatic = dynamicEnabled
                    guard let fullImage = Perf.measure("static.render", "", { generator.generateWallpaper(
                        clipping: displayClipping,
                        style: style,
                        screenSize: fullSize,
                        typography: typographySnapshot,
                        longQuote: longQuote
                    ) }) else {
                        throw KindleWallError.wallpaperGenerationFailed(reason: "Render başarısız")
                    }
                    url = try wallpaperManager.writeWallpaperPNG(image: fullImage)
                }
                applyClock.finish(fellBackToStatic ? "statik (dinamik başarısız)"
                                                   : (dynamicEnabled ? "dinamik" : "statik"))
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.applyGeneration == generation else { return }
                    self.transition(to: .failed(
                        message: (error as? KindleWallError)?.errorDescription ?? error.localizedDescription
                    ))
                }
                return
            }

            // Frozen before the hop: `fellBackToStatic` is a mutable local, and capturing one in
            // a closure that runs on another actor is a race the compiler cannot rule out.
            let didFallBackToStatic = fellBackToStatic

            await MainActor.run { [weak self] in
                guard let self, self.applyGeneration == generation else {
                    // Lost the race after the file was already written. Nothing will ever point
                    // at it, so throw it away rather than leave it for a later prune to notice.
                    wallpaperManager.discardPendingWallpaper(at: url)
                    return
                }
                do {
                    // NSWorkspace swap + captureCurrentWallpaper stay on the main actor.
                    try self.wallpaperManager.setWallpaper(fileURL: url, propagateToAllSpaces: propagateNow)
                    if notify {
                        self.notificationService.sendWallpaperChangedNotification(clipping: displayClipping)
                    }
                    self.refreshDerivedServiceState()
                    // A fallback is reported as a caveat on success, not as an error: the
                    // wallpaper really did change, and pushing this into `errorMessage` used to
                    // put a red line next to the green "Uygulandı".
                    self.transition(to: .applied(
                        at: Date(),
                        reason: reason,
                        degraded: didFallBackToStatic ? "Dinamik duvar kağıdı üretilemedi, statik uygulandı." : nil
                    ))
                    if !propagateNow { self.scheduleAllSpacesSync() }
                } catch {
                    self.transition(to: .failed(
                        message: (error as? KindleWallError)?.errorDescription ?? error.localizedDescription
                    ))
                }
            }
        }
    }

    /// Renders the six-frame dynamic wallpaper and writes it as a single HEIC.
    ///
    /// Runs entirely off the main actor. Returns nil rather than throwing on any failure, so
    /// the caller can fall back to the static path — a wallpaper that changed is always better
    /// than an error dialog and an unchanged desktop.
    private nonisolated static func renderDynamicWallpaper(
        clipping: Clipping, style: WallpaperStyle, screenSize: CGSize,
        typography: TypographySettings, longQuote: LongQuoteSettings,
        rewriteHorizon: Date?,
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
        let allPhaseTimes = sunCalculator.phases(for: Date(), at: coordinate)
        guard !allPhaseTimes.isEmpty else { return nil }

        let phaseTimes = framesWorthWriting(allPhaseTimes, now: Date(), until: rewriteHorizon)
        guard !phaseTimes.isEmpty else { return nil }

        // The expensive typesetting happens here, once, and is reused by every frame.
        // Explicit "" for the detail argument: a trailing closure cannot be used inside a guard
        // condition, so the body has to be passed positionally.
        guard let background = Perf.measure("layer.background", "", {
                  generator.renderBackgroundLayer(clipping: clipping, style: style,
                                                  screenSize: screenSize, typography: typography) }),
              !Task.isCancelled,
              let text = Perf.measure("layer.text", "", {
                  generator.renderTextLayer(clipping: clipping, style: style, screenSize: screenSize,
                                            typography: typography, longQuote: longQuote,
                                            invertedInk: false) }),
              !Task.isCancelled else { return nil }

        // A second text layer is only worth drawing when some phase actually moves the
        // background past readability — for the dark styles, none ever does.
        let phases = phaseTimes.map(\.phase)
        let needsInvertedInk = phases.contains {
            SolarPalette.transforms(for: $0, style: style, typography: typography).usesInvertedInk
        }
        let invertedText = needsInvertedInk
            ? Perf.measure("layer.text.inverted", "", {
                  generator.renderTextLayer(clipping: clipping, style: style, screenSize: screenSize,
                                            typography: typography, longQuote: longQuote,
                                            invertedInk: true) })
            : nil
        if Task.isCancelled { return nil }

        guard let frameSource = composer.makeFrameSource(
            background: background, text: text, invertedText: invertedText,
            style: style, typography: typography
        ), !Task.isCancelled else { return nil }

        let url = manager.wallpaperFileURL(extension: "heic")
        do {
            try manager.prepareWallpaperDirectory()
            // Frames are produced one at a time inside the encoder, so peak memory is one frame
            // (39 MB at 3840×2560) rather than the whole set.
            try encoder.write(phaseTimes: phaseTimes, to: url) { index in
                Task.isCancelled ? nil : frameSource(phases[index])
            }
            guard !Task.isCancelled else {
                manager.discardPendingWallpaper(at: url)
                return nil
            }
            return url
        } catch {
            // A half-written HEIC is useless and, at several megabytes, worth removing now
            // rather than at whatever prune happens next.
            manager.discardPendingWallpaper(at: url)
            return nil
        }
    }

    /// The phases a dynamic file actually needs to carry.
    ///
    /// `apple_desktop:h24` shows the frame whose time is the latest one at or before now, so two
    /// kinds of frame are written and never seen: phases that are already behind us today, and
    /// phases that fall after the next quote rotation rewrites the whole file. At the default
    /// 30-minute rotation that was five of six frames, every single time — six full-resolution
    /// composites, six encodes, and a file the system re-decodes on every Space.
    ///
    /// One frame past the horizon is kept so a late rewrite still has somewhere to go, and the
    /// result never drops below two frames while the day still has two left — a single-frame
    /// HEIC is just a static wallpaper.
    /// `nonisolated`: a pure function of its arguments, called from the off-main render path.
    nonisolated static func framesWorthWriting(_ phaseTimes: [SolarPhaseTime],
                                               now: Date,
                                               until horizon: Date?) -> [SolarPhaseTime] {
        let sorted = phaseTimes.sorted { $0.date < $1.date }
        guard sorted.count > 1 else { return sorted }

        // Start at the phase that is current now. If the day has not reached its first phase
        // yet, macOS wraps to the last frame, so keeping the whole set is correct there.
        guard let currentIndex = sorted.lastIndex(where: { $0.date <= now }) else { return sorted }
        var remaining = Array(sorted[currentIndex...])

        if let horizon, horizon > now {
            let throughHorizon = remaining.prefix { $0.date <= horizon }.count
            remaining = Array(remaining.prefix(max(2, throughHorizon + 1)))
        }
        return remaining
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

    /// Updates the wallpaper style, refreshes the preview, and lets the desktop follow.
    func updateStyle(_ style: WallpaperStyle) {
        let previous = currentDesign
        selectedStyle = style
        storage.selectedStyle = style
        applyStyleTypography(for: style)
        designDidChange(.discrete, undoing: previous)
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
        // Through the funnel, not straight to `generatePreview` — otherwise undoing would fix
        // the preview and leave the desktop showing the typography the user just rejected.
        designDidChange(.discrete)
    }

    /// Commits typography, persists it, and routes the change through the shared funnel.
    private func commitTypography(_ settings: TypographySettings, kind: DesignChangeKind) {
        let previous = currentDesign
        typography = settings
        storage.typography = settings
        designDidChange(kind, undoing: previous)
    }

    /// Updates typography settings, persists them, and regenerates the preview.
    func updateTypography(_ settings: TypographySettings) {
        commitTypography(settings, kind: .continuous)
    }

    // MARK: - Design state (single owner)

    /// Gradient used when the user has not chosen custom colors.
    static let defaultGradientStart = Color(hex: "667EEA") ?? .purple
    static let defaultGradientEnd   = Color(hex: "764BA2") ?? .indigo

    /// Start / end of the custom background gradient.
    ///
    /// Every piece of design state — style, typography, decoration, gradient — is owned here and
    /// nowhere else. It used to be mirrored on `SettingsViewModel` too, which is how the
    /// Tipografi page could keep highlighting a decoration a style change had already replaced,
    /// and how toggling an unrelated General switch could write a stale style back over the one
    /// picked from the menu bar.
    var backgroundStartColor: Color {
        get { typography.backgroundStartColorHex.flatMap { Color(hex: $0) } ?? Self.defaultGradientStart }
        set {
            var updated = typography
            updated.backgroundStartColorHex = newValue.hexString
            commitTypography(updated, kind: .continuous)
        }
    }

    var backgroundEndColor: Color {
        get { typography.backgroundEndColorHex.flatMap { Color(hex: $0) } ?? Self.defaultGradientEnd }
        set {
            var updated = typography
            updated.backgroundEndColorHex = newValue.hexString
            commitTypography(updated, kind: .continuous)
        }
    }

    /// True when the user has overridden the style's own background.
    var hasCustomGradient: Bool {
        typography.backgroundStartColorHex != nil || typography.backgroundEndColorHex != nil
    }

    /// Clears the custom gradient so the selected style's own background returns.
    func resetBackgroundGradient() {
        var updated = typography
        updated.backgroundStartColorHex = nil
        updated.backgroundEndColorHex = nil
        commitTypography(updated, kind: .discrete)
    }

    /// Sets the decorative element drawn around the quote.
    func updateDecorationStyle(_ style: TypographySettings.DecorationStyle) {
        var updated = typography
        updated.decorativeStyle = style
        commitTypography(updated, kind: .discrete)
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

    /// Whether a source has ever been chosen — a bookmarked file, our cached copy of one, or
    /// hand-entered quotes. Distinguishes "you haven't picked a file" from "the file you picked
    /// had nothing in it", which are very different things to tell someone.
    var hasClippingsSource: Bool {
        storage.resolveClippingsFileURL() != nil
            || storage.localClippingsFileURL() != nil
            || !storage.manualClippings.isEmpty
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

    /// Re-reads typography that was written to storage out of band — the long-quote controls
    /// and CloudKit sync both do that — and routes it through the funnel.
    func reloadTypography() {
        let previous = currentDesign
        typography = storage.typography
        designDidChange(.continuous, undoing: previous)
    }

    /// Updates the scheduler interval (and optional custom date) from SettingsView.
    func updateScheduleInterval(_ interval: ScheduleInterval, customDate: Date?) {
        scheduler.interval = interval
        storage.scheduleInterval = interval
        if let date = customDate {
            scheduler.customDate = date
            storage.customScheduleDate = date
        }
        refreshDerivedServiceState()
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

    /// Restores the desktop wallpaper to the one before KindleWall last changed it.
    func restorePreviousWallpaper() {
        do {
            try wallpaperManager.restorePreviousWallpaper()
            // Reported like any other desktop change; it used to happen in total silence.
            transition(to: .applied(at: Date(), reason: .manual, degraded: nil))
        } catch {
            transition(to: .failed(
                message: (error as? KindleWallError)?.errorDescription ?? error.localizedDescription
            ))
        }
        refreshDerivedServiceState()
    }

    /// Pulls the two values that live behind non-observable services back into stored state.
    /// Call after anything that can move them: an apply, a restore, a scheduler change.
    private func refreshDerivedServiceState() {
        nextWallpaperDate = scheduler.nextChangeDate
        canRestorePreviousWallpaper = wallpaperManager.previousWallpaperURL != nil
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

    /// Renders a fresh wallpaper when there is no working KindleWall wallpaper to show.
    ///
    /// Two ways to get there, both seen in practice:
    /// * the desktop points at one of our files that has been deleted — macOS keeps drawing it
    ///   from cache, so it looks like a wallpaper that has frozen and stopped changing;
    /// * the launch sweep found the desktop set to something that is not ours (another app, a
    ///   leftover from a test run) and cleared our directory, leaving nothing to show at all.
    ///
    /// Without this the app produces nothing until the next rotation tick — up to a full
    /// interval of the user watching a wallpaper that has apparently stopped working.
    ///
    /// Called both at launch and after an import finishes: at launch the clipping list is still
    /// empty (the import is async), so a launch-only attempt would silently do nothing.
    private func rerenderIfDesktopIsBlank() {
        guard wallpaperManager.isDesktopWallpaperMissing()
                || !wallpaperManager.hasWallpaperOnDisk else { return }
        if currentClipping == nil && !clippings.isEmpty { selectRandomClipping() }
        guard currentClipping != nil else { return }
        applyWallpaper(reason: .repair)
    }

    /// Starts the automatic wallpaper change scheduler.
    func startScheduler() {
        isSchedulerPaused = false
        scheduler.start { [weak self] in
            self?.selectRandomClipping()
            self?.applyWallpaper(reason: .scheduler)
            self?.refreshDerivedServiceState()
        }
        refreshDerivedServiceState()
    }

    /// Stops the scheduler.
    func stopScheduler() {
        scheduler.stop()
        refreshDerivedServiceState()
    }

    /// Pauses or resumes the automatic wallpaper scheduler.
    func toggleSchedulerPause() {
        scheduler.togglePause()
        isSchedulerPaused = !scheduler.isActive
        refreshDerivedServiceState()
    }
}

// MARK: - CGSize Helper

private extension CGSize {
    static func * (lhs: CGSize, rhs: CGFloat) -> CGSize {
        CGSize(width: lhs.width * rhs, height: lhs.height * rhs)
    }
}
