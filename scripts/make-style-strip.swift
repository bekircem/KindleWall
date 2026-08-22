#!/usr/bin/env swift
//
// Generates docs/screenshots/styles.png — the six-style gallery in the README.
//
//   swift scripts/make-style-strip.swift
//
// The README's strongest claim is "six styles that actually look different", and until this
// image existed the only evidence for it was a list of six adjectives. One picture settles it.
//
// Drawn, not screenshotted — the same rule scripts/make-social-card.swift follows. A screenshot
// of the app shows whichever library is on the machine that took it, and that library is
// somebody's real reading history. Every passage below comes from SampleData/My Clippings.txt,
// which is six public-domain books, so this file leaks nothing.
//
// The surfaces are the app's own numbers, copied from WallpaperGenerator.drawBackground and
// WallpaperStyle: same hex stops, same gradient direction, same radial centre and locations,
// same default font and decoration per style, same 0.17 padding ratio, same fit-the-type-to-
// the-passage sizing. If any of those change in the app, re-run this script.

import AppKit
import Foundation

// MARK: - The six styles, verbatim from the app

enum Surface {
    case solid(String)
    case linear([String])
    case radial([String])
}

enum Face { case serif, sans, classic, mono }
enum Decor { case quote, line, dots }

struct Style {
    let name: String
    let caption: String
    let surface: Surface
    let face: Face
    let decor: Decor
    let light: Bool
    let grain: Bool      // Paper's texture overlay
    let rules: Bool      // Grid's two hairlines
    let quote: String
    let credit: String
}

let styles: [Style] = [
    Style(name: "Night", caption: "Flat deep dark · serif",
          surface: .solid("141414"), face: .serif, decor: .quote,
          light: false, grain: false, rules: false,
          quote: "Man errs as long as he strives.", credit: "Faust"),

    Style(name: "Paper", caption: "Grainy cream · Palatino",
          surface: .solid("F4E8C1"), face: .classic, decor: .quote,
          light: true, grain: true, rules: false,
          quote: "The happiness of your life depends upon the quality of your thoughts.",
          credit: "Meditations"),

    Style(name: "Grid", caption: "Blue-black · monospace",
          surface: .solid("0D1117"), face: .mono, decor: .line,
          light: false, grain: false, rules: true,
          quote: "Taking a new step, uttering a new word, is what people fear most.",
          credit: "Crime and Punishment"),

    Style(name: "Dawn", caption: "Warm gradient · sans-serif",
          surface: .linear(["FF8A4C", "E0453A", "8A2F2A"]), face: .sans, decor: .dots,
          light: false, grain: false, rules: false,
          quote: "You have power over your mind — not outside events.",
          credit: "Meditations"),

    Style(name: "Depth", caption: "Indigo-violet gradient · sans-serif",
          surface: .linear(["667EEA", "764BA2", "1B1464"]), face: .sans, decor: .line,
          light: false, grain: false, rules: false,
          quote: "My life has been filled with terrible misfortune, most of which never happened.",
          credit: "Essays"),

    Style(name: "Forest Light", caption: "Radial shaft of light · serif",
          surface: .radial(["35662F", "17330F", "08150A"]), face: .serif, decor: .line,
          light: false, grain: false, rules: false,
          quote: "I went to the woods because I wished to live deliberately, to front only the essential facts of life.",
          credit: "Walden"),
]

// MARK: - Layout

let scale: CGFloat = 2
let margin: CGFloat = 26
let gapX: CGFloat = 16
let gapY: CGFloat = 24
let tileW: CGFloat = 336
let tileH: CGFloat = 210          // 16:10, the shape of a desktop
let captionH: CGFloat = 46
let cols = 3
let rows = 2

let width  = margin * 2 + tileW * CGFloat(cols) + gapX * CGFloat(cols - 1)
let height = margin * 2 + (tileH + captionH) * CGFloat(rows) + gapY * CGFloat(rows - 1)

// The page this sits on: docs/index.html's --void, --ink, --muted.
let void  = NSColor(srgbRed: 0.043, green: 0.043, blue: 0.047, alpha: 1)
let ink   = NSColor(srgbRed: 0.929, green: 0.918, blue: 0.890, alpha: 1)
let muted = NSColor(srgbRed: 0.608, green: 0.584, blue: 0.541, alpha: 1)

func hex(_ s: String) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: s).scanHexInt64(&v)
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                   green:   CGFloat((v >>  8) & 0xFF) / 255,
                   blue:    CGFloat( v        & 0xFF) / 255, alpha: 1)
}

