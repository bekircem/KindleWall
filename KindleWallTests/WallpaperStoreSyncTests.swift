import XCTest
@testable import KindleWall

/// Covers the one piece of this feature that must never be wrong: what gets written into macOS's
/// wallpaper store. The store is a system file shared with the screensaver and with settings this
/// app knows nothing about, so the transform is exercised against a fixture that mirrors the real
/// structure — never against the machine's own store.
final class WallpaperStoreSyncTests: XCTestCase {

    private var tempDir: URL!
    private var storeURL: URL!
    private var backupURL: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KindleWallStore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storeURL = tempDir.appendingPathComponent("Index.plist")
        backupURL = tempDir.appendingPathComponent("backup/Index.plist")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Fixture

    /// Mirrors the real store's shape, read off this machine:
    /// `Spaces[<uuid>].Default.Desktop.Content.Choices[]`, the same again per display, plus an
    /// `Idle` (screensaver) sibling that uses the `default` provider and an empty configuration.
    private func makeFixture(imageURL: String = "file:///old/wallpaper.png") -> [String: Any] {
        func imageChoice() -> [String: Any] {
            ["Configuration": WallpaperStoreSync.makeConfiguration(for: URL(string: imageURL)!),
             "Files": [], "Provider": WallpaperStoreSync.imageProvider]
        }
        func idleChoice() -> [String: Any] {
            ["Configuration": Data(), "Files": [], "Provider": "default"]
        }
        func content(_ choice: [String: Any]) -> [String: Any] {
            ["Choices": [choice], "EncodedOptionValues": "$null", "Shuffle": "$null"]
        }
        func slot(_ choice: [String: Any]) -> [String: Any] {
            ["Content": content(choice), "LastSet": Date(), "LastUse": Date()]
        }
        let perDisplay: [String: Any] = ["Desktop": slot(imageChoice()), "Idle": slot(idleChoice())]

        return [
            "SystemDefault": ["Desktop": slot(imageChoice())],
            "AllSpacesAndDisplays": ["Idle": slot(idleChoice()), "Type": "idle"],
            "Displays": ["D1": perDisplay, "D2": perDisplay],
            "Spaces": [
                "S1": ["Default": ["Desktop": slot(imageChoice()), "Idle": slot(idleChoice()),
                                   "Type": "individual"],
                       "Displays": ["D1": perDisplay]],
                "S2": ["Default": ["Desktop": slot(imageChoice()), "Idle": slot(idleChoice()),
                                   "Type": "individual"],
                       "Displays": ["D1": perDisplay]]
            ]
        ]
    }

