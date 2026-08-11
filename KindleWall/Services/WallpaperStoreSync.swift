import Foundation
import OSLog

// MARK: - Protocol

/// Points **every** Mission Control Space at one wallpaper, by writing macOS's own wallpaper store.
protocol WallpaperStoreSyncProtocol {
    /// Rewrites the store so every Space shows `fileURL`, then asks the wallpaper agent to reload.
    /// - Returns: how many entries were rewritten. `0` means nothing was changed — the store was
    ///   missing, unreadable, or had no image choices — and the caller should assume the other
    ///   Spaces still have their old wallpaper.
    @discardableResult
    func syncAllSpaces(to fileURL: URL) -> Int
}

// MARK: - Implementation

/// Writes the wallpaper store that macOS's own Wallpaper settings pane writes.
///
/// ## Why this exists
///
/// Measured on this machine (12 Spaces, one display):
///
/// | mechanism | Spaces changed |
/// |---|---|
/// | `NSWorkspace.setDesktopImageURL` per screen | 1 of 12 — the active Space only |
/// | System Events `tell every desktop to set picture` | 0 more — a `desktop` there is a *display* |
/// | rewriting this store + restarting `WallpaperAgent` | **12 of 12** |
///
/// So there is exactly one mechanism that does what "change every desktop at once" means, and
/// this is it. The store lives at
/// `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist` and holds one entry per
/// Space per display. Each entry carries a small nested binary plist:
///
///     { type: "imageFile", url: { relative: "file:///…" } }
///
/// ## Why it is opt-in, and defensive
///
/// The format is undocumented and could change in any macOS release, and the only way to make the
/// agent reload is to kill it — SIP refuses `launchctl kickstart` for system agents. So:
///
/// * the original store is copied aside before the first write, once, and kept;
/// * only `Configuration` values whose sibling `Provider` is the *image* provider are replaced.
///   Screensaver ("Idle") choices use a different provider and an empty blob, so they cannot be
///   caught by accident — there is a test for that;
/// * every other key, including ones this code does not understand, is copied through verbatim;
/// * anything unexpected aborts the write and returns 0 rather than guessing.
///
/// One consequence deserves naming: once the store points at our file, deleting that file would
/// freeze **every** Space on a cached image, because macOS keeps drawing a deleted wallpaper and
/// can never refresh it. `WallpaperManager.pruneWallpapers` always keeps the file it last applied,
/// which is the same file written here.
final class WallpaperStoreSync: WallpaperStoreSyncProtocol {

    private let storeURL: URL
    private let backupURL: URL
    /// Injected so tests can assert the rewrite without killing a system process.
    private let reloadAgent: () -> Void

    private let logger = Logger(subsystem: Constants.App.bundleIdentifier, category: "spacesync")

    /// The provider name macOS uses for a plain image wallpaper. Idle/screensaver entries use
    /// `default` (with an empty configuration), which is why matching on this is safe.
    static let imageProvider = "com.apple.wallpaper.choice.image"

    init(storeURL: URL = Constants.Paths.wallpaperStore,
         backupURL: URL = Constants.Paths.wallpaperStoreBackup,
         reloadAgent: @escaping () -> Void = WallpaperStoreSync.restartWallpaperAgent) {
        self.storeURL = storeURL
        self.backupURL = backupURL
        self.reloadAgent = reloadAgent
    }

    @discardableResult
    func syncAllSpaces(to fileURL: URL) -> Int {
        // Never point the store at something that is not there: every Space would freeze on a
        // cached image with no way back.
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.error("eşitleme atlandı: dosya yok — \(fileURL.lastPathComponent, privacy: .public)")
            return 0
        }
        guard let data = try? Data(contentsOf: storeURL),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) else {
            logger.notice("duvar kağıdı store'u okunamadı — eşitleme atlandı")
            return 0
        }

        backUpOnce(data)

        var rewritten = 0
        let configuration = Self.makeConfiguration(for: fileURL)
        let updated = Self.rewritingImageChoices(in: root, to: configuration, count: &rewritten)
        guard rewritten > 0 else {
            logger.notice("store'da görüntü girdisi yok — eşitleme atlandı")
            return 0
        }

        guard let out = try? PropertyListSerialization.data(
            fromPropertyList: updated, format: .binary, options: 0
        ) else {
            logger.error("store yeniden serileştirilemedi — eşitleme atlandı")
            return 0
        }

        do {
            try out.write(to: storeURL)
        } catch {
            logger.error("store yazılamadı: \(error.localizedDescription, privacy: .public)")
            return 0
        }

        // The agent holds the store in memory, so it has to be restarted to notice. SIP blocks
        // the polite route (`launchctl kickstart`), which is a large part of why this is opt-in.
        Perf.measure("spaces.storeSync", "\(rewritten) girdi") { reloadAgent() }
        logger.info("\(rewritten, privacy: .public) space girdisi eşitlendi")
        return rewritten
    }

    // MARK: - Pure transform (unit-tested; touches no system state)

    /// The nested binary plist macOS stores for an image wallpaper.
    static func makeConfiguration(for fileURL: URL) -> Data {
        let payload: [String: Any] = [
            "type": "imageFile",
            "url": ["relative": fileURL.absoluteString]
        ]
        // A failure here is impossible for this fixed shape, but an empty blob would blank the
        // desktop, so fall back to leaving the entry alone rather than writing nothing.
        return (try? PropertyListSerialization.data(fromPropertyList: payload,
                                                    format: .binary, options: 0)) ?? Data()
    }

    /// Returns a copy of `node` with every image choice's `Configuration` replaced.
    ///
    /// Everything else — keys this code has never heard of, screensaver entries, timestamps — is
    /// copied through untouched. A structural surprise therefore degrades to "changed nothing"
    /// rather than "wrote something wrong into a system file".
    static func rewritingImageChoices(in node: Any, to configuration: Data,
                                      count: inout Int) -> Any {
        guard !configuration.isEmpty else { return node }

        if var dict = node as? [String: Any] {
            if dict["Provider"] as? String == imageProvider {
                dict["Configuration"] = configuration
                count += 1
                return dict
            }
            for (key, value) in dict {
                dict[key] = rewritingImageChoices(in: value, to: configuration, count: &count)
            }
            return dict
        }
        if let array = node as? [Any] {
            return array.map { rewritingImageChoices(in: $0, to: configuration, count: &count) }
        }
        return node
    }

    // MARK: - Private

    /// Keeps the store as macOS wrote it, once, before this app ever changes it. Our
    /// re-serialisation is not byte-identical to Apple's (it loses their object sharing, so the
    /// file roughly doubles), and if the format ever moves on, this is what makes it recoverable.
    private func backUpOnce(_ original: Data) {
        guard !FileManager.default.fileExists(atPath: backupURL.path) else { return }
        do {
            try FileManager.default.createDirectory(
                at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try original.write(to: backupURL)
            logger.info("duvar kağıdı store'unun ilk yedeği alındı: \(self.backupURL.path, privacy: .public)")
        } catch {
            logger.error("store yedeği alınamadı: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Restarts the wallpaper agent so it re-reads the store. Blocking — call it off the main
    /// thread and off Swift's cooperative pool.
    static func restartWallpaperAgent() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["WallpaperAgent"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
