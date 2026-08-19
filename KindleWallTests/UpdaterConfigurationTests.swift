import XCTest
@testable import KindleWall

/// Sparkle fails quietly when it is misconfigured, and every failure mode looks like "no
/// updates available" from the outside: a missing `SUPublicEDKey` makes it reject every update
/// as unsigned, and a feed URL that drifts from the one `release.sh` writes points the app at
/// an address no appcast is ever published to. Nobody notices until a user is stranded on an
/// old build, so the configuration is pinned here.
final class UpdaterConfigurationTests: XCTestCase {

    func test_feedURL_isInTheBundleAndMatchesTheConstant() {
        let fromBundle = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        XCTAssertEqual(fromBundle, Constants.Updates.feedURL)
    }

    func test_feedURL_isHTTPS() throws {
        let url = try XCTUnwrap(URL(string: Constants.Updates.feedURL))
        XCTAssertEqual(url.scheme, "https", "Sparkle refuses a plain-HTTP feed")
    }

    func test_publicKey_isPresent() throws {
        let key = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            "SUPublicEDKey missing — every update would be rejected as unsigned"
        )
        // A base64 Ed25519 public key is 32 bytes, which encodes to 44 characters.
        XCTAssertEqual(key.count, 44, "'\(key)' is not a 32-byte base64 Ed25519 key")
        XCTAssertNotNil(Data(base64Encoded: key), "SUPublicEDKey is not valid base64")
    }

    @MainActor
    func test_updater_startsAndCanCheck() {
        XCTAssertTrue(UpdaterManager.shared.canCheckForUpdates,
                      "the updater did not start — Sparkle could not read its configuration")
    }
}
