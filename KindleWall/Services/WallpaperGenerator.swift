import AppKit
import Foundation

// MARK: - Protocol

/// Protocol for generating wallpaper images from clippings.
protocol WallpaperGeneratorProtocol {
    /// Generates a wallpaper image from a clipping using the specified style.
    func generateWallpaper(clipping: Clipping, style: WallpaperStyle, screenSize: CGSize, typography: TypographySettings, longQuote: LongQuoteSettings) -> NSImage?
}

extension WallpaperGeneratorProtocol {
    func generateWallpaper(clipping: Clipping, style: WallpaperStyle, screenSize: CGSize, typography: TypographySettings = .default) -> NSImage? {
        generateWallpaper(clipping: clipping, style: style, screenSize: screenSize, typography: typography, longQuote: .default)
    }
}

// MARK: - Implementation

/// Generates visually appealing wallpaper images using Core Graphics.
final class WallpaperGenerator: WallpaperGeneratorProtocol {

    /// Length-derived rendering profile. Tightens font, line spacing, and padding
    /// progressively for longer quotes so they don't dominate the desktop.
    private struct LengthProfile {
        let baseMaxFontPt: CGFloat       // before scaling
        let minFontPt: CGFloat           // before scaling
        let maxTextRatio: CGFloat        // fraction of screen height
        let lineSpacingMultiplier: CGFloat
        let paddingMultiplier: CGFloat
    }

    private static func lengthProfile(charCount: Int, tightenLength: Int, settings: LongQuoteSettings) -> LengthProfile {
        // Original short-quote tiers — always active.
        if charCount < 80 {
            return LengthProfile(baseMaxFontPt: 42, minFontPt: 22, maxTextRatio: 0.25, lineSpacingMultiplier: 0.40, paddingMultiplier: 1.00)
        }
        if charCount < 250 {
            return LengthProfile(baseMaxFontPt: 38, minFontPt: 20, maxTextRatio: 0.35, lineSpacingMultiplier: 0.35, paddingMultiplier: 1.00)
        }

        // Quote is "medium-long" but below the user's tighten threshold (or tightening disabled) —
        // use the legacy ≥250 profile, no aggressive tightening.
        guard settings.autoTightenEnabled, tightenLength >= settings.tightenThreshold else {
            return LengthProfile(baseMaxFontPt: 32, minFontPt: 18, maxTextRatio: 0.45, lineSpacingMultiplier: 0.35, paddingMultiplier: 1.00)
        }

        // Aggressive tightening: baseMaxFontPt / maxTextRatio / paddingMultiplier scale by
        // character length (smart defaults), but the FLOOR font size and line spacing come
        // from user settings so the user controls exactly how small/tight things can get.
        let userMin = CGFloat(settings.minFontPt)
        let userLine = CGFloat(settings.lineSpacingMultiplier)

        let baseMax: CGFloat
        let textRatio: CGFloat
        let paddingMul: CGFloat
        if charCount < 500 {
            baseMax = 30; textRatio = 0.45; paddingMul = 0.90
        } else if charCount < 800 {
            baseMax = 26; textRatio = 0.55; paddingMul = 0.85
        } else {
            baseMax = 22; textRatio = 0.60; paddingMul = 0.80
        }

        // Guard against the floor exceeding the base — keep base ≥ floor + 2pt headroom so
        // the font-size search has something to step through.
        let safeBase = max(baseMax, userMin + 2)

        return LengthProfile(
            baseMaxFontPt: safeBase,
            minFontPt: userMin,
            maxTextRatio: textRatio,
            lineSpacingMultiplier: userLine,
            paddingMultiplier: paddingMul
        )
    }

