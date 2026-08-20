#!/usr/bin/env swift
//
// Generates docs/social-card.png — the repository's social preview.
//
//   swift scripts/make-social-card.swift
//
// GitHub renders this image whenever the repo is linked anywhere: X, Reddit, Slack, Discord.
// Without it the link shows GitHub's generated grey card, which for an app whose whole point
// is how it looks on a desktop is the worst possible first impression.
//
// Drawn rather than screenshotted on purpose. A screenshot of this app shows whichever
// library is on the machine that took it, and that library is somebody's actual reading
// history. This card carries a public-domain line instead and leaks nothing.
//
// 1280×640 is GitHub's stated size. It crops to a narrower strip in some clients, so
// everything that matters stays inside a generous vertical band.

import AppKit
import Foundation

// MARK: - Palette (the Night wallpaper style, and Assets/AccentColor's dark variant)

let background = NSColor(srgbRed: 0.078, green: 0.078, blue: 0.078, alpha: 1)   // #141414
let amber = NSColor(srgbRed: 0.949, green: 0.741, blue: 0.384, alpha: 1)
let quoteInk = NSColor(white: 0.93, alpha: 1)
let attributionInk = NSColor(white: 0.62, alpha: 1)
let footerInk = NSColor(white: 0.45, alpha: 1)

let width: CGFloat = 1280, height: CGFloat = 640

/// Public domain, and it says what the app is for.
let quote = "A room without books is like a body without a soul."
let attribution = "Cicero"

// MARK: - Drawing

func centered(_ text: String, font: NSFont, color: NSColor, width maxWidth: CGFloat) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineHeightMultiple = 1.18
    return NSAttributedString(string: text, attributes: [
        .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
    ])
}

/// Serif for the passage, matching what the Night style renders on the desktop.
func serif(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    let descriptor = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
    return NSFont(descriptor: descriptor, size: size) ?? base
}

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

background.setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

// A single hairline of the accent along the top: enough identity to be recognisable as a
// product shot, not enough to compete with the text.
amber.withAlphaComponent(0.9).setFill()
NSRect(x: 0, y: height - 6, width: width, height: 6).fill()

let inset: CGFloat = 120
let textWidth = width - inset * 2

// The opening quote mark, the same glyph the app's About page and icon use.
let mark = centered("\u{201C}", font: serif(120), color: amber.withAlphaComponent(0.85), width: textWidth)
mark.draw(in: NSRect(x: inset, y: height - 210, width: textWidth, height: 140))

let passage = centered(quote, font: serif(52), color: quoteInk, width: textWidth)
passage.draw(in: NSRect(x: inset, y: height - 400, width: textWidth, height: 190))

let credit = centered("— \(attribution)", font: serif(28, weight: .medium), color: attributionInk, width: textWidth)
credit.draw(in: NSRect(x: inset, y: height - 452, width: textWidth, height: 40))

// Separator, then the product line. The name is the loudest thing below the passage.
attributionInk.withAlphaComponent(0.25).setFill()
NSRect(x: width / 2 - 60, y: 168, width: 120, height: 1).fill()

let name = centered("KindleWall", font: NSFont.systemFont(ofSize: 44, weight: .semibold), color: .white, width: textWidth)
name.draw(in: NSRect(x: inset, y: 96, width: textWidth, height: 56))

let tagline = centered("Turns your Kindle highlights into desktop wallpapers on macOS",
                       font: NSFont.systemFont(ofSize: 24, weight: .regular), color: attributionInk, width: textWidth)
tagline.draw(in: NSRect(x: inset, y: 56, width: textWidth, height: 34))

let footer = centered("macOS 26+   ·   Homebrew   ·   Open source",
                      font: NSFont.systemFont(ofSize: 18, weight: .medium), color: footerInk, width: textWidth)
footer.draw(in: NSRect(x: inset, y: 22, width: textWidth, height: 26))

image.unlockFocus()

// MARK: - Write

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write(Data("could not encode the card\n".utf8))
    exit(1)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let out = root.appendingPathComponent("docs/social-card.png")
try png.write(to: out)
print("wrote \(out.path) — \(rep.pixelsWide)×\(rep.pixelsHigh), \(png.count) bytes")
