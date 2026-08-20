import XCTest
@testable import KindleWall

/// Guards the design inspector's tab titles against the leak that put them on screen in
/// English inside a Turkish window.
///
/// `DesignTab.title` is `String`-typed, and a bare `String` literal never reaches the String
/// Catalog: the extractor only sees `LocalizedStringKey` and `String(localized:)`. The catalog
/// therefore reported "0 keys without a Turkish value" while three visible labels had no
/// Turkish at all. Asserting through the built Turkish bundle is what makes this real — a test
/// that only checked the key spelling would pass on the broken version too.
final class DesignTabLocalizationTests: XCTestCase {

    private func turkishBundle() throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "tr", ofType: "lproj"),
                                 "no tr.lproj in the bundle")
        return try XCTUnwrap(Bundle(path: path))
    }

    /// The English key each case is written against. Hard-coded rather than read from
    /// `title`, which returns the *translated* string at runtime and so cannot serve as its
    /// own lookup key.
    private static let englishKey: [DesignTab: String] = [
        .style: "Style",
        .typography: "Typography",
        .background: "Background",
    ]

    /// Catalog side: the Turkish values exist and reached the built bundle. Locale-independent.
    func test_everyTabTitle_hasATurkishTranslation() throws {
        let bundle = try turkishBundle()
        let expected: [DesignTab: String] = [
            .style: "Stil",
            .typography: "Tipografi",
            .background: "Arka Plan",
        ]

        for tab in DesignTab.allCases {
            let key = try XCTUnwrap(Self.englishKey[tab])
            XCTAssertEqual(bundle.localizedString(forKey: key, value: nil, table: nil), expected[tab],
                           "\(tab.rawValue): the catalog's Turkish value did not reach the bundle")
        }
    }

    /// Routing side: `title` resolves through the bundle rather than returning a constant.
    ///
    /// On a Turkish-locale host a bare literal fails this outright. On an English host both
    /// sides read "Style" and it cannot discriminate — which is why the catalog assertion
    /// above exists as well, and why the leak survived a catalog audit in the first place.
    func test_title_resolvesThroughTheBundleRatherThanReturningTheKey() throws {
        for tab in DesignTab.allCases {
            let key = try XCTUnwrap(Self.englishKey[tab])
            XCTAssertEqual(tab.title, Bundle.main.localizedString(forKey: key, value: nil, table: nil),
                           "\(tab.rawValue): title does not go through the String Catalog")
        }
    }

    /// The raw values back `Constants.StorageKeys.designInspectorTab` in UserDefaults, so
    /// translating one would drop everyone back to the default tab.
    func test_rawValues_areStorageKeysAndDoNotChange() {
        XCTAssertEqual(DesignTab.style.rawValue, "style")
        XCTAssertEqual(DesignTab.typography.rawValue, "typography")
        XCTAssertEqual(DesignTab.background.rawValue, "background")
    }

    /// Every case must be reachable from the segmented picker.
    func test_allCases_coversTheThreeSections() {
        XCTAssertEqual(Set(DesignTab.allCases.map(\.rawValue)), ["style", "typography", "background"])
    }
}
