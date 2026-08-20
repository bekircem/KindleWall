import AppKit
import Foundation
import OSLog

// MARK: - Protocol

/// Protocol for applying wallpaper images to the desktop.
///
/// `Sendable` because the render path hands the manager to a detached task: PNG/HEIC encoding
/// and the write both happen off the main actor, and only the `NSWorkspace` swap comes back.
protocol WallpaperManagerProtocol: Sendable {
    /// Renders the wallpaper image to a PNG on disk and returns its file URL, without
    /// applying it. Safe to call off the main actor — touches no instance state, only the
    /// filesystem — so the expensive PNG encode + write can run on a background task.
    /// - Parameter image: The wallpaper image to encode.
    /// - Returns: The URL of the written PNG.
    /// - Throws: KindleWallError if the image cannot be encoded or written.
    func writeWallpaperPNG(image: NSImage) throws -> URL

    /// Sets the desktop wallpaper from an NSImage on all screens.
    /// - Parameter image: The wallpaper image to apply.
    /// - Throws: KindleWallError if the wallpaper cannot be applied.
    func setWallpaper(image: NSImage) throws

    /// Sets the desktop wallpaper from a file URL on all screens.
    /// - Parameters:
    ///   - fileURL: The URL of the wallpaper image file.
    ///   - propagateToAllSpaces: Whether to also push the image to every Mission Control Space
    ///     right now (only meaningful when the user enabled "Immediate Sync"). Pass `false`
    ///     for rapid automatic applies and call `syncCurrentWallpaperToAllSpaces()` once the
    ///     edits settle — see that method for why.
    /// - Throws: KindleWallError if the wallpaper cannot be applied.
    func setWallpaper(fileURL: URL, propagateToAllSpaces: Bool) throws

    /// Pushes the wallpaper currently on the desktop out to every Space.
    ///
    /// Split out from `setWallpaper` because propagating is enormously more expensive than
    /// setting: it rewrites macOS's wallpaper store and restarts `WallpaperAgent`, which
    /// reloads the wallpaper on every Space. The existing generation coalescing only helps
    /// when syncs *overlap*, and at a ~1 s edit cadence each one finishes before the next
    /// starts — so browsing six styles would mean six full-system wallpaper reloads. Deferring
    /// until the design stops changing turns that back into one.
    func syncCurrentWallpaperToAllSpaces()

    /// Returns the URL of the current desktop wallpaper (before KindleWall changed it).
    var previousWallpaperURL: URL? { get }

    /// Restores the wallpaper to the one before KindleWall last changed it.
    /// - Throws: KindleWallError if restoring fails.
    func restorePreviousWallpaper() throws

    /// Deletes every file in the wallpapers directory except the given URLs.
    /// Call only *after* a new wallpaper has been applied successfully — pruning first
    /// would risk deleting the file the desktop is about to point at.
    /// - Parameter keep: URLs that must survive; anything else in the directory goes.
    func pruneWallpapers(keeping keep: [URL])

    /// Throws away a wallpaper file that was rendered but will never reach the desktop,
    /// and stops protecting it from pruning.
    ///
    /// A superseded apply has already written its file by the time it notices it lost the
    /// race. Without this the file sits there until some later prune happens to sweep it —
    /// which, once design changes apply automatically, means a burst of edits leaves a
    /// trail of multi-megabyte orphans behind.
    /// - Parameter url: A URL previously obtained from `wallpaperFileURL(extension:)`.
    func discardPendingWallpaper(at url: URL)

    /// Whether the given URL is a wallpaper KindleWall generated (i.e. lives in our directory).
    /// - Parameter url: Any file URL.
    func isOwnWallpaper(_ url: URL) -> Bool

    /// Deletes wallpapers left over from previous runs, keeping only the one currently on
    /// the desktop. Call once at launch.
    func sweepOrphanedWallpapers()

    /// Re-applies the newest surviving wallpaper if the desktop points at one of ours that has
    /// been deleted (which macOS renders as a blank desktop).
    /// - Returns: true if a repair was applied.
    @discardableResult
    func repairDesktopIfWallpaperMissing() -> Bool

    /// Whether the desktop points at one of our wallpapers that no longer exists, which macOS
    /// renders as a blank desktop.
    func isDesktopWallpaperMissing() -> Bool

