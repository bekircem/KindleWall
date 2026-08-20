import Foundation

extension String {
    /// Uppercases with Turkish casing rules, so "i" becomes "İ" and not "I".
    ///
    /// The locale is pinned rather than taken from the system: the UI is Turkish whatever the
    /// user's region is set to, and plain `uppercased()` turned "Wallpaper Style" into
    /// "DUVAR KAĞIDI STILI" on every card header in the app.
    var uppercasedTurkish: String {
        uppercased(with: Locale(identifier: "tr_TR"))
    }

    /// Trims whitespace and newlines from both ends of the string.
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns nil if the string is empty after trimming, otherwise returns the trimmed string.
    var nilIfEmpty: String? {
        let trimmed = self.trimmed
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Truncates the string to the specified length, appending an ellipsis if needed.
    func truncated(to maxLength: Int) -> String {
        if count <= maxLength { return self }
        let index = self.index(startIndex, offsetBy: maxLength - 1)
        return String(self[...index]) + "…"
    }
}
