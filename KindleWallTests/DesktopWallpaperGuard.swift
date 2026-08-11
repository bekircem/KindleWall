import AppKit
import XCTest

/// Restores the real desktop wallpaper after tests that apply one.
///
/// Tests apply wallpapers for real — there is no way to exercise the `NSWorkspace` path
/// otherwise — and they write them into throwaway temp directories that are deleted on teardown.
/// Restoring naively is not enough: `applyWallpaper` renders on a detached task, so an apply
/// started by a test can land *after* its `tearDown` has put the old wallpaper back, leaving the
/// desktop pointing at a temp file. The next test's `setUp` then captures that temp path as "the
/// original" and faithfully restores it — and the deleted-file reference propagates forward.
///
/// This was not theoretical: a full test run left this machine's desktop pointing at
/// `…/T/KindleWallStress-…/kindlewall_….heic`, which macOS renders from cache forever. The app
/// then swept its own directory empty at launch, because the desktop was showing something that
/// was not one of its files.
///
/// The guard fixes both halves: the captured wallpaper is only ever a real one (never a temp
/// path), and it is captured once for the whole bundle rather than per test.
enum DesktopWallpaperGuard {

    /// The wallpaper that was on the desktop before any test touched it. Captured once.
    private static var original: URL?
    private static var didCapture = false

    /// Records the user's real wallpaper. Safe to call from every `setUp`.
    static func capture() {
        guard !didCapture else { return }
        guard let url = NSScreen.main.flatMap({ NSWorkspace.shared.desktopImageURL(for: $0) }) else { return }
        // A temp path here means a previous run already leaked; do not enshrine it.
        guard !url.path.hasPrefix(NSTemporaryDirectory()),
              !url.path.hasPrefix("/private/tmp/") else { return }
        original = url
        didCapture = true
    }

    /// Puts the real wallpaper back, after giving any in-flight apply a moment to land so it
    /// cannot overwrite the restore.
    static func restore(settleFor seconds: TimeInterval = 0.6) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
        guard let original, FileManager.default.fileExists(atPath: original.path) else { return }
        for screen in NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(original, for: screen, options: [:])
        }
    }
}