    /// Whether any wallpaper we generated still exists on disk.
    ///
    /// False means there is nothing of ours to show and nothing to restore from — which happens
    /// when the launch sweep finds the desktop set to something that is not ours and clears the
    /// directory. Without noticing that, the app would sit there producing nothing until the
    /// next rotation tick, which the user experiences as the wallpaper having stopped working.
    var hasWallpaperOnDisk: Bool { get }

    /// A fresh, unused URL inside the wallpapers directory.
    /// - Parameter extension: File extension without the dot, e.g. `"heic"`.
    func wallpaperFileURL(extension ext: String) -> URL

    /// Creates the wallpapers directory if it does not exist.
    /// - Throws: `KindleWallError.directoryCreationFailed`.
    func prepareWallpaperDirectory() throws
}

extension WallpaperManagerProtocol {
    /// Applies a wallpaper and propagates it to every Space, which is what almost every caller
    /// wants. Only the automatic design-apply path passes `false`.
    func setWallpaper(fileURL: URL) throws {
        try setWallpaper(fileURL: fileURL, propagateToAllSpaces: true)
    }
}

// MARK: - Implementation

/// Manages applying and restoring desktop wallpapers using NSWorkspace.
///
/// ## How other Spaces get the wallpaper
///
/// `NSWorkspace.setDesktopImageURL` only reaches the **active** Space, so the app used to also
/// shell out to System Events (`tell every desktop to set picture …`) on every apply, believing
/// that covered the rest.
///
/// It does not. In System Events a `desktop` is a **display**, not a Space. Measured on this
/// machine — 12 Spaces, one display — running that script changed exactly the desktops
/// `setDesktopImageURL` had already changed, and left the other Spaces untouched. It was pure
/// cost: ~115 ms of blocked thread per apply, an Automation permission prompt, and a slow
/// asynchronous write that could land *after* its file had been pruned, pointing Spaces at a file
/// that no longer existed. macOS then renders that deleted file from cache forever, which is what
/// "the wallpaper stopped changing" turned out to be.
///
/// Other Spaces are covered by `activeSpaceDidChange` instead: each one gets the current
/// wallpaper the first time it is visited, and only if it is not already showing it.
/// **Isolation contract.** `@unchecked Sendable` is claimed here, not assumed, and it rests on
/// two disciplines that the code keeps and this comment names so a future edit cannot break one
/// without noticing:
///
/// 1. State reachable from background work — `pendingWrites` and `syncGeneration` — is touched
///    only while `syncLock` is held. Those are the two the render path and the prune path race
///    over.
/// 2. Everything else — `currentWallpaperURL`, `previousWallpaperURL`, `spaceChangeWork`,
///    `storageService` — is main-thread-only, because it is written from the `NSWorkspace` swap
///    and the space-change observer, both of which are main-thread by construction.
///
/// Adding a stored property means choosing a side: lock it, or keep it on the main thread.
final class WallpaperManager: WallpaperManagerProtocol, @unchecked Sendable {
    private var storageService: StorageServiceProtocol

    /// Where generated wallpapers live. Injectable so pruning can be tested against a
    /// throwaway directory instead of the user's real Application Support folder.
    private let wallpapersDirectory: URL

    private(set) var previousWallpaperURL: URL?

    /// The last wallpaper URL applied by KindleWall — used by the space-change observer.
    private var currentWallpaperURL: URL?

    /// Debounces bursts of Space changes (Ctrl+arrow through five desktops fires five times).
    private var spaceChangeWork: DispatchWorkItem?

    /// Opt-in all-Spaces sync. Writes macOS's own wallpaper store — see `WallpaperStoreSync`.
    private let storeSync: WallpaperStoreSyncProtocol

    /// Serial queue for the store sync. It writes a file and blocks on `killall`, neither of
    /// which belongs on the main thread or on Swift's cooperative pool — blocking a cooperative
    /// thread starves every other async task in the app, renders included.
    private let syncQueue = DispatchQueue(label: "\(Constants.App.bundleIdentifier).spaceSync",
                                          qos: .utility)
    private let syncLock = NSLock()
    private var syncGeneration = 0

