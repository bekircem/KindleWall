import Foundation

/// A book as the rotation scope UI needs it: identity, author, and how many quotes it brings.
///
/// Replaces the `(title:author:)` tuple this used to be passed around as. The count is the
/// reason the type exists — pinning a book without it is a blind choice, because a book with
/// four highlights and a book with four hundred looked identical in the picker.
struct RotationBook: Identifiable, Hashable, Sendable {
    let title: String
    let author: String?
    let quoteCount: Int

    var id: String { title }

    /// Match over title and author for the picker's search, tolerant of how Turkish actually
    /// gets typed.
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let needle = Self.normalized(query)
        if Self.normalized(title).contains(needle) { return true }
        guard let author else { return false }
        return Self.normalized(author).contains(needle)
    }

    /// Folds case, diacritics, and the dotless ı.
    ///
    /// `.diacriticInsensitive` alone is not enough, and the test caught it: it folds ş→s and
    /// ğ→g, but ı (U+0131) is a distinct letter rather than an "i" wearing a mark, so nothing
    /// removes anything from it. Without the last line, someone on a US keyboard typing
    /// "ayaklanmasi" gets no results for "Kitlelerin Ayaklanması".
    private static func normalized(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "ı", with: "i")
    }
}
