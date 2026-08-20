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

    /// Turkish capitalises "i" as "İ", so uppercasing "Stili" with the wrong locale yields
    /// "STILI". The helper used to pin tr_TR — right while the app was Turkish-only, wrong the
    /// moment it also shipped in English.
    func test_uppercasing_followsTheLocale() {
        XCTAssertEqual("Stili".uppercased(with: Locale(identifier: "tr_TR")), "STİLİ")
        XCTAssertEqual("Stili".uppercased(with: Locale(identifier: "en_US")), "STILI")
    }

    func test_uppercasedForCurrentLocale_usesTheCurrentLocale() {
        XCTAssertEqual("Stili".uppercasedForCurrentLocale, "Stili".uppercased(with: Locale.current))
    }

    /// The catalog is the complete inventory of what is localizable, so a key with no Turkish
    /// value is a string that would ship reading English inside a Turkish build.
    func test_everyKey_hasATurkishValue() throws {
        let (strings, _) = try loadCatalog()
        var missing: [String] = []
        for (key, value) in strings {
            guard let entry = value as? [String: Any] else { continue }
            if (entry["shouldTranslate"] as? Bool) == false { continue }
            let turkish = (entry["localizations"] as? [String: Any])?["tr"] as? [String: Any]
            let unit = (turkish?["stringUnit"] as? [String: Any])?["value"] as? String
            let hasVariations = turkish?["variations"] != nil
            if (unit?.isEmpty ?? true) && !hasVariations { missing.append(key) }
        }
        XCTAssertTrue(missing.isEmpty, "no Turkish value for: \(missing.sorted().prefix(10))")
    }

    /// The source language is English now. A key that still reads Turkish is a literal somebody
    /// forgot to translate — and grep cannot find those that carry no Turkish letters, which is
    /// why this looks at the catalog rather than the source.
    func test_noSourceKey_containsTurkishLetters() throws {
        let (strings, _) = try loadCatalog()
        let turkish = CharacterSet(charactersIn: "çğıöşüÇĞİÖŞÜ")
        let offenders = strings.keys.filter { $0.rangeOfCharacter(from: turkish) != nil }
        XCTAssertTrue(offenders.isEmpty, "still Turkish source keys: \(offenders.sorted().prefix(10))")
    }

    /// English needs "1 quote" but "5 quotes"; Turkish needs neither, which is why the code
    /// carried no plural rule at all. A missing variation renders the `other` form for every
    /// count — "1 quotes" — which reads as a bug to every English speaker.
    func test_plurals_haveBothFormsInBothLanguages() throws {
        let (strings, _) = try loadCatalog()
        let pluralKeys = strings.filter { _, value in
            guard let entry = value as? [String: Any],
                  let locs = entry["localizations"] as? [String: Any] else { return false }
            return locs.values.contains { ($0 as? [String: Any])?["variations"] != nil }
        }
        XCTAssertGreaterThanOrEqual(pluralKeys.count, 6, "expected at least 6 pluralized keys")
        for (key, value) in pluralKeys {
            let locs = (value as! [String: Any])["localizations"] as! [String: Any]
            for language in ["en", "tr"] {
                let plural = ((locs[language] as? [String: Any])?["variations"] as? [String: Any])?["plural"] as? [String: Any]
                XCTAssertNotNil(plural?["one"], "\(key): \(language) has no 'one' form")
                XCTAssertNotNil(plural?["other"], "\(key): \(language) has no 'other' form")
            }
        }
    }

    /// The catalog is a source file, not a bundle resource, so it is found by walking up from
    /// this test file to the repository root.
    private func loadCatalog() throws -> ([String: Any], [String: Any]) {
        var directory = URL(fileURLWithPath: #filePath)
        directory.deleteLastPathComponent()          // KindleWallTests
        directory.deleteLastPathComponent()          // repository root
        let url = directory.appendingPathComponent("KindleWall/Resources/Localizable.xcstrings")
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        return (try XCTUnwrap(root["strings"] as? [String: Any]), root)
    }
}