    /// Files handed out by `wallpaperFileURL` that are not on the desktop yet, with the time
    /// they were claimed.
    ///
    /// Pruning enumerates the directory on a background queue, so without this an earlier
    /// apply's prune could run *after* a later apply wrote its file but *before* that apply
    /// recorded it as current — deleting the very file the desktop is about to point at.
    /// macOS then keeps drawing the deleted image from cache with no way to refresh it, which
    /// is exactly the "wallpaper froze and stopped changing" failure this app has already been
    /// bitten by. Applies used to be minutes apart, which made the window academic; once design
    /// edits apply on their own they arrive a second apart, in bursts.
    ///
    /// Entries are ignored once older than `pendingWriteTTL`, so a render that dies without
    /// releasing its URL can never block pruning permanently.
    private var pendingWrites: [String: Date] = [:]
    private static let pendingWriteTTL: TimeInterval = 120

    private let logger = Logger(subsystem: Constants.App.bundleIdentifier, category: "wallpaper")

    init(storageService: StorageServiceProtocol,
         wallpapersDirectory: URL = Constants.Paths.wallpapersDirectory,
         storeSync: WallpaperStoreSyncProtocol = WallpaperStoreSync()) {
        self.storageService = storageService
        self.wallpapersDirectory = wallpapersDirectory
        self.storeSync = storeSync
        self.previousWallpaperURL = storageService.previousWallpaperURL

        // Observe Mission Control space changes so we can re-apply the wallpaper
        // whenever the user switches to (or creates) a space that hasn't received it yet.
        // This requires no special permissions and works whether running from Xcode or installed.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        spaceChangeWork?.cancel()
    }

    func wallpaperFileURL(extension ext: String) -> URL {
        let url = wallpapersDirectory.appendingPathComponent("kindlewall_\(UUID().uuidString).\(ext)")
        notePendingWrite(url)
        return url
    }

    func discardPendingWallpaper(at url: URL) {
        clearPendingWrite(url)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Pending write bookkeeping

    private func notePendingWrite(_ url: URL) {
        syncLock.lock()
        defer { syncLock.unlock() }
        pendingWrites[url.standardizedFileURL.path] = Date()
    }

    private func clearPendingWrite(_ url: URL) {
        syncLock.lock()
        defer { syncLock.unlock() }
        pendingWrites.removeValue(forKey: url.standardizedFileURL.path)
    }

    /// Paths still being written, dropping anything past the TTL.
    private func livePendingWritePaths() -> Set<String> {
        syncLock.lock()
        defer { syncLock.unlock() }
        let cutoff = Date().addingTimeInterval(-Self.pendingWriteTTL)
        pendingWrites = pendingWrites.filter { $0.value > cutoff }
        return Set(pendingWrites.keys)
    }

    func prepareWallpaperDirectory() throws {
        try ensureWallpaperDirectoryExists()
    }

    func writeWallpaperPNG(image: NSImage) throws -> URL {
        let fileURL = wallpaperFileURL(extension: "png")
        do {
            try ensureWallpaperDirectoryExists()
            try Perf.measure("png.write") { try image.savePNG(to: fileURL) }
        } catch {
            // Release the claim, or a write that never happened would shield a nonexistent
            // path from pruning until the TTL expires.
            discardPendingWallpaper(at: fileURL)
            throw error
        }
        return fileURL
    }

    func setWallpaper(image: NSImage) throws {
        // Save image to disk first, then apply. (For the async apply path in MainViewModel
        // the encode/write half is `writeWallpaperPNG` run off-main; this convenience keeps
        // the synchronous one-shot callers — e.g. onboarding — working unchanged.)
        let fileURL = try writeWallpaperPNG(image: image)
        try setWallpaper(fileURL: fileURL)
    }

    func setWallpaper(fileURL: URL, propagateToAllSpaces: Bool = true) throws {
        // Capture current wallpaper before changing
        captureCurrentWallpaper()

        // Track so the space-change observer knows which wallpaper to re-apply
        currentWallpaperURL = fileURL
        // On the desktop now, so it no longer needs the pending-write shield; `currentWallpaperURL`
        // protects it from here on.
        clearPendingWrite(fileURL)

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            throw KindleWallError.screenNotAvailable
        }

        // Apply immediately to the active space on every screen (instant visual feedback)
        try Perf.measure("desktop.set", "\(screens.count) ekran") {
            for screen in screens {
                do {
                    try NSWorkspace.shared.setDesktopImageURL(fileURL, for: screen, options: [:])
                } catch {
                    throw KindleWallError.wallpaperApplyFailed(underlying: error)
                }
            }
        }

        // Prune only after the new wallpaper is on screen — pruning earlier would risk
        // deleting the file the desktop is about to point at.
        pruneWallpapers(keeping: [fileURL])

        if propagateToAllSpaces && storageService.syncAllSpaces {
            syncEverySpace(to: fileURL)
        }
    }

