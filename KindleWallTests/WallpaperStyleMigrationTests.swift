import XCTest
@testable import KindleWall

/// The style set shrank from eight to six. Anything a previous build persisted — in
/// UserDefaults or in a CloudKit record written by a device still running the old build —
/// must still resolve, or users silently lose their selection.
final class WallpaperStyleMigrationTests: XCTestCase {

    func test_everyRetiredStyleNameMapsToItsSuccessor() {
        let expected: [String: WallpaperStyle] = [
            "Minimal Dark":  .night,
            "Elegant Serif": .night,
            "Minimal Light": .paper,
            "Paper Texture": .paper,
            "Modern Sans":   .grid,
            "Gradient Warm": .dawn,
            "Gradient Cool": .depth,
            "Nature Blur":   .forestLight
        ]

        for (legacy, want) in expected {
            XCTAssertEqual(WallpaperStyle(persistedRawValue: legacy), want,
                           "\"\(legacy)\" yanlış stile göç etti")
        }
    }

    func test_currentStyleNamesRoundTrip() {
        for style in WallpaperStyle.allCases {
            XCTAssertEqual(WallpaperStyle(persistedRawValue: style.rawValue), style)
        }
    }

    func test_unknownNameIsRejectedRatherThanGuessed() {
        XCTAssertNil(WallpaperStyle(persistedRawValue: "Vaporwave"))
        XCTAssertNil(WallpaperStyle(persistedRawValue: ""))
    }

    /// Nature Blur was green. Depth is indigo — migrating there would have thrown away the
    /// one thing those users chose. Forest Light keeps the green.
    func test_natureBlurKeepsItsGreenIdentity() {
        XCTAssertEqual(WallpaperStyle(persistedRawValue: "Nature Blur"), .forestLight)
    }

    func test_eachStyleCarriesItsOwnTypographicCharacter() {
        // The consolidation's whole point: picking a style must be a visible change, so no
        // two styles may share both a font and a decoration.
        let signatures = WallpaperStyle.allCases.map { "\($0.defaultFontFamily)|\($0.defaultDecoration)" }
        XCTAssertEqual(Set(signatures).count, WallpaperStyle.allCases.count,
                       "iki stil aynı font+dekorasyon imzasını paylaşıyor")
    }

    func test_onlyPaperHasALightBackground() {
        XCTAssertEqual(WallpaperStyle.allCases.filter(\.hasLightBackground), [.paper])
    }
}
