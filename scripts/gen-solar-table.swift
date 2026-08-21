#!/usr/bin/env swift
//
//  gen-solar-table.swift
//
//  Generates `docs/solar-table.json` — the exact colours the app's solar (dynamic) wallpaper
//  produces for every (style, phase) pair, so a web page can reproduce them without shipping
//  a Core Image runtime.
//
//  Run:  swift scripts/gen-solar-table.swift > docs/solar-table.json
//
//  How it works: it runs the *same* Core Image chain the app runs
//  (`CITemperatureAndTint` → `CIExposureAdjust`, rendered through a 1×1 RGBA8 bitmap in
//  device RGB) over every background gradient stop of every style, using the phase transform
//  `SolarPalette` computes — including the readability guard that can nudge the exposure and
//  flip the ink colour. The numbers are therefore measured, not modelled.
//
//  ⚠️  THIS FILE IS A STANDALONE COPY OF APP LOGIC.
//      It duplicates, by value:
//        • the phase curve and per-style tuning   — KindleWall/Models/SolarPalette.swift
//        • `readableExposure` and `minimumContrast` — KindleWall/Models/SolarPalette.swift
//        • the filter chain and `resolve`          — KindleWall/Services/SolarColorTransform.swift
//        • `drawBackground` stop colours,
//          `backgroundColor(for:)`, `inkColor(for:inverted:)`
//                                                  — KindleWall/Services/WallpaperGenerator.swift
//        • `WallpaperStyle.hasLightBackground`     — KindleWall/Models/WallpaperStyle.swift
//      If ANY of those change, this script is stale and `docs/solar-table.json` is wrong.
//      Re-run it and commit the regenerated JSON.
//
//  Assumptions: `TypographySettings.default` (no custom background gradient). A user-set
//  custom gradient replaces the style surface entirely and is out of scope for the table.
//

import AppKit
import CoreImage
import Foundation

// MARK: - Colour helpers (mirrors NSColor+hex in Utilities/Extensions/Color+Extensions.swift)

/// NOTE: the app's `NSColor(hex:)` uses `init(red:green:blue:alpha:)`, which is the *calibrated*
/// RGB space, not `deviceRed:`. The later `usingColorSpace(.deviceRGB)` conversion inside
/// `resolve` therefore shifts the components very slightly. Keeping the same initialiser here
/// keeps the shift identical.
func hexColor(_ hex: String) -> NSColor {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    s = s.replacingOccurrences(of: "#", with: "")
    guard s.count == 6, let n = UInt64(s, radix: 16) else {
        fatalError("bad hex: \(hex)")
    }
    return NSColor(red:   CGFloat((n & 0xFF0000) >> 16) / 255.0,
                   green: CGFloat((n & 0x00FF00) >> 8) / 255.0,
                   blue:  CGFloat(n & 0x0000FF) / 255.0,
                   alpha: 1.0)
}

// MARK: - SolarColorTransform (mirrors KindleWall/Services/SolarColorTransform.swift)

struct Transform {
    let kelvin: Double
    let exposure: Double
}

let ciContext = CIContext(options: [.useSoftwareRenderer: false])

func apply(_ transform: Transform, to image: CIImage) -> CIImage {
    let warmed = image.applyingFilter("CITemperatureAndTint", parameters: [
        "inputNeutral": CIVector(x: 6500, y: 0),
        "inputTargetNeutral": CIVector(x: transform.kelvin, y: 0)
    ])
    return warmed.applyingFilter("CIExposureAdjust", parameters: [
        "inputEV": transform.exposure
    ])
}

/// The 8-bit device-RGB pixel a colour becomes after the chain — the same bytes the composer
/// writes into the frame bitmap.
func resolveBytes(_ color: NSColor, through transform: Transform) -> (UInt8, UInt8, UInt8) {
    guard let rgb = color.usingColorSpace(.deviceRGB) else {
        fatalError("colour space conversion failed")
    }
    let source = CIImage(color: CIColor(red: rgb.redComponent,
                                        green: rgb.greenComponent,
                                        blue: rgb.blueComponent))
        .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))

    var pixel = [UInt8](repeating: 0, count: 4)
    ciContext.render(apply(transform, to: source),
                     toBitmap: &pixel,
                     rowBytes: 4,
                     bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                     format: .RGBA8,
                     colorSpace: CGColorSpaceCreateDeviceRGB())
    return (pixel[0], pixel[1], pixel[2])
}

func resolve(_ color: NSColor, through transform: Transform) -> NSColor {
    let (r, g, b) = resolveBytes(color, through: transform)
    return NSColor(deviceRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
                   blue: CGFloat(b) / 255, alpha: 1)
}

