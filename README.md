# KindleWall

Turns your Kindle highlights into desktop wallpapers on macOS.

Point KindleWall at your Kindle's `My Clippings.txt` and it renders a passage from your own
library onto your desktop, rotating on a schedule you choose.

Available in **English and Turkish** — the app follows your system language, and macOS lets
you give it a language of its own under System Settings → General → Language & Region → Applications.

![KindleWall](docs/screenshots/main.png)

## Install

```sh
brew tap bekircem/tap
brew trust bekircem/tap      # Homebrew 6 requires this for third-party taps
brew install --cask kindlewall
```

Or take the signed, notarized DMG from
[Releases](https://github.com/bekircem/KindleWall/releases/latest).

**Requires macOS 26 (Tahoe) or later.**

## What it does

- **Reads your highlights.** Parses `My Clippings.txt` in both the English and Turkish Kindle
  formats, deduplicates by content, and skips bookmarks and notes.
- **Six styles** — Night, Paper, Grid, Dawn, Depth, Forest Light — with the type size fitted to
  each passage rather than clipped to a fixed box.
- **A wallpaper that follows the sun.** Optionally writes a dynamic HEIC whose colour
  temperature tracks the solar position, so the same passage warms and cools through the day.
- **Rotation you control.** Every book, one book at a time, only pinned books, or only
  favourites — every 30 minutes through to daily, or a custom interval. Shuffles without
  repeating until the pool is exhausted.
- **Capture from anywhere.** A global hotkey or the Services menu turns selected text in any
  app into a clipping.
- **Lives in the menu bar** and keeps running when you close the window.
- **Syncs across your Macs** through your own private iCloud database — optional, and off
  unless you are signed into iCloud.
- **Updates itself** via Sparkle, with EdDSA-signed releases.

## Build from source

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project KindleWall.xcodeproj -scheme KindleWall -configuration Debug build
```

Tests are a two-step run on purpose — the single-step `xcodebuild test` does not stage the
test bundle, and fails in a way that looks like a test failure but means the tests never ran:

```sh
xcodebuild -project KindleWall.xcodeproj -scheme KindleWall clean
xcodebuild build-for-testing -project KindleWall.xcodeproj -scheme KindleWall -destination 'platform=macOS,arch=arm64'
xcodebuild test-without-building -project KindleWall.xcodeproj -scheme KindleWall -destination 'platform=macOS,arch=arm64'
```

Always check the `Executed N tests` line before believing a result.

The app is written in Swift 6 language mode with `SWIFT_STRICT_CONCURRENCY: complete`, so
isolation violations are compile errors rather than warnings.

## Privacy

There is no analytics, no telemetry, and no server operated by this project. Precisely what
does and does not leave your Mac:

| | Where it goes |
|---|---|
| Your highlights | Nowhere — unless you are signed into iCloud, in which case **your own** private CloudKit database, and nowhere else |
| **Book titles** | Google Books and Open Library, as search queries, when the library screen fetches cover art |
| Update checks | GitHub, to read the appcast |

The cover lookup is worth stating plainly: opening the library sends the titles of your books
to two third-party services. Nothing else about you is attached, but the titles themselves say
something about what you read.

## License

[GPL-3.0](LICENSE)

## Trademark

KindleWall is not affiliated with, endorsed by, or sponsored by Amazon.
Kindle is a registered trademark of Amazon.com, Inc.

---

🇹🇷 [Türkçe README](README.tr.md)