func font(_ face: Face, _ size: CGFloat) -> NSFont {
    switch face {
    case .serif:
        let base = NSFont.systemFont(ofSize: size)
        guard let d = base.fontDescriptor.withDesign(.serif) else { return base }
        return NSFont(descriptor: d, size: size) ?? base
    case .sans:    return NSFont.systemFont(ofSize: size)
    case .classic: return NSFont(name: "Palatino-Roman", size: size)
                       ?? NSFont(name: "Palatino", size: size)
                       ?? NSFont.systemFont(ofSize: size)
    case .mono:    return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

/// `lineSpacing`, not `lineHeightMultiple`: `boundingRect` measures the first and ignores the
/// second, and a measurement that disagrees with the drawing puts the credit line on top of the
/// passage's last line — which is exactly what the first draft of this script did.
func paragraph(_ alignment: NSTextAlignment, spacing: CGFloat = 0) -> NSParagraphStyle {
    let p = NSMutableParagraphStyle()
    p.alignment = alignment
    p.lineSpacing = spacing
    return p
}

// MARK: - Canvas

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else {
    FileHandle.standardError.write(Data("could not allocate the canvas\n".utf8))
    exit(1)
}
rep.size = NSSize(width: width, height: height)

guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
    FileHandle.standardError.write(Data("could not open a drawing context\n".utf8))
    exit(1)
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
let cg = ctx.cgContext

void.setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

// MARK: - One tile

/// The app sizes type to the passage rather than clipping it to a fixed box. This is the same
/// idea at tile scale: walk down from the largest size that still fits the text column.
func fittedFont(_ text: String, face: Face, width w: CGFloat, height h: CGFloat,
                from maxSize: CGFloat, to minSize: CGFloat) -> CGFloat {
    var size = maxSize
    while size > minSize {
        let f = font(face, size)
        let attrs: [NSAttributedString.Key: Any] = [.font: f, .paragraphStyle: paragraph(.center, spacing: size * 0.22)]
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: w, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
        if bounds.height <= h { return size }
        size -= 0.5
    }
    return minSize
}

/// Deterministic, so re-running the script produces a byte-identical grain.
struct SeededRNG {
    var state: UInt64
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
}

func drawTile(_ style: Style, in rect: NSRect) {
    cg.saveGState()
    let clip = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
    clip.addClip()

    // --- surface: the app's own stops, direction and locations ------------------
    switch style.surface {
    case .solid(let h):
        hex(h).setFill()
        rect.fill()

    case .linear(let hs):
        let colors = hs.map { hex($0).cgColor } as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) {
            // WallpaperGenerator draws top-left to bottom-right.
            cg.drawLinearGradient(g,
                start: CGPoint(x: rect.minX, y: rect.maxY),
                end:   CGPoint(x: rect.maxX, y: rect.minY), options: [])
        }

    case .radial(let hs):
        let colors = hs.map { hex($0).cgColor } as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.52, 1]) {
            let centre = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.60)
            cg.drawRadialGradient(g, startCenter: centre, startRadius: 0,
                                  endCenter: centre, endRadius: rect.width * 0.75,
                                  options: [.drawsAfterEndLocation])
        }
    }

    // Paper's grain. Same 4pt pitch and 0.03 alpha as drawPaperTextureOverlay.
    if style.grain {
        NSColor(white: 0.5, alpha: 0.03).setFill()
        var rng = SeededRNG(state: 0x9E3779B97F4A7C15)
        let step: CGFloat = 4
        var cells: [NSRect] = []
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX
            while x < rect.maxX {
                if rng.next() % 3 == 0 { cells.append(NSRect(x: x, y: y, width: step, height: step)) }
                x += step
            }
            y += step
        }
        cells.forEach { $0.fill() }
    }

    // Grid's two hairlines, at 0.3 and 0.7 of the height, inset by the padding ratio.
    if style.rules {
        let pad = rect.width * 0.17
        NSColor(white: 1.0, alpha: 0.05).setStroke()
        for fraction in [0.3, 0.7] as [CGFloat] {
            let line = NSBezierPath()
            line.lineWidth = 1
            line.move(to: CGPoint(x: rect.minX + pad, y: rect.minY + rect.height * fraction))
            line.line(to: CGPoint(x: rect.maxX - pad, y: rect.minY + rect.height * fraction))
            line.stroke()
        }
    }

    // --- content ----------------------------------------------------------------
    let textInk: NSColor = style.light ? hex("3B2F1E") : .white
    let creditInk: NSColor = style.light
        ? hex("3B2F1E").withAlphaComponent(0.55)
        : NSColor(white: 1.0, alpha: 0.55)

    let pad = rect.width * 0.17
    let column = rect.width - pad * 2

    let quoteSize = fittedFont(style.quote, face: style.face,
                               width: column, height: rect.height * 0.46, from: 17, to: 7)
    let quoteAttrs: [NSAttributedString.Key: Any] = [
        .font: font(style.face, quoteSize),
        .foregroundColor: textInk,
        .paragraphStyle: paragraph(.center, spacing: quoteSize * 0.22),
    ]
    let quoteH = ceil((style.quote as NSString).boundingRect(
        with: NSSize(width: column, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: quoteAttrs).height)

    let creditAttrs: [NSAttributedString.Key: Any] = [
        .font: font(style.face, 8),
        .foregroundColor: creditInk,
        .paragraphStyle: paragraph(.center),
    ]
    let creditH = ceil((style.credit as NSString).boundingRect(
        with: NSSize(width: column, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: creditAttrs).height)

    // Decoration, passage and credit are one optical block, centred in the tile — the same
    // stack the app lays out on a real desktop.
    let decorH: CGFloat = 20
    let decorGap: CGFloat = 12
    let creditGap: CGFloat = 10
    let blockH = decorH + decorGap + quoteH + creditGap + creditH
    let blockTop = rect.minY + (rect.height + blockH) / 2

    let quoteTop = blockTop - decorH - decorGap
    (style.quote as NSString).draw(
        with: NSRect(x: rect.minX + pad, y: quoteTop - quoteH, width: column, height: quoteH),
        options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: quoteAttrs)

    (style.credit as NSString).draw(
        with: NSRect(x: rect.minX + pad, y: quoteTop - quoteH - creditGap - creditH,
                     width: column, height: creditH),
        options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: creditAttrs)

    // --- the style's own decoration, above the passage ---------------------------
    let cx = rect.midX
    let decorTopY = blockTop
    switch style.decor {
    case .quote:
        let mark = NSAttributedString(string: "\u{201C}", attributes: [
            .font: font(style.face, decorH * 2),
            .foregroundColor: style.light ? NSColor(white: 0, alpha: 0.20) : NSColor(white: 1, alpha: 0.30),
        ])
        let s = mark.size()
        mark.draw(at: CGPoint(x: cx - s.width / 2, y: decorTopY - s.height))

    case .line:
        (style.light ? NSColor(white: 0, alpha: 0.30) : NSColor(white: 1, alpha: 0.40)).setStroke()
        let rule = NSBezierPath()
        rule.lineWidth = max(1, decorH * 0.05)
        rule.lineCapStyle = .round
        rule.move(to: CGPoint(x: cx - decorH * 1.25, y: decorTopY - decorH / 2))
        rule.line(to: CGPoint(x: cx + decorH * 1.25, y: decorTopY - decorH / 2))
        rule.stroke()

    case .dots:
        // Two thin bars, each hanging under a dot — WallpaperGenerator.drawQuoteIcon, same ratios.
        (style.light ? NSColor(white: 0, alpha: 0.15) : NSColor(white: 1, alpha: 0.25)).setFill()
        let barW = decorH * 0.08, barHt = decorH * 0.45
        let dotR = decorH * 0.07, pairGap = decorH * 0.22
        for originX in [cx - pairGap / 2 - barW, cx + pairGap / 2] {
            NSBezierPath(ovalIn: NSRect(x: originX - dotR + barW / 2, y: decorTopY - dotR * 2,
                                        width: dotR * 2, height: dotR * 2)).fill()
            NSRect(x: originX, y: decorTopY - dotR * 2 - barHt - 2, width: barW, height: barHt).fill()
        }
    }

    cg.restoreGState()

    // A hairline so a dark tile still has an edge against the dark page.
    NSColor(white: 1, alpha: 0.10).setStroke()
    let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
    border.lineWidth = 1
    border.stroke()
}

// MARK: - Grid

for (index, style) in styles.enumerated() {
    let col = index % cols
    let row = index / cols

    let x = margin + CGFloat(col) * (tileW + gapX)
    let yTop = height - margin - CGFloat(row) * (tileH + captionH + gapY)
    let tile = NSRect(x: x, y: yTop - tileH, width: tileW, height: tileH)

    drawTile(style, in: tile)

    let nameFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    (style.name as NSString).draw(
        with: NSRect(x: x, y: tile.minY - 22, width: tileW, height: 18),
        options: [.usesLineFragmentOrigin],
        attributes: [.font: nameFont, .foregroundColor: ink, .paragraphStyle: paragraph(.left)])

    (style.caption as NSString).draw(
        with: NSRect(x: x, y: tile.minY - 38, width: tileW, height: 16),
        options: [.usesLineFragmentOrigin],
        attributes: [.font: NSFont.systemFont(ofSize: 11),
                     .foregroundColor: muted, .paragraphStyle: paragraph(.left)])
}

NSGraphicsContext.restoreGraphicsState()

// MARK: - Write

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("could not encode the strip\n".utf8))
    exit(1)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let out = root.appendingPathComponent("docs/screenshots/styles.png")
try png.write(to: out)
print("wrote \(out.path) — \(rep.pixelsWide)×\(rep.pixelsHigh), \(png.count) bytes")
