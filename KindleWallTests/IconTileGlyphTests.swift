import XCTest
import SwiftUI
import AppKit
@testable import KindleWall

/// Pins `IconTile`'s glyph-contrast rule.
///
/// The glyph color used to be hardcoded white, which failed on the warm tiles. The
/// replacement decides by measured contrast, and nothing about that decision is visible in a
/// screenshot — a tile with an illegible glyph looks like a tile. These tests are the only
/// thing standing between that rule and a silent regression.
///
/// `@MainActor` because `IconTile.glyph(on:)` and `nonTextContrastFloor` are — reaching them
/// from a nonisolated test body is exactly the kind of hole the Swift 6 mode exists to close.
@MainActor
final class IconTileGlyphTests: XCTestCase {

    /// Every fill the app actually puts under a glyph today.
    private var fills: [(name: String, color: Color)] {
        [
            ("accent",     Theme.Palette.accent),
            ("indigo",      .indigo),
            ("blue",        .blue),
            ("neutralTile", Theme.Palette.neutralTile),
            ("orange",     .orange),
            ("pink",       .pink),
            ("indigo",     .indigo),
            ("purple",     .purple),
            ("green",      .green),
        ]
    }

    /// Convention holds wherever it can: a fill that white reads fine on keeps its white glyph.
    ///
    /// This is the half of the contract that stops the rule from "improving" the cool tiles
    /// into something no other Mac app does.
    func test_glyph_staysWhiteWhereverWhiteIsLegible() {
        for (name, fill) in fills where contrast(.white, on: fill) >= IconTile.nonTextContrastFloor {
            XCTAssertTrue(
                isEffectivelyWhite(IconTile.glyph(on: fill)),
                "\(name): beyaz \(contrast(.white, on: fill)):1 ile eşiği geçiyor, beyaz kalmalıydı"
            )
        }
    }

    /// And it gives way exactly where it must.
    func test_glyph_flipsToDarkOnlyWhereWhiteFails() {
        for (name, fill) in fills where contrast(.white, on: fill) < IconTile.nonTextContrastFloor {
            XCTAssertFalse(
                isEffectivelyWhite(IconTile.glyph(on: fill)),
                "\(name): beyaz \(contrast(.white, on: fill)):1 — koyu glife düşmeliydi"
            )
        }
    }

    /// The specific failure that prompted the change: white over the warm accent.
    func test_glyph_onWarmAccent_isNotWhite() {
        let chosen = IconTile.glyph(on: Theme.Palette.accent)
        XCTAssertFalse(
            isEffectivelyWhite(chosen),
            "Amber aksan üzerinde beyaz glif 1.9:1 — 3:1 eşiğinin altında"
        )
    }

    /// The sidebar palette, named. Every section but the branded one keeps its white glyph;
    /// the accent tile is the single deliberate reversal, not an accident of some color drifting
    /// past a threshold.
    func test_sidebarPalette_onlyTheAccentSectionReversesItsGlyph() {
        for section in [SidebarSection.content, .behavior, .app] {
            XCTAssertTrue(
                isEffectivelyWhite(IconTile.glyph(on: section.tint)),
                "\(section.rawValue) karosu beyaz glif kullanmalı — \(contrast(.white, on: section.tint)):1"
            )
        }
        XCTAssertFalse(
            isEffectivelyWhite(IconTile.glyph(on: SidebarSection.wallpaper.tint)),
            "Duvar Kağıdı karosu amber; beyaz glif eşiği geçmiyor"
        )
    }

    /// Whatever it picks, the result must clear the 3:1 floor WCAG sets for non-text marks.
    func test_glyph_clearsNonTextContrastFloor() {
        for (name, fill) in fills {
            let ratio = contrast(IconTile.glyph(on: fill), on: fill)
            XCTAssertGreaterThanOrEqual(ratio, 3.0, "\(name): \(ratio):1 — 3:1 altında")
        }
    }

    // MARK: - Helpers (independent of the implementation under test)

    private func isEffectivelyWhite(_ color: Color) -> Bool {
        luminance(color) > 0.9
    }

    private func luminance(_ color: Color) -> CGFloat {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return 0 }
        func lin(_ v: CGFloat) -> CGFloat {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(c.redComponent)
             + 0.7152 * lin(c.greenComponent)
             + 0.0722 * lin(c.blueComponent)
    }

    private func contrast(_ glyph: Color, on fill: Color) -> CGFloat {
        let a = luminance(glyph), b = luminance(fill)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
