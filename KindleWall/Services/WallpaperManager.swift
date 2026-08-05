import AppKit
import Foundation

// MARK: - Protocol

/// Protocol for applying wallpaper images to the desktop.
protocol WallpaperManagerProtocol {
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
    /// - Parameter fileURL: The URL of the wallpaper image file.
    /// - Throws: KindleWallError if the wallpaper cannot be applied.
    func setWallpaper(fileURL: URL) throws

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

    /// Whether the given URL is a wallpaper KindleWall generated (i.e. lives in our directory).
    /// - Parameter url: Any file URL.
    func isOwnWallpaper(_ url: URL) -> Bool
}

// MARK: - Implementation

/// Manages applying and restoring desktop wallpapers using NSWorkspace.
final class WallpaperManager: WallpaperManagerProtocol {
    private var storageService: StorageServiceProtocol

    /// Where generated wallpapers live. Injectable so pruning can be tested against a
    /// throwaway directory instead of the user's real Application Support folder.
    private let wallpapersDirectory: URL

    private(set) var previousWallpaperURL: URL?

    /// The last wallpaper URL applied by KindleWall — used by the space-change observer.
    private var currentWallpaperURL: URL?

    init(storageService: StorageServiceProtocol,
         wallpapersDirectory: URL = Constants.Paths.wallpapersDirectory) {
        self.storageService = storageService
        self.wallpapersDirectory = wallpapersDirectory
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

    func writeWallpaperPNG(image: NSImage) throws -> URL {
        let fileName = "kindlewall_\(UUID().uuidString).png"
        let fileURL = wallpapersDirectory.appendingPathComponent(fileName)

        try ensureWallpaperDirectoryExists()
        try image.savePNG(to: fileURL)
        return fileURL
    }

    func setWallpaper(image: NSImage) throws {
        // Save image to disk first, then apply. (For the async apply path in MainViewModel
        // the encode/write half is `writeWallpaperPNG` run off-main; this convenience keeps
        // the synchronous one-shot callers — e.g. onboarding — working unchanged.)
        let fileURL = try writeWallpaperPNG(image: image)
        try setWallpaper(fileURL: fileURL)
    }

    func setWallpaper(fileURL: URL) throws {
        // Capture current wallpaper before changing
        captureCurrentWallpaper()

        // Track so the space-change observer knows which wallpaper to re-apply
        currentWallpaperURL = fileURL

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            throw KindleWallError.screenNotAvailable
        }

        // Apply immediately to the active space on every screen (instant visual feedback)
        for screen in screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(fileURL, for: screen, options: [:])
            } catch {
                throw KindleWallError.wallpaperApplyFailed(underlying: error)
            }
        }

        // Apply to all Mission Control spaces in the background via osascript
        if storageService.applyToAllSpaces {
            applyToAllSpacesInBackground(fileURL: fileURL)
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
        if storageService.applyToAllSpaces {
            applyToAllSpacesInBackground(fileURL: previousURL)
        }
    }

    func pruneWallpapers(keeping keep: [URL]) {
        let keepPaths = Set(keep.map(\.standardizedFileURL.path))
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: wallpapersDirectory, includingPropertiesForKeys: nil
        ) else { return }   // directory missing or unreadable — nothing to prune

        for url in entries where !keepPaths.contains(url.standardizedFileURL.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func isOwnWallpaper(_ url: URL) -> Bool {
        // Compare against the directory path plus a trailing separator so a sibling
        // directory sharing the same prefix ("wallpapers-backup") never matches.
        let root = wallpapersDirectory.standardizedFileURL.path + "/"
        return url.standardizedFileURL.path.hasPrefix(root)
    }

    // MARK: - Private

    /// Fires whenever the user switches to a different Mission Control space (or activates a new one).
    /// Applies the current KindleWall wallpaper to all screens in the newly active space.
    /// Uses only NSWorkspace — no special Automation permission required.
    @objc private func activeSpaceDidChange(_ notification: Notification) {
        guard storageService.applyToAllSpaces,
              let wallpaperURL = currentWallpaperURL else { return }
        DispatchQueue.main.async {
            for screen in NSScreen.screens {
                try? NSWorkspace.shared.setDesktopImageURL(wallpaperURL, for: screen, options: [:])
            }
        }
    }

    /// Uses System Events AppleScript to apply the wallpaper to every Space on every screen.
    /// `NSWorkspace.setDesktopImageURL` only targets the *active* Space; osascript covers all immediately.
    /// Runs in background — caller gets instant feedback from the NSWorkspace call above.
    /// NOTE: Requires Automation permission (System Settings → Privacy & Security → Automation).
    /// When running from Xcode this often fails silently; the activeSpaceDidChange observer handles
    /// coverage in that case (lazily, on each space visit).
    private func applyToAllSpacesInBackground(fileURL: URL) {
        // Escape backslashes and quotes so the path is safe inside an AppleScript string literal
        let safePath = fileURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "System Events"
            tell every desktop
                set picture to "\(safePath)"
            end tell
        end tell
        """

        Task.detached(priority: .background) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                // Most likely cause: Automation permission not granted for System Events.
                // Go to System Settings → Privacy & Security → Automation and enable it for KindleWall.
                print("[WallpaperManager] osascript failed (exit \(process.terminationStatus)) — Automation permission for System Events may not be granted")
            }
        }
    }

    private func captureCurrentWallpaper() {
        guard let screen = NSScreen.main,
              let currentURL = NSWorkspace.shared.desktopImageURL(for: screen) else { return }

        // Never record our own output as "the previous wallpaper". This method runs on every
        // apply, so without this guard the second apply overwrites the user's real wallpaper
        // with a KindleWall image and "restore previous" becomes a no-op forever.
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
