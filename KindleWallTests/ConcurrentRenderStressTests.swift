import XCTest
@testable import KindleWall

/// Reproduction harness for the EXC_BAD_ACCESS seen while the app was running.
///
/// `generatePreview()` and `applyWallpaper()` each spawn their own `Task.detached` and both call
/// into `WallpaperGenerator`; `selectAndApply` fires them back to back. This test drives the
/// same shape deliberately — many renders at once, off the main thread — to see whether the
/// renderer survives concurrent use.
final class ConcurrentRenderStressTests: XCTestCase {

    private let generator = WallpaperGenerator()

    private func clipping(_ index: Int) -> Clipping {
        Clipping(
            bookTitle: "Kitap \(index)",
            author: "Yazar \(index)",
            text: "İnsan ancak sevdiği şeyi korur, ancak anladığı şeyi sever. Deneme \(index)."
        )
    }

    /// Hammers the renderer from many background threads at once.
    /// If AppKit's shared text machinery is the problem, this is where it shows.
    func test_concurrentRendersDoNotCrash() {
        let iterations = 40
        let done = expectation(description: "renders finished")
        done.expectedFulfillmentCount = iterations

        let styles = WallpaperStyle.allCases

        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            let style = styles[index % styles.count]
            let image = generator.generateWallpaper(
                clipping: clipping(index),
                style: style,
                screenSize: CGSize(width: 800, height: 500),
                typography: .default,
                longQuote: .default
            )
            XCTAssertNotNil(image, "render \(index) başarısız")
            done.fulfill()
        }

        wait(for: [done], timeout: 120)
    }

    /// The exact overlap `selectAndApply` creates: a preview render and a full render running
    /// at the same time, repeatedly.
    func test_previewAndApplyRendersOverlapping() {
        let rounds = 15
        let done = expectation(description: "overlapping renders finished")
        done.expectedFulfillmentCount = rounds * 2

        for round in 0..<rounds {
            DispatchQueue.global().async {
                _ = self.generator.generateWallpaper(
                    clipping: self.clipping(round), style: .paper,
                    screenSize: CGSize(width: 600, height: 375),
                    typography: .default, longQuote: .default)
                done.fulfill()
            }
            DispatchQueue.global().async {
                _ = self.generator.generateWallpaper(
                    clipping: self.clipping(round), style: .paper,
                    screenSize: CGSize(width: 1600, height: 1000),
                    typography: .default, longQuote: .default)
                done.fulfill()
            }
        }

        wait(for: [done], timeout: 120)
    }

    /// Isolates the shared AppKit singleton the renderer touches per draw.
    /// `NSFontManager` is documented as main-thread-bound; this proves whether it tolerates
    /// the concurrent use the render path subjects it to.
    func test_sharedFontManagerUnderConcurrentUse() {
        let done = expectation(description: "font conversions finished")
        done.expectedFulfillmentCount = 200

        DispatchQueue.concurrentPerform(iterations: 200) { index in
            let base = NSFont.systemFont(ofSize: CGFloat(12 + index % 40), weight: .light)
            let italic = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
            XCTAssertGreaterThan(italic.pointSize, 0)
            done.fulfill()
        }

        wait(for: [done], timeout: 120)
    }
}
