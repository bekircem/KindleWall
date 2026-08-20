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
}