func relativeLuminance(_ color: NSColor) -> Double {
    guard let rgb = color.usingColorSpace(.deviceRGB) else { return 0.5 }
    func channel(_ v: CGFloat) -> Double {
        let c = Double(v)
        return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(rgb.redComponent)
         + 0.7152 * channel(rgb.greenComponent)
         + 0.0722 * channel(rgb.blueComponent)
}

func contrastRatio(_ a: NSColor, _ b: NSColor) -> Double {
    let la = relativeLuminance(a), lb = relativeLuminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

// MARK: - Styles and phases

enum Style: String, CaseIterable {
    case night, paper, grid, dawn, depth, forestLight

    /// `WallpaperStyle.hasLightBackground`
    var hasLightBackground: Bool { self == .paper }

    /// The background gradient stops `WallpaperGenerator.drawBackground` fills with.
    /// One entry = solid fill; three = gradient (linear, except forestLight which is radial).
    var stops: [String] {
        switch self {
        case .night:       return ["141414"]
        case .paper:       return ["F4E8C1"]
        case .grid:        return ["0D1117"]
        case .dawn:        return ["FF8A4C", "E0453A", "8A2F2A"]
        case .depth:       return ["667EEA", "764BA2", "1B1464"]
        case .forestLight: return ["35662F", "17330F", "08150A"]
        }
    }

    /// `WallpaperGenerator.backgroundColor(for:typography:)` — flat fill, or gradient midpoint.
    var representativeBackground: NSColor {
        switch self {
        case .night:       return hexColor("141414")
        case .paper:       return hexColor("F4E8C1")
        case .grid:        return hexColor("0D1117")
        case .dawn:        return hexColor("E0453A")
        case .depth:       return hexColor("764BA2")
        case .forestLight: return hexColor("17330F")
        }
    }

    /// `WallpaperGenerator.inkColor(for:typography:inverted:)`
    func ink(inverted: Bool) -> NSColor {
        let onLight = inverted ? !hasLightBackground : hasLightBackground
        return onLight ? hexColor("3B2F1E") : NSColor.white
    }

    /// `SolarPalette.tuning(for:)`
    var tuning: (warmth: Double, lift: Double, floor: Double) {
        switch self {
        case .night:       return (0.40, 0.15, 0.55)
        case .paper:       return (1.00, 0.60, 0.22)
        case .grid:        return (0.25, 0.20, 0.50)
        case .dawn:        return (0.80, 0.45, 0.35)
        case .depth:       return (0.45, 0.40, 0.35)
        case .forestLight: return (0.85, 0.50, 0.30)
        }
    }
}

enum Phase: String, CaseIterable {
    case dawn, sunrise, noon, afternoon, sunset, night

    /// `SolarPalette.curve`
    var base: (kelvin: Double, exposure: Double) {
        switch self {
        case .dawn:      return (5600, -0.85)
        case .sunrise:   return (3200, -0.30)
        case .noon:      return (6500,  0.00)
        case .afternoon: return (5200, -0.10)
        case .sunset:    return (2900, -0.35)
        case .night:     return (4200, -1.30)
        }
    }
}

// MARK: - SolarPalette (mirrors KindleWall/Models/SolarPalette.swift)

let minimumContrast = 4.5

/// `SolarPalette.readableExposure` — walks outward from the intended exposure, intended
/// direction first, and takes the first value where one of the two inks clears WCAG AA.
func readableExposure(intended: Double, kelvin: Double, surface: NSColor,
                      normalInk: NSColor, invertedInk: NSColor) -> (exposure: Double, inverted: Bool) {

    func evaluate(_ exposure: Double) -> (score: Double, inverted: Bool) {
        let resolved = resolve(surface, through: Transform(kelvin: kelvin, exposure: exposure))
        let normal = contrastRatio(normalInk, resolved)
        let inverse = contrastRatio(invertedInk, resolved)
        return inverse > normal ? (inverse, true) : (normal, false)
    }

    let atIntended = evaluate(intended)
    if atIntended.score >= minimumContrast { return (intended, atIntended.inverted) }

    let lowerBound = -5.0, upperBound = 0.5
    let step = 0.1
    let directions: [Double] = intended <= 0 ? [-1, 1] : [1, -1]

    for direction in directions {
        for i in 1...30 {
            let candidate = intended + direction * Double(i) * step
            guard candidate >= lowerBound, candidate <= upperBound else { break }
            let result = evaluate(candidate)
            if result.score >= minimumContrast { return (candidate, result.inverted) }
        }
    }
    return (intended, atIntended.inverted)
}

/// `SolarPalette.transforms(for:style:typography:)`
func transforms(for phase: Phase, style: Style) -> (kelvin: Double, exposure: Double, inverted: Bool) {
    let base = phase.base
    let tune = style.tuning

    let kelvin = 6500 + (base.kelvin - 6500) * tune.warmth
    let rawExposure = base.exposure * tune.lift / 0.45
    let floorStops = log2(max(tune.floor, 0.01))
    let backgroundExposure = max(rawExposure, floorStops)

    let readable = readableExposure(intended: backgroundExposure,
                                    kelvin: kelvin,
                                    surface: style.representativeBackground,
                                    normalInk: style.ink(inverted: false),
                                    invertedInk: style.ink(inverted: true))
    return (kelvin, readable.exposure, readable.inverted)
}

// MARK: - Emit

func num(_ v: Double, _ places: Int) -> String {
    var s = String(format: "%.\(places)f", v)
    // Trim trailing zeros so 6140.0000 reads as 6140, -0.2833 stays -0.2833.
    if s.contains(".") {
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
    }
    if s == "-0" { s = "0" }
    return s
}

var out = "{\n"
out += "  \"phases\": [" + Phase.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ") + "],\n"
out += "  \"styles\": {\n"

let styleBlocks: [String] = Style.allCases.map { style in
    let phaseBlocks: [String] = Phase.allCases.map { phase in
        let t = transforms(for: phase, style: style)
        let transform = Transform(kelvin: t.kelvin, exposure: t.exposure)
        let hexes = style.stops.map { stop -> String in
            let (r, g, b) = resolveBytes(hexColor(stop), through: transform)
            return "\"#" + String(format: "%02x%02x%02x", r, g, b) + "\""
        }
        var line = "      \"\(phase.rawValue)\": { "
        line += "\"stops\": [" + hexes.joined(separator: ", ") + "], "
        line += "\"invertedInk\": \(t.inverted), "
        line += "\"kelvin\": \(num(t.kelvin, 4)), "
        line += "\"exposure\": \(num(t.exposure, 4)) }"
        return line
    }
    return "    \"\(style.rawValue)\": {\n" + phaseBlocks.joined(separator: ",\n") + "\n    }"
}

out += styleBlocks.joined(separator: ",\n") + "\n"
out += "  }\n}\n"

print(out, terminator: "")
