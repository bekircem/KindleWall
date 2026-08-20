import XCTest
@testable import KindleWall

/// The whole localization effort rests on one assumption: a String Catalog in the target makes
/// SwiftUI's `LocalizedStringKey` literals translatable and puts a `tr.lproj` in the built
/// bundle. Proving that with one string is cheap; discovering it is false after translating
/// 296 of them is not.
final class LocalizationTests: XCTestCase {

    func test_bundle_shipsBothLanguages() {
        let localizations = Set(Bundle.main.localizations)
        XCTAssertTrue(localizations.contains("en"), "English is missing: \(localizations.sorted())")
        XCTAssertTrue(localizations.contains("tr"), "Turkish is missing: \(localizations.sorted())")
    }

    func test_turkishBundle_translatesAKnownKey() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "tr", ofType: "lproj"),
                                 "no tr.lproj in the bundle")
        let trBundle = try XCTUnwrap(Bundle(path: path))
        let translated = trBundle.localizedString(forKey: "Current Quote", value: nil, table: nil)
        XCTAssertEqual(translated, "Şu Anki Alıntı",
                       "the catalog's Turkish value did not reach the built bundle")
    }

    /// Raw values are storage, not copy.
    ///
    /// `StorageService` writes these strings to UserDefaults, so translating one silently drops
    /// every existing user back to the fallback — their schedule quietly resets and nothing
    /// says why. A bulk translation pass did exactly that to `daily` and `custom` before this
    /// test existed. The Turkish spellings stay because they are already on disk.
    func test_rawValues_areStorageKeysAndDoNotChange() {
        XCTAssertEqual(ScheduleInterval.every30Minutes.rawValue, "30 Dakikada Bir")
        XCTAssertEqual(ScheduleInterval.hourly.rawValue, "Saatlik")
        XCTAssertEqual(ScheduleInterval.every3Hours.rawValue, "3 Saatte Bir")
        XCTAssertEqual(ScheduleInterval.every6Hours.rawValue, "6 Saatte Bir")
        XCTAssertEqual(ScheduleInterval.daily.rawValue, "Günlük")
        XCTAssertEqual(ScheduleInterval.custom.rawValue, "Özel")

        XCTAssertEqual(RotationMode.allRandom.rawValue, "allRandom")
        XCTAssertEqual(RotationMode.bookByBook.rawValue, "bookByBook")
        XCTAssertEqual(RotationMode.pinnedBooks.rawValue, "pinnedBooks")
        XCTAssertEqual(RotationMode.favorites.rawValue, "favorites")

        XCTAssertEqual(WallpaperStyle.night.rawValue, "Night")
        XCTAssertEqual(WallpaperStyle.paper.rawValue, "Paper")
        XCTAssertEqual(WallpaperStyle.grid.rawValue, "Grid")
        XCTAssertEqual(WallpaperStyle.dawn.rawValue, "Dawn")
        XCTAssertEqual(WallpaperStyle.depth.rawValue, "Depth")
        XCTAssertEqual(WallpaperStyle.forestLight.rawValue, "Forest Light")
    }
}
