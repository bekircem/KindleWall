import Foundation

/// Represents the type of a Kindle clipping entry.
enum ClippingType: String, Codable, CaseIterable {
    case highlight
    case note
    case bookmark
}
