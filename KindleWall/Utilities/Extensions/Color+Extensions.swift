import SwiftUI
import AppKit

extension Color {
    /// Converts a SwiftUI Color to NSColor.
    var nsColor: NSColor {
        NSColor(self)
    }

    /// Returns a 6-character uppercase hex string (e.g. "FF6B35"), or nil if conversion fails.
    var hexString: String? {
        guard let cgColor = NSColor(self).cgColor
            .converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
              let components = cgColor.components, components.count >= 3 else { return nil }
        let r = Int((components[0] * 255).rounded())
        let g = Int((components[1] * 255).rounded())
        let b = Int((components[2] * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }

    /// Initializes a Color from a 6-character hex string (e.g. "FF6B35"). Returns nil if invalid.
    init?(hex: String) {
        guard let ns = NSColor(hex: hex) else { return nil }
        self.init(ns)
    }
}

extension NSColor {
    /// Creates an NSColor from a hex string (e.g., "#FF5733" or "FF5733").
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6,
              let hexNumber = UInt64(hexSanitized, radix: 16) else {
            return nil
        }

        let r = CGFloat((hexNumber & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((hexNumber & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(hexNumber & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
