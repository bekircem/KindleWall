import Foundation

/// A user-supplied correction for a book's title and/or author as parsed from My Clippings.txt.
/// Keyed by the original parsed title so overrides survive file re-imports.
struct BookMetadataOverride: Codable, Equatable {
    /// The raw title as it appears in My Clippings.txt — used as the storage key.
    let originalTitle: String
    /// User-corrected display title.
    var displayTitle: String
    /// User-corrected display author. nil means "keep original".
    var displayAuthor: String?
}
