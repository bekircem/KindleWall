import XCTest
@testable import KindleWall

/// Everything the user has ever chosen lives in `UserDefaults`, and it is read on every launch
/// before anything is on screen. A value that is missing, corrupt, or written by an older build
/// must degrade to a default — if any of these getters could trap or throw, the app would be
/// unlaunchable until the user found and deleted a plist they do not know exists.
///
/// The corruption here is not hypothetical: an interrupted write, an iCloud merge, a hand-edited
/// plist and a downgraded build all produce exactly these shapes.
final class StorageServiceRobustnessTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "KindleWallStorageTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeStorage() -> StorageService { StorageService(defaults: defaults) }

    // MARK: - Nothing stored yet (first launch)

    func test_emptyDefaults_giveUsableDefaultsForEverything() {
        let storage = makeStorage()

        XCTAssertEqual(storage.selectedStyle, .night)
        XCTAssertEqual(storage.scheduleInterval, .hourly)
        XCTAssertEqual(storage.typography, .default)
        XCTAssertEqual(storage.longQuote, .default)
        XCTAssertTrue(storage.shownClippingIDs.isEmpty)
        XCTAssertTrue(storage.favoriteClippingIDs.isEmpty)
        XCTAssertNil(storage.customScheduleDate)
    }

    // MARK: - Corrupt JSON blobs

    func test_corruptTypographyBlob_fallsBackToDefaultInsteadOfTrapping() {
        defaults.set(Data("this is not json".utf8),
                     forKey: Constants.StorageKeys.typographySettings)

        XCTAssertEqual(makeStorage().typography, .default)
    }

    func test_corruptLongQuoteBlob_fallsBackToDefault() {
        defaults.set(Data([0x00, 0xFF, 0x00, 0xFF]),
                     forKey: Constants.StorageKeys.longQuoteSettings)

        XCTAssertEqual(makeStorage().longQuote, .default)
    }

    func test_typographyBlobThatIsValidJsonButTheWrongShape_fallsBackToDefault() {
        // What a schema change between builds looks like: parseable, but not this type.
        defaults.set(Data(#"{"unrelated":true}"#.utf8),
                     forKey: Constants.StorageKeys.typographySettings)

        XCTAssertEqual(makeStorage().typography, .default)
    }

    // MARK: - Values of the wrong type under the right key

    func test_stringWhereDataWasExpected_fallsBackRatherThanTrapping() {
        // `UserDefaults.data(forKey:)` returns nil for a non-data value; this pins that the
        // getter actually handles the nil rather than force-unwrapping it.
        defaults.set("plain string", forKey: Constants.StorageKeys.typographySettings)

        XCTAssertEqual(makeStorage().typography, .default)
    }

    func test_nonArrayWhereIdListWasExpected_yieldsAnEmptySet() {
        defaults.set(42, forKey: Constants.StorageKeys.shownClippingIDs)

        XCTAssertTrue(makeStorage().shownClippingIDs.isEmpty)
    }

    func test_idListWithUnparseableEntries_keepsTheGoodOnesAndDropsTheRest() {
        let good = UUID()
        defaults.set([good.uuidString, "not-a-uuid", ""],
                     forKey: Constants.StorageKeys.shownClippingIDs)

        // Losing one unreadable id is right; losing the whole shown-history because of it is not,
        // because the user would start seeing quotes they had already been shown.
        XCTAssertEqual(makeStorage().shownClippingIDs, [good])
    }

    // MARK: - Unknown enum cases

    func test_unknownStyleName_fallsBackToNightRatherThanFailing() {
        defaults.set("A Style From The Future", forKey: Constants.StorageKeys.selectedStyle)

        XCTAssertEqual(makeStorage().selectedStyle, .night)
    }

    func test_unknownScheduleInterval_fallsBackToHourly() {
        defaults.set("Her Yarım Yüzyılda", forKey: Constants.StorageKeys.scheduleInterval)

        XCTAssertEqual(makeStorage().scheduleInterval, .hourly)
    }

    // MARK: - Round trips

    func test_everySettingSurvivesAWriteAndReadOnAFreshInstance() throws {
        let storage = makeStorage()
        let ids: Set<UUID> = [UUID(), UUID()]

        storage.selectedStyle = .paper
        storage.scheduleInterval = .every6Hours
        storage.shownClippingIDs = ids
        storage.favoriteClippingIDs = ids
        var typography = TypographySettings.default
        typography.fontScale = 1.35
        storage.typography = typography

        // A second instance reads the same suite — this is what the next launch does.
        let reread = makeStorage()
        XCTAssertEqual(reread.selectedStyle, .paper)
        XCTAssertEqual(reread.scheduleInterval, .every6Hours)
        XCTAssertEqual(reread.shownClippingIDs, ids)
        XCTAssertEqual(reread.favoriteClippingIDs, ids)
        XCTAssertEqual(reread.typography.fontScale, typography.fontScale)
    }

    func test_constructingStorageOverCorruptDefaults_doesNotThrowOrHang() {
        // `init` runs a cleanup pass over the suite; it must survive junk under every key it
        // touches, because that is exactly the state it exists to clean up.
        for key in [Constants.StorageKeys.typographySettings,
                    Constants.StorageKeys.longQuoteSettings,
                    Constants.StorageKeys.selectedStyle,
                    Constants.StorageKeys.scheduleInterval,
                    Constants.StorageKeys.shownClippingIDs] {
            defaults.set(Data([0xFF, 0x00]), forKey: key)
        }

        let storage = makeStorage()
        XCTAssertEqual(storage.selectedStyle, .night)
        XCTAssertEqual(storage.typography, .default)
    }
}
