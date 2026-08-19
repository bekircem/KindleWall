import XCTest
import AppKit
@testable import KindleWall

/// The appiconset shipped with nothing but a `Contents.json` for months, so the app wore the
/// generic document icon in the Dock, in Finder and in the App Switcher. A missing icon leaves
/// no trace in a build log — the asset catalog compiles happily around it — so it is pinned
/// here instead, where it fails loudly.
final class AppIconTests: XCTestCase {

    func test_appIcon_isInTheBundle() {
        XCTAssertNotNil(NSImage(named: "AppIcon"),
                        "AppIcon did not compile into the bundle — run `swift scripts/make-icon.swift`")
    }

    func test_appIcon_carriesAHighResolutionRepresentation() throws {
        let icon = try XCTUnwrap(NSImage(named: "AppIcon"))
        let widest = icon.representations.map(\.pixelsWide).max() ?? 0
        XCTAssertGreaterThanOrEqual(widest, 512,
                                    "largest representation is \(widest)px; Finder's icon view wants 1024")
    }

    func test_appIcon_isSquare() throws {
        let icon = try XCTUnwrap(NSImage(named: "AppIcon"))
        let widest = try XCTUnwrap(icon.representations.max(by: { $0.pixelsWide < $1.pixelsWide }))
        XCTAssertEqual(widest.pixelsWide, widest.pixelsHigh)
    }

    /// A blank canvas would satisfy every check above. This one looks at the middle of the
    /// icon and insists something was actually drawn there.
    func test_appIcon_isNotBlank() throws {
        let icon = try XCTUnwrap(NSImage(named: "AppIcon"))
        // A compiled asset catalog hands back reps that are not `NSBitmapImageRep`, so go
        // through a CGImage rather than casting.
        let cg = try XCTUnwrap(icon.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let rep = NSBitmapImageRep(cgImage: cg)
        let centre = try XCTUnwrap(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2))
        XCTAssertGreaterThan(centre.alphaComponent, 0.5, "the middle of the icon is transparent")
    }
}