    func syncCurrentWallpaperToAllSpaces() {
        guard storageService.syncAllSpaces, let fileURL = currentWallpaperURL else { return }
        syncEverySpace(to: fileURL)
    }

    /// Pushes `fileURL` to every Mission Control Space, off the main thread.
    ///
    /// Coalesced by generation: a sync superseded by a newer apply is dropped rather than run,
    /// so clicking through wallpapers cannot queue up a series of agent restarts.
    private func syncEverySpace(to fileURL: URL) {
        syncLock.lock()
        syncGeneration &+= 1
        let generation = syncGeneration
        syncLock.unlock()

        syncQueue.async { [weak self] in
            guard let self else { return }
            self.syncLock.lock()
            let current = self.syncGeneration
            self.syncLock.unlock()
            guard current == generation else { return }

            let entries = self.storeSync.syncAllSpaces(to: fileURL)
            if entries == 0 {
                self.logger.notice("tüm-space eşitlemesi bir şey değiştirmedi; diğer alanlar ziyaret edildiklerinde güncellenecek")
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
        currentWallpaperURL = nil
    }

    func pruneWallpapers(keeping keep: [URL]) {
        // Whatever we last put on the desktop always survives, even if the caller forgot to list
        // it. Deleting the file the desktop points at does not blank it — macOS keeps drawing the
        // image from cache — it freezes it, permanently, with no way to refresh. That is what
        // "the wallpaper stopped changing" was.
        // Built as a `let` so the closure below captures an immutable value: a mutable local
        // reaching concurrently-executing code is a data race the compiler cannot rule out,
        // even when — as here — every mutation happens before the dispatch.
        let keepPaths = Set(keep.map(\.standardizedFileURL.path))
            .union(currentWallpaperURL.map { [$0.standardizedFileURL.path] } ?? [])

        // Everything below is filesystem work with no AppKit in it, so the whole body runs off
        // the main thread. It used to list the directory and make a synchronous XPC call to the
        // wallpaper agent on the main thread, on every single apply.
        let directory = wallpapersDirectory
        let logger = self.logger
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            ) else { return }   // directory missing or unreadable — nothing to prune

            // Read the in-flight set *here*, not at dispatch time: the whole point is to see
            // files claimed after this prune was scheduled.
            var keepPaths = keepPaths
            if let self { keepPaths.formUnion(self.livePendingWritePaths()) }

            let doomed = entries.filter { !keepPaths.contains($0.standardizedFileURL.path) }
            guard !doomed.isEmpty else { return }

            logger.info("prune siliyor: \(doomed.map(\.lastPathComponent).joined(separator: ", "), privacy: .public) | koruyor: \(keepPaths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "), privacy: .public)")

            for url in doomed {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    func isOwnWallpaper(_ url: URL) -> Bool {
        // Compare against the directory path plus a trailing separator so a sibling
        // directory sharing the same prefix ("wallpapers-backup") never matches.
        let root = wallpapersDirectory.standardizedFileURL.path + "/"
        return url.standardizedFileURL.path.hasPrefix(root)
    }

    func sweepOrphanedWallpapers() {
        let current = NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
        sweepOrphanedWallpapers(currentDesktopURL: current)
    }

    /// Testable core: `currentDesktopURL` is injected instead of read from NSWorkspace.
    func sweepOrphanedWallpapers(currentDesktopURL: URL?) {
        // Only a *live* wallpaper of ours is worth keeping. If the desktop points at one of our
        // files that no longer exists, the reference is already stale — but that is precisely
        // when the directory must not be emptied, because the newest surviving file is the only
        // thing that can repair the desktop. So in that case, keep the newest and drop the rest.
        if let currentDesktopURL, isOwnWallpaper(currentDesktopURL) {
            if FileManager.default.fileExists(atPath: currentDesktopURL.path) {
                pruneWallpapers(keeping: [currentDesktopURL])
                return
            }
            if let newest = newestWallpaper() {
                pruneWallpapers(keeping: [newest])
                return
            }
        }
        pruneWallpapers(keeping: [])
    }

    /// The most recently written file in our directory, used to recover a stale desktop reference.
    private func newestWallpaper() -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: wallpapersDirectory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }

        return entries.max { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return l < r
        }
    }

