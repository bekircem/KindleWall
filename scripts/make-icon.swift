#!/usr/bin/env swift
//
// Generates AppIcon.appiconset from code.
//
//   swift scripts/make-icon.swift
//
// The icon is generated rather than drawn by hand so it stays tied to the app's own identity:
// the amber from Assets/AccentColor, the dark label Theme.Palette.onAccent prescribes for text
// on that amber, and the `text.quote` mark the About page already uses.
//
// macOS does not mask AppIcon PNGs — the rounded shape is the developer's job — and the shape
// is a superellipse, not a circular rounded rect. Next to system icons the difference is
// visible: circular corners read as slightly pinched. Apple's grid puts an 824pt body inside a
// 1024pt canvas, and the margin is what the drop shadow lives in.

import AppKit
import CoreGraphics
import Foundation

// MARK: - Palette (mirrors Assets/AccentColor.colorset, dark variant — the app is dark-first)

let accentTop = NSColor(srgbRed: 0.949, green: 0.741, blue: 0.384, alpha: 1)
let accentBottom = NSColor(srgbRed: 0.839, green: 0.518, blue: 0.176, alpha: 1)
/// Theme.Palette.onAccent. White over this amber measures 1.9:1; black measures 11:1.
let glyphColor = NSColor(white: 0.05, alpha: 0.90)

let canvas: CGFloat = 1024
let bodyInset: CGFloat = 100        // 1024 − 2×100 = 824pt body
let superellipseExponent: CGFloat = 5.0

// MARK: - Shape

/// A superellipse: |x/a|ⁿ + |y/b|ⁿ = 1, sampled parametrically.
///
/// n = 5 sits where Apple's continuous corner does for a square of this proportion. Lower and
/// the corners round too far toward a circle; higher and the shape squares off.
func superellipsePath(in rect: CGRect, exponent n: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 1024
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / n)
        let y = cy + b * (st < 0 ? -1 : 1) * pow(abs(st), 2 / n)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

/// Tints a template symbol. Drawing the symbol and then filling `.sourceAtop` is the reliable
/// AppKit way — `withSymbolConfiguration` alone does not carry a color.
func tinted(_ symbol: NSImage, _ color: NSColor, size: CGSize) -> NSImage {
    NSImage(size: size, flipped: false) { rect in
        symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        color.set()
        rect.fill(using: .sourceAtop)
        return true
    }
}

// MARK: - Render

func renderIcon(pixels: Int) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("could not allocate a \(pixels)px bitmap") }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let gc = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("no graphics context") }
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext

    let scale = CGFloat(pixels) / canvas
    let side = (canvas - 2 * bodyInset) * scale
    let body = CGRect(x: bodyInset * scale, y: bodyInset * scale, width: side, height: side)
    let shape = superellipsePath(in: body, exponent: superellipseExponent)

    // Body and its shadow, composited as one.
    //
    // The obvious version — fill the shape black to cast the shadow, then paint the gradient
    // over it — leaves the black fill's antialiased edge peeking out from under the amber as a
    // grey halo. Invisible at 512px, the dominant feature at 16px. A transparency layer casts
    // the shadow from the finished body instead, so there is no stand-in to leak.
    //
    // Below 64px the blur is under a pixel and adds nothing but dirt, so it is skipped.
    ctx.saveGState()
    if pixels >= 64 {
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * scale),
                      blur: 22 * scale,
                      color: NSColor(white: 0, alpha: 0.28).cgColor)
    }
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.addPath(shape)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [accentTop.cgColor, accentBottom.cgColor] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: body.midX, y: body.maxY),
                           end: CGPoint(x: body.midX, y: body.minY),
                           options: [])
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // The app's own mark — simplified below 128px.
    //
    // `text.quote` is the app's glyph and it is what the About page shows, but it is a quote
    // mark *plus three rules*: at 32px the rules merge into a smear and at 16px the whole
    // thing is a grey blob. Small sizes therefore drop to the quote mark alone, drawn larger.
    // Apple's own icon sets simplify the same way; a silhouette that reads beats a faithful
    // one that does not.
    let detailed = pixels >= 128
    let symbolName = detailed ? "text.quote" : "quote.opening"
    let target = side * (detailed ? 0.50 : 0.62)
    let config = NSImage.SymbolConfiguration(pointSize: target, weight: detailed ? .semibold : .bold)
    if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let natural = symbol.size
        let fitted = CGSize(width: target, height: target * (natural.height / max(natural.width, 1)))
        let mark = tinted(symbol, glyphColor, size: fitted)
        mark.draw(in: NSRect(x: body.midX - fitted.width / 2,
                             y: body.midY - fitted.height / 2,
                             width: fitted.width, height: fitted.height),
                  from: .zero, operation: .sourceOver, fraction: 1)
    } else {
        fatalError("SF Symbol \(symbolName) unavailable")
    }

    return rep
}

// MARK: - Write the appiconset

// mac idiom: 16/32/128/256/512 at 1× and 2×.
let slots: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1),
    (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("KindleWall/Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

var manifest: [[String: String]] = []
for slot in slots {
    let pixels = slot.points * slot.scale
    let name = "icon_\(slot.points)x\(slot.points)\(slot.scale == 2 ? "@2x" : "").png"
    guard let data = renderIcon(pixels: pixels).representation(using: .png, properties: [:]) else {
        fatalError("PNG encode failed for \(name)")
    }
    try data.write(to: outDir.appendingPathComponent(name))
    manifest.append([
        "idiom": "mac",
        "size": "\(slot.points)x\(slot.points)",
        "scale": "\(slot.scale)x",
        "filename": name,
    ])
    print("wrote \(name) — \(pixels)px, \(data.count / 1024) KB")
}

let contents: [String: Any] = ["images": manifest, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: outDir.appendingPathComponent("Contents.json"))
print("wrote Contents.json — \(manifest.count) entries")
