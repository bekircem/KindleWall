import AppKit
import Foundation

// MARK: - Protocol

/// Protocol for generating wallpaper images from clippings.
protocol WallpaperGeneratorProtocol {
    /// Generates a wallpaper image from a clipping using the specified style.
    /// - Parameters:
    ///   - clipping: The clipping to render.
    ///   - style: The visual style to apply.
    ///   - screenSize: The target screen resolution.
    /// - Returns: The rendered wallpaper image, or nil if generation fails.
    func generateWallpaper(clipping: Clipping, style: WallpaperStyle, screenSize: CGSize) -> NSImage?
}

// MARK: - Implementation

/// Generates visually appealing wallpaper images using Core Graphics.
final class WallpaperGenerator: WallpaperGeneratorProtocol {

    func generateWallpaper(clipping: Clipping, style: WallpaperStyle, screenSize: CGSize) -> NSImage? {
        return NSImage.render(size: screenSize) { context in
            let rect = CGRect(origin: .zero, size: screenSize)

            // Draw background
            drawBackground(context: context, rect: rect, style: style)

            // Draw decorative quote marks
            drawDecorativeQuotes(context: context, rect: rect, style: style)

            // Draw clipping text
            drawClippingText(clipping: clipping, context: context, rect: rect, style: style)
        }
    }

    // MARK: - Background Rendering

    private func drawBackground(context: CGContext, rect: CGRect, style: WallpaperStyle) {
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
            drawPaperTextureOverlay(context: context, rect: rect)

        case .elegantSerif:
            drawSolidBackground(context: context, rect: rect, color: NSColor(hex: "2C2C2C")!)

        case .modernSans:
            drawSolidBackground(context: context, rect: rect, color: NSColor(hex: "0D1117")!)
            drawGeometricDecoration(context: context, rect: rect)

        case .natureBlur:
            // Solid dark green as a fallback; a real photo + blur can be added later
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

    private func drawPaperTextureOverlay(context: CGContext, rect: CGRect) {
        // Subtle noise-like overlay for paper texture feel
        context.setFillColor(NSColor(white: 0.5, alpha: 0.03).cgColor)
        let step: CGFloat = 4
        var y: CGFloat = 0
        while y < rect.height {
            var x: CGFloat = 0
            while x < rect.width {
                if Int.random(in: 0...2) == 0 {
                    context.fill(CGRect(x: x, y: y, width: step, height: step))
                }
                x += step
            }
            y += step
        }
    }

    private func drawGeometricDecoration(context: CGContext, rect: CGRect) {
        // Subtle geometric lines for modern style
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

    // MARK: - Decorative Quotes

    private func drawDecorativeQuotes(context: CGContext, rect: CGRect, style: WallpaperStyle) {
        let color: NSColor
        switch style {
        case .minimalDark, .gradientWarm, .gradientCool, .elegantSerif, .modernSans, .natureBlur:
            color = NSColor(white: 1.0, alpha: Constants.Wallpaper.decorativeQuoteOpacity)
        case .minimalLight, .paperTexture:
            color = NSColor(white: 0.0, alpha: Constants.Wallpaper.decorativeQuoteOpacity)
        }

        let fontName: String
        switch style {
        case .modernSans:
            fontName = "SFProDisplay-Bold"
        default:
            fontName = "NewYork-Bold"
        }

        let font = NSFont(name: fontName, size: Constants.Wallpaper.decorativeQuoteFontSize)
            ?? NSFont.systemFont(ofSize: Constants.Wallpaper.decorativeQuoteFontSize, weight: .bold)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]

        let padding = rect.width * Constants.Wallpaper.paddingRatio
        let openQuote = NSAttributedString(string: "\u{201C}", attributes: attributes)
        openQuote.draw(at: CGPoint(x: padding - 20, y: rect.height * 0.65))

        let closeQuote = NSAttributedString(string: "\u{201D}", attributes: attributes)
        let closeSize = closeQuote.size()
        closeQuote.draw(at: CGPoint(x: rect.width - padding - closeSize.width + 20, y: rect.height * 0.3))
    }

    // MARK: - Text Rendering

    private func drawClippingText(clipping: Clipping, context: CGContext, rect: CGRect, style: WallpaperStyle) {
        let padding = rect.width * Constants.Wallpaper.paddingRatio
        let textRect = CGRect(
            x: padding,
            y: rect.height * 0.35,
            width: rect.width - padding * 2,
            height: rect.height * 0.35
        )

        let textColor = textColor(for: style)
        let metaColor = metaColor(for: style)
        let fontName = quoteFont(for: style)

        // Dynamic font sizing
        let fontSize = calculateFontSize(for: clipping.text, in: textRect, fontName: fontName)
        let font = NSFont(name: fontName, size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = fontSize * 0.3

        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]

        let attributedText = NSAttributedString(string: clipping.text, attributes: textAttributes)
        attributedText.draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])

        // Draw book title and author below the quote
        let metaY = textRect.origin.y - 40
        let metaFont = NSFont.systemFont(ofSize: 18, weight: .light)
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

        let metaRect = CGRect(x: padding, y: metaY, width: rect.width - padding * 2, height: 30)
        let attributedMeta = NSAttributedString(string: metaText, attributes: metaAttributes)
        attributedMeta.draw(with: metaRect, options: [.usesLineFragmentOrigin])
    }

    private func calculateFontSize(for text: String, in rect: CGRect, fontName: String) -> CGFloat {
        var fontSize = Constants.Wallpaper.maxFontSize

        while fontSize > Constants.Wallpaper.minFontSize {
            let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = fontSize * 0.3

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
            fontSize -= 2
        }

        return Constants.Wallpaper.minFontSize
    }

    private func textColor(for style: WallpaperStyle) -> NSColor {
        switch style {
        case .minimalDark, .gradientWarm, .gradientCool, .elegantSerif, .modernSans, .natureBlur:
            return .white
        case .minimalLight:
            return NSColor(hex: "2C2C2C")!
        case .paperTexture:
            return NSColor(hex: "3B2F1E")!
        }
    }

    private func metaColor(for style: WallpaperStyle) -> NSColor {
        switch style {
        case .minimalDark, .gradientWarm, .gradientCool, .elegantSerif, .modernSans, .natureBlur:
            return NSColor(white: 1.0, alpha: 0.6)
        case .minimalLight:
            return NSColor(white: 0.0, alpha: 0.5)
        case .paperTexture:
            return NSColor(hex: "3B2F1E")!.withAlphaComponent(0.6)
        }
    }

    private func quoteFont(for style: WallpaperStyle) -> String {
        switch style {
        case .minimalDark, .minimalLight, .paperTexture, .elegantSerif:
            return "NewYork-Regular"
        case .gradientWarm, .gradientCool, .natureBlur:
            return "NewYork-Medium"
        case .modernSans:
            return "SFProDisplay-Regular"
        }
    }
}