    func isDesktopWallpaperMissing() -> Bool {
        guard let screen = NSScreen.main,
              let current = NSWorkspace.shared.desktopImageURL(for: screen),
              isOwnWallpaper(current) else { return false }
        return !FileManager.default.fileExists(atPath: current.path)
    }

    var hasWallpaperOnDisk: Bool {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: wallpapersDirectory, includingPropertiesForKeys: nil
        )) ?? []
        return !entries.isEmpty
    }

    @discardableResult
    func repairDesktopIfWallpaperMissing() -> Bool {
        guard isDesktopWallpaperMissing() else { return false }

        // The desktop is pointing at one of our files that has been deleted, so macOS is showing
        // nothing. Put the newest surviving wallpaper back rather than leaving it blank.
        guard let replacement = newestWallpaper() else { return false }
        try? setWallpaper(fileURL: replacement)
        return true
    }

    // MARK: - Private

    /// Fires whenever the user switches to a different Mission Control space (or activates a new one).
    ///
    /// Applying unconditionally made every Mission Control switch pay a full wallpaper decode in
    /// the system's wallpaper agent, even when the Space already had the right picture — which is
    /// what made switching desktops stutter. Now the burst is debounced and each screen is only
    /// touched when it is actually showing something else.
    @objc private func activeSpaceDidChange(_ notification: Notification) {
        guard storageService.applyToAllSpaces else { return }
        guard let wallpaperURL = currentWallpaperURL ?? newestWallpaper() else { return }
        guard FileManager.default.fileExists(atPath: wallpaperURL.path) else { return }

        spaceChangeWork?.cancel()
        // `NSScreen.screens` is AppKit state, so it is snapshotted here on the main thread; the
        // comparison and the set then run off it.
        let screens = NSScreen.screens
        let work = DispatchWorkItem { [weak self] in
            self?.applyToScreensThatNeedIt(wallpaperURL, screens: screens)
        }
        spaceChangeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// Sets `url` only on the screens not already showing it.
    private func applyToScreensThatNeedIt(_ url: URL, screens: [NSScreen]) {
        let target = url.standardizedFileURL.path
        for screen in screens {
            let onScreen = NSWorkspace.shared.desktopImageURL(for: screen)?.standardizedFileURL.path
            guard onScreen != target else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    }

    private func captureCurrentWallpaper() {
        // Once we have set the desktop ourselves, the wallpaper on screen is our own file —
        // which the `isOwnWallpaper` guard below would reject anyway. Reading it again costs a
        // synchronous XPC round-trip into the wallpaper agent on the main thread, on every
        // apply including every scheduler tick, to learn something already known.
        guard currentWallpaperURL == nil else { return }

        guard let screen = NSScreen.main,
              let currentURL = NSWorkspace.shared.desktopImageURL(for: screen) else { return }

        // Never record our own output as "the previous wallpaper". Without this guard the second
        // apply overwrites the user's real wallpaper with a KindleWall image and "restore
        // previous" becomes a no-op forever.
        guard !isOwnWallpaper(currentURL) else { return }

        previousWallpaperURL = currentURL
        storageService.previousWallpaperURL = currentURL
    }

    private func ensureWallpaperDirectoryExists() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: wallpapersDirectory.path) {
            do {
                try fm.createDirectory(at: wallpapersDirectory, withIntermediateDirectories: true)
            } catch {
                throw KindleWallError.directoryCreationFailed(underlying: error)
            }
        }
    }
}