    func generateWallpaper(clipping: Clipping, style: WallpaperStyle, screenSize: CGSize, typography: TypographySettings = .default, longQuote: LongQuoteSettings = .default) -> NSImage? {
        return NSImage.render(size: screenSize) { context in
            let rect = CGRect(origin: .zero, size: screenSize)

            // Derive a deterministic seed from the clipping UUID bytes so paper texture
        // looks the same in preview and when applied (no randomness across renders).
        let uuid = clipping.id.uuid
        let textureSeed = UInt64(uuid.0) | UInt64(uuid.1) << 8 | UInt64(uuid.2) << 16 |
                          UInt64(uuid.3) << 24 | UInt64(uuid.4) << 32 | UInt64(uuid.5) << 40 |
                          UInt64(uuid.6) << 48 | UInt64(uuid.7) << 56

        drawBackground(context: context, rect: rect, style: style, typography: typography, textureSeed: textureSeed)

            // Scale factor: all fixed pt values are designed for 900pt height.
            // At 1800pt (Retina) everything doubles automatically.
            let referenceHeight: CGFloat = 900
            let sf = rect.height / referenceHeight

            // Length-adaptive profile — tightens for long quotes per user-configured threshold and floors.
            let charCount = clipping.text.count
            let tightenLength = longQuote.tightenUnit.measure(clipping.text)
            let profile = Self.lengthProfile(charCount: charCount, tightenLength: tightenLength, settings: longQuote)

            // Apply typography settings
            let basePadding = rect.width * Constants.Wallpaper.paddingRatio
            let padding = basePadding * typography.paddingScale * profile.paddingMultiplier
            let contentWidth = rect.width - padding * 2
            let textColor = textColor(for: style, typography: typography)
                .withAlphaComponent(typography.textOpacity)
            let metaColor = metaColor(for: style, typography: typography)
                .withAlphaComponent(typography.textOpacity)

            // Adaptive font limits based on profile, scaled to resolution and user typography.
            let maxFont = profile.baseMaxFontPt * sf * typography.fontScale
            let minFont = profile.minFontPt * sf * typography.fontScale
            let fontStep = max(2, round(2 * sf))

            let maxTextHeight = rect.height * profile.maxTextRatio
            let sizeRect = CGRect(x: 0, y: 0, width: contentWidth, height: maxTextHeight)
            let fontSize = calculateFontSize(for: clipping.text, in: sizeRect, typography: typography, maxSize: maxFont, minSize: minFont, step: fontStep, lineSpacingMultiplier: profile.lineSpacingMultiplier)

            // Quote text attributes
            let font = makeQuoteFont(size: fontSize, typography: typography)
            let lineSpacing = fontSize * profile.lineSpacingMultiplier * typography.lineSpacingScale
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            paragraphStyle.lineSpacing = lineSpacing

            var textAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle
            ]
            if typography.letterSpacing != 0 {
                textAttributes[.kern] = typography.letterSpacing
            }

            let textBounds = (clipping.text as NSString).boundingRect(
                with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: textAttributes
            )

            // Meta text attributes — ratio increased to 0.50 for better readability
            let metaFontSize: CGFloat = max(fontSize * 0.50, 24 * sf * typography.fontScale)
            let metaFont = NSFont.systemFont(ofSize: metaFontSize, weight: .light)
            let metaItalicFont = NSFontManager.shared.convert(metaFont, toHaveTrait: .italicFontMask)

            var metaText = clipping.bookTitle
            if let author = clipping.author {
                metaText += " — \(author)"
            }

            let metaParagraph = NSMutableParagraphStyle()
            metaParagraph.alignment = .center

            let metaAttributes: [NSAttributedString.Key: Any] = [
                .font: metaItalicFont,
                .foregroundColor: metaColor,
                .paragraphStyle: metaParagraph
            ]

            let metaBounds = (metaText as NSString).boundingRect(
                with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: metaAttributes
            )

            // Screen-proportional spacing
            let quoteIconSize: CGFloat = 28 * sf
            let quoteIconGap: CGFloat = rect.height * 0.025
            let metaGap: CGFloat = rect.height * 0.03

            // Total content block height
            let totalHeight = quoteIconSize + quoteIconGap + textBounds.height + metaGap + metaBounds.height

            // Vertical centering with user bias
            let verticalPadding = rect.height * 0.10
            let usableHeight = rect.height - verticalPadding * 2
            let centerY = verticalPadding + usableHeight / 2
            let biasOffset = typography.verticalPosition * (usableHeight - totalHeight) / 2
            var topY = centerY + totalHeight / 2 + biasOffset

            // Clamp to safe zone
            topY = min(topY, rect.height - verticalPadding)
            if topY - totalHeight < verticalPadding {
                topY = verticalPadding + totalHeight
            }

            // 1. Decorative element at top of content block
            var cursorY = topY
            drawDecoration(
                context: context,
                centerX: rect.width / 2,
                topY: cursorY,
                size: quoteIconSize,
                style: style,
                typography: typography
            )
            cursorY -= quoteIconSize + quoteIconGap

            // 2. Quote text
            let drawTextRect = CGRect(
                x: padding,
                y: cursorY - textBounds.height,
                width: contentWidth,
                height: textBounds.height + 4
            )
            let attributedText = NSAttributedString(string: clipping.text, attributes: textAttributes)
            if typography.shadowEnabled {
                context.saveGState()
                context.setShadow(
                    offset: CGSize(width: 0, height: -1),
                    blur: typography.shadowRadius,
                    color: shadowColor(for: style, typography: typography).cgColor
                )
                attributedText.draw(with: drawTextRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
                context.restoreGState()
            } else {
                attributedText.draw(with: drawTextRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            }
            cursorY -= textBounds.height + metaGap * 0.5

            // 3. Thin separator line
            let separatorMaxWidth: CGFloat = 70 * sf
            let lineWidth: CGFloat = min(contentWidth * 0.12, separatorMaxWidth)
            context.setStrokeColor(metaColor.withAlphaComponent(0.3).cgColor)
            context.setLineWidth(1 * sf)
            context.move(to: CGPoint(x: (rect.width - lineWidth) / 2, y: cursorY))
            context.addLine(to: CGPoint(x: (rect.width + lineWidth) / 2, y: cursorY))
            context.strokePath()
            cursorY -= metaGap * 0.5

            // 4. Book title and author
            let metaRect = CGRect(x: padding, y: cursorY - metaBounds.height, width: contentWidth, height: metaBounds.height + 4)
            let attributedMeta = NSAttributedString(string: metaText, attributes: metaAttributes)
            attributedMeta.draw(with: metaRect, options: [.usesLineFragmentOrigin])
        }
    }

    // MARK: - Background Rendering

    private func drawBackground(context: CGContext, rect: CGRect, style: WallpaperStyle,
                                typography: TypographySettings, textureSeed: UInt64 = 0) {
        if let startHex = typography.backgroundStartColorHex,
           let endHex   = typography.backgroundEndColorHex,
           let startColor = NSColor(hex: startHex),
           let endColor   = NSColor(hex: endHex) {
            drawGradientBackground(context: context, rect: rect, colors: [startColor, endColor])
            return
        }

        switch style {
        case .minimalDark:
            drawSolidBackground(context: context, rect: rect, color: NSColor(hex: "1A1A1A")!)

        case .minimalLight:
            drawSolidBackground(context: context, rect: rect, color: NSColor(hex: "F5F1EB")!)

        case .gradientWarm:
            drawGradientBackground(
                context: context, rect: rect,
                colors: [NSColor(hex: "FF6B35")!, NSColor(hex: "D62828")!, NSColor(hex: "7B2D26")!]
            )

        case .gradientCool:
            drawGradientBackground(
                context: context, rect: rect,
                colors: [NSColor(hex: "667EEA")!, NSColor(hex: "764BA2")!, NSColor(hex: "1B1464")!]
            )

        case .paperTexture:
            drawSolidBackground(context: context, rect: rect, color: NSColor(hex: "F4E8C1")!)
            drawPaperTextureOverlay(context: context, rect: rect, seed: textureSeed)

        case .elegantSerif:
            drawSolidBackground(context: context, rect: rect, color: NSColor(hex: "2C2C2C")!)

        case .modernSans:
            drawSolidBackground(context: context, rect: rect, color: NSColor(hex: "0D1117")!)
            drawGeometricDecoration(context: context, rect: rect)

        case .natureBlur:
            drawGradientBackground(
                context: context, rect: rect,
                colors: [NSColor(hex: "2D5016")!, NSColor(hex: "1A3A0A")!, NSColor(hex: "0F2006")!]
            )
        }
    }

    private func drawSolidBackground(context: CGContext, rect: CGRect, color: NSColor) {
        context.setFillColor(color.cgColor)
        context.fill(rect)
    }

    private func drawGradientBackground(context: CGContext, rect: CGRect, colors: [NSColor]) {
        let cgColors = colors.map { $0.cgColor } as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: cgColors,
            locations: nil
        ) else { return }

        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: rect.height),
            end: CGPoint(x: rect.width, y: 0),
            options: []
        )
    }

    private func drawPaperTextureOverlay(context: CGContext, rect: CGRect, seed: UInt64) {
        context.setFillColor(NSColor(white: 0.5, alpha: 0.03).cgColor)
        let step: CGFloat = 4
        var rng = SeededRNG(seed: seed)
        var y: CGFloat = 0
        while y < rect.height {
            var x: CGFloat = 0
            while x < rect.width {
                if rng.next() % 3 == 0 {
                    context.fill(CGRect(x: x, y: y, width: step, height: step))
                }
                x += step
            }
            y += step
        }
    }

    private func drawGeometricDecoration(context: CGContext, rect: CGRect) {
        context.setStrokeColor(NSColor(white: 1.0, alpha: 0.05).cgColor)
        context.setLineWidth(1)

        let padding = rect.width * Constants.Wallpaper.paddingRatio
        context.move(to: CGPoint(x: padding, y: rect.height * 0.3))
        context.addLine(to: CGPoint(x: rect.width - padding, y: rect.height * 0.3))
        context.strokePath()

        context.move(to: CGPoint(x: padding, y: rect.height * 0.7))
        context.addLine(to: CGPoint(x: rect.width - padding, y: rect.height * 0.7))
        context.strokePath()
    }

    // MARK: - Decoration

    /// Dispatches to the appropriate decoration renderer based on the typography setting.
    private func drawDecoration(context: CGContext, centerX: CGFloat, topY: CGFloat,
                                size: CGFloat, style: WallpaperStyle, typography: TypographySettings) {
        switch typography.decorativeStyle {
        case .classicQuote:
            drawClassicQuoteMark(context: context, centerX: centerX, topY: topY, size: size, style: style, typography: typography)
        case .minimalDots:
            drawQuoteIcon(context: context, centerX: centerX, topY: topY, size: size, style: style)
        case .line:
            drawDecorationLine(context: context, centerX: centerX, topY: topY, size: size, style: style)
        case .none:
            break
        }
    }

    /// Draws a large typographic open-quote mark " using the quote font family from typography settings.
    private func drawClassicQuoteMark(context: CGContext, centerX: CGFloat, topY: CGFloat,
                                      size: CGFloat, style: WallpaperStyle, typography: TypographySettings) {
        let iconColor: NSColor
        switch style {
        case .minimalDark, .gradientWarm, .gradientCool, .elegantSerif, .modernSans, .natureBlur:
            iconColor = NSColor(white: 1.0, alpha: 0.30)
        case .minimalLight, .paperTexture:
            iconColor = NSColor(white: 0.0, alpha: 0.20)
        }

        // Point size ~2× the allocated icon size; visual glyph height ≈ 55% of point size,
        // so the " character fills the quoteIconSize area naturally.
        let fontSize = size * 2.0
        let font = makeQuoteFont(size: fontSize, typography: typography)

        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: iconColor]
        let str = NSAttributedString(string: "\u{201C}", attributes: attrs)
        let strSize = str.size()

        // Center horizontally; bottom-left in Core Graphics upward-Y coordinates
        let drawPoint = CGPoint(x: centerX - strSize.width / 2, y: topY - strSize.height)
        str.draw(at: drawPoint)
    }

    /// Draws a thin centered horizontal rule in the allocated decoration space.
    private func drawDecorationLine(context: CGContext, centerX: CGFloat, topY: CGFloat,
                                    size: CGFloat, style: WallpaperStyle) {
        let lineColor: NSColor
        switch style {
        case .minimalDark, .gradientWarm, .gradientCool, .elegantSerif, .modernSans, .natureBlur:
            lineColor = NSColor(white: 1.0, alpha: 0.40)
        case .minimalLight, .paperTexture:
            lineColor = NSColor(white: 0.0, alpha: 0.30)
        }

        let lineThickness = max(1.0, size * 0.05)
        let lineLength = size * 2.5
        let lineY = topY - size / 2  // vertically centered within allocated icon space

        context.setStrokeColor(lineColor.cgColor)
        context.setLineWidth(lineThickness)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: centerX - lineLength / 2, y: lineY))
        context.addLine(to: CGPoint(x: centerX + lineLength / 2, y: lineY))
        context.strokePath()
    }

    /// Draws the original minimal decorative quote icon (two small vertical bars with dots).
    private func drawQuoteIcon(context: CGContext, centerX: CGFloat, topY: CGFloat, size: CGFloat, style: WallpaperStyle) {
        let color: NSColor
        switch style {
        case .minimalDark, .gradientWarm, .gradientCool, .elegantSerif, .modernSans, .natureBlur:
            color = NSColor(white: 1.0, alpha: 0.25)
        case .minimalLight, .paperTexture:
            color = NSColor(white: 0.0, alpha: 0.15)
        }

        // Draw a minimal open-quote glyph using two thin rounded bars
        let barWidth: CGFloat = size * 0.08
        let barHeight: CGFloat = size * 0.45
        let dotRadius: CGFloat = size * 0.07
        let pairGap: CGFloat = size * 0.22

        context.setFillColor(color.cgColor)

        // Left quote mark
        let leftX = centerX - pairGap / 2 - barWidth
        // Dot (circle)
        let leftDotRect = CGRect(
            x: leftX - dotRadius + barWidth / 2,
            y: topY - dotRadius * 2,
            width: dotRadius * 2,
            height: dotRadius * 2
        )
        context.fillEllipse(in: leftDotRect)
        // Bar
        let leftBarRect = CGRect(
            x: leftX,
            y: topY - dotRadius * 2 - barHeight - 2,
            width: barWidth,
            height: barHeight
        )
        context.fill(leftBarRect)

        // Right quote mark
        let rightX = centerX + pairGap / 2
        let rightDotRect = CGRect(
            x: rightX - dotRadius + barWidth / 2,
            y: topY - dotRadius * 2,
            width: dotRadius * 2,
            height: dotRadius * 2
        )
        context.fillEllipse(in: rightDotRect)
        let rightBarRect = CGRect(
            x: rightX,
            y: topY - dotRadius * 2 - barHeight - 2,
            width: barWidth,
            height: barHeight
        )
        context.fill(rightBarRect)
    }

    // MARK: - Helpers

    private func calculateFontSize(for text: String, in rect: CGRect, typography: TypographySettings, maxSize: CGFloat = Constants.Wallpaper.maxFontSize, minSize: CGFloat = Constants.Wallpaper.minFontSize, step: CGFloat = 2, lineSpacingMultiplier: CGFloat = 0.35) -> CGFloat {
        var fontSize = maxSize

        while fontSize > minSize {
            let font = makeQuoteFont(size: fontSize, typography: typography)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = fontSize * lineSpacingMultiplier

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .paragraphStyle: paragraphStyle
            ]

            let boundingRect = (text as NSString).boundingRect(
                with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: attributes
            )

            if boundingRect.height <= rect.height {
                return fontSize
            }
            fontSize -= step
        }

        return minSize
    }

    private func textColor(for style: WallpaperStyle, typography: TypographySettings) -> NSColor {
        if let startHex = typography.backgroundStartColorHex,
           let color = NSColor(hex: startHex) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return (0.299 * r + 0.587 * g + 0.114 * b) > 0.5
                ? NSColor(hex: "2C2C2C")!
                : .white
        }
        switch style {
        case .minimalDark, .gradientWarm, .gradientCool, .elegantSerif, .modernSans, .natureBlur:
            return .white
        case .minimalLight:
            return NSColor(hex: "2C2C2C")!
        case .paperTexture:
            return NSColor(hex: "3B2F1E")!
        }
    }

    private func metaColor(for style: WallpaperStyle, typography: TypographySettings) -> NSColor {
        if let startHex = typography.backgroundStartColorHex,
           let color = NSColor(hex: startHex) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return (0.299 * r + 0.587 * g + 0.114 * b) > 0.5
                ? NSColor(white: 0.0, alpha: 0.45)
                : NSColor(white: 1.0, alpha: 0.55)
        }
        switch style {
        case .minimalDark, .gradientWarm, .gradientCool, .elegantSerif, .modernSans, .natureBlur:
            return NSColor(white: 1.0, alpha: 0.55)
        case .minimalLight:
            return NSColor(white: 0.0, alpha: 0.45)
        case .paperTexture:
            return NSColor(hex: "3B2F1E")!.withAlphaComponent(0.55)
        }
    }

    private func makeQuoteFont(size: CGFloat, typography: TypographySettings) -> NSFont {
        switch typography.fontFamily {
        case .serif:
            if let descriptor = NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif) {
                return NSFont(descriptor: descriptor, size: size) ?? NSFont.systemFont(ofSize: size)
            }
            return NSFont.systemFont(ofSize: size)
        case .sansSerif:
            return NSFont.systemFont(ofSize: size)
        case .classic:
            return NSFont(name: "Palatino-Roman", size: size)
                ?? NSFont(name: "Palatino", size: size)
                ?? NSFont.systemFont(ofSize: size)
        case .monospace:
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }

    private func shadowColor(for style: WallpaperStyle, typography: TypographySettings) -> NSColor {
        let lightBackground: Bool
        if let hex = typography.backgroundStartColorHex, let c = NSColor(hex: hex) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            lightBackground = (0.299 * r + 0.587 * g + 0.114 * b) > 0.5
        } else {
            lightBackground = (style == .minimalLight || style == .paperTexture)
        }
        return lightBackground
            ? NSColor.black.withAlphaComponent(0.50)
            : NSColor.white.withAlphaComponent(0.30)
    }
}

// MARK: - Seeded RNG

/// A simple Linear Congruential Generator for deterministic pseudo-random sequences.
private struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 1 : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 33
    }
}