    private func writeFixture(_ fixture: [String: Any]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: fixture,
                                                      format: .binary, options: 0)
        try data.write(to: storeURL)
    }

    /// A real file, because the sync refuses to point the store at something that is not there.
    private func makeWallpaperFile() throws -> URL {
        let url = tempDir.appendingPathComponent("kindlewall.heic")
        try Data("not really an image".utf8).write(to: url)
        return url
    }

    private func makeSync(reload: @escaping () -> Void = {}) -> WallpaperStoreSync {
        WallpaperStoreSync(storeURL: storeURL, backupURL: backupURL, reloadAgent: reload)
    }

    /// Every `Configuration` in the tree, paired with its provider.
    private func choices(in node: Any) -> [(provider: String, configuration: Data)] {
        if let dict = node as? [String: Any] {
            if let provider = dict["Provider"] as? String,
               let configuration = dict["Configuration"] as? Data {
                return [(provider, configuration)]
            }
            return dict.values.flatMap { choices(in: $0) }
        }
        if let array = node as? [Any] { return array.flatMap { choices(in: $0) } }
        return []
    }

    private func readStore() throws -> Any {
        try PropertyListSerialization.propertyList(from: Data(contentsOf: storeURL), format: nil)
    }

    private func url(inside configuration: Data) -> String? {
        guard let plist = try? PropertyListSerialization.propertyList(from: configuration, format: nil),
              let dict = plist as? [String: Any],
              let url = dict["url"] as? [String: Any] else { return nil }
        return url["relative"] as? String
    }

    // MARK: - Tests

    func test_everyImageChoicePointsAtTheNewWallpaper() throws {
        let fixture = makeFixture()
        try writeFixture(fixture)
        let wallpaper = try makeWallpaperFile()

        // Derived rather than hardcoded: the count is a property of the fixture, and asserting a
        // literal only tests whether the fixture was counted correctly by hand.
        let expected = choices(in: fixture).filter { $0.provider == WallpaperStoreSync.imageProvider }.count
        XCTAssertGreaterThan(expected, 1, "fikstürde birden fazla görüntü girdisi olmalı")

        let rewritten = makeSync().syncAllSpaces(to: wallpaper)

        XCTAssertEqual(rewritten, expected, "her görüntü girdisi yeniden yazılmalı")
        let images = choices(in: try readStore()).filter { $0.provider == WallpaperStoreSync.imageProvider }
        XCTAssertFalse(images.isEmpty)
        for image in images {
            XCTAssertEqual(url(inside: image.configuration), wallpaper.absoluteString)
        }
    }

    /// The store is shared with the screensaver. Idle entries use a different provider and an
    /// empty blob; writing an image configuration into one would change what the user sees when
    /// the machine goes idle, which this feature has no business touching.
    func test_screensaverEntriesAreLeftAlone() throws {
        try writeFixture(makeFixture())
        let wallpaper = try makeWallpaperFile()

        makeSync().syncAllSpaces(to: wallpaper)

        let idle = choices(in: try readStore()).filter { $0.provider == "default" }
        XCTAssertFalse(idle.isEmpty, "fikstürde idle girdisi olmalı")
        for entry in idle {
            XCTAssertTrue(entry.configuration.isEmpty, "idle girdisi değiştirilmemeli")
        }
    }

    /// Keys this code has never heard of must survive: the store belongs to macOS, not to us.
    func test_unknownKeysArePreserved() throws {
        var fixture = makeFixture()
        fixture["SomeFutureKeyWeDoNotKnow"] = ["nested": ["value": 42]]
        try writeFixture(fixture)
        let wallpaper = try makeWallpaperFile()

        makeSync().syncAllSpaces(to: wallpaper)

        let root = try XCTUnwrap(try readStore() as? [String: Any])
        let future = try XCTUnwrap(root["SomeFutureKeyWeDoNotKnow"] as? [String: Any])
        XCTAssertEqual((future["nested"] as? [String: Any])?["value"] as? Int, 42)
        XCTAssertNotNil(root["AllSpacesAndDisplays"], "dokunulmayan üst düzey anahtarlar kalmalı")
    }

    /// Pointing the store at a file that does not exist would freeze *every* Space on a cached
    /// image, because macOS keeps drawing a deleted wallpaper and can never refresh it.
    func test_missingWallpaperFileIsRefused() throws {
        try writeFixture(makeFixture())
        let before = try Data(contentsOf: storeURL)

        var reloaded = false
        let rewritten = makeSync(reload: { reloaded = true })
            .syncAllSpaces(to: tempDir.appendingPathComponent("does-not-exist.heic"))

        XCTAssertEqual(rewritten, 0)
        XCTAssertFalse(reloaded, "dosya yokken ajan yeniden başlatılmamalı")
        XCTAssertEqual(try Data(contentsOf: storeURL), before, "store dokunulmamış olmalı")
    }

    func test_unreadableStoreIsRefusedRatherThanRecreated() throws {
        try Data("bu bir plist değil".utf8).write(to: storeURL)
        let wallpaper = try makeWallpaperFile()

        var reloaded = false
        XCTAssertEqual(makeSync(reload: { reloaded = true }).syncAllSpaces(to: wallpaper), 0)
        XCTAssertFalse(reloaded)
    }

    func test_storeWithNoImageChoicesIsLeftAlone() throws {
        try writeFixture(["AllSpacesAndDisplays": ["Type": "idle"]])
        let wallpaper = try makeWallpaperFile()

        var reloaded = false
        XCTAssertEqual(makeSync(reload: { reloaded = true }).syncAllSpaces(to: wallpaper), 0)
        XCTAssertFalse(reloaded, "değişiklik yoksa ajanı yeniden başlatmaya gerek yok")
    }

    /// The backup is the recovery path if Apple's format ever moves on, so it has to capture the
    /// store as *macOS* wrote it — not as we rewrote it on a later run.
    func test_backupKeepsTheOriginalAndIsWrittenOnlyOnce() throws {
        try writeFixture(makeFixture(imageURL: "file:///original/apple.heic"))
        let original = try Data(contentsOf: storeURL)
        let wallpaper = try makeWallpaperFile()

        let sync = makeSync()
        sync.syncAllSpaces(to: wallpaper)
        XCTAssertEqual(try Data(contentsOf: backupURL), original)

        sync.syncAllSpaces(to: wallpaper)
        XCTAssertEqual(try Data(contentsOf: backupURL), original,
                       "ikinci eşitleme yedeği ezmemeli")
    }

    func test_agentIsRestartedOnlyAfterASuccessfulWrite() throws {
        try writeFixture(makeFixture())
        let wallpaper = try makeWallpaperFile()

        var reloadCount = 0
        makeSync(reload: { reloadCount += 1 }).syncAllSpaces(to: wallpaper)
        XCTAssertEqual(reloadCount, 1)
    }
}
