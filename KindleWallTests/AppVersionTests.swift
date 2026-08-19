import XCTest
@testable import KindleWall

/// The version used to live in two places — a literal in `Constants` and a value in
/// `Info.plist` — and they drifted: the About page said 1.1.0 while the shipped binary was
/// stamped 1.0. These pin the bundle as the single source and keep `release.sh`'s writes
/// well-formed. The build-number check is not pedantry: Sparkle orders releases by
/// `CFBundleVersion`, so a non-integer there stops updates without printing a word.
final class AppVersionTests: XCTestCase {

    /// The one that actually catches the drift. It reads `Info.plist` off disk rather than
    /// through `Bundle.main`'s cached dictionary, so it compares the constant against the file
    /// the build stamped — not against the same lookup the constant itself performs.
    func test_version_agreesWithTheInfoPlistOnDisk() throws {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: url)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let stamped = try XCTUnwrap(plist["CFBundleShortVersionString"] as? String)
        XCTAssertEqual(Constants.App.version, stamped,
                       "Constants says '\(Constants.App.version)', the bundle is stamped '\(stamped)'")
    }

    func test_version_isReadFromTheBundleNotTheFallback() {
        XCTAssertNotEqual(Constants.App.version, "0.0.0",
                          "CFBundleShortVersionString missing from Info.plist — the fallback was hit")
    }

    func test_version_isSemantic() {
        XCTAssertNotNil(
            Constants.App.version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression),
            "'\(Constants.App.version)' is not MAJOR.MINOR.PATCH — release.sh wrote something malformed"
        )
    }

    func test_buildNumber_isAPositiveInteger() throws {
        let raw = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            "CFBundleVersion missing"
        )
        let value = try XCTUnwrap(Int(raw), "CFBundleVersion '\(raw)' is not an integer — Sparkle cannot order it")
        XCTAssertGreaterThan(value, 0)
    }

    func test_bundleIdentifier_matchesTheConstant() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, Constants.App.bundleIdentifier)
    }
}
