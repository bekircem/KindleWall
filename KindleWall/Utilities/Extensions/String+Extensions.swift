import Foundation

extension String {
    /// Uppercased in the locale the app is actually running in.
    ///
    /// This used to pin `tr_TR`, because Turkish capitalises "i" as "İ" and plain
    /// `uppercased()` turned "Stili" into "STILI" on every card header. That was right while
    /// the UI was Turkish whatever the user's region said, and wrong the moment the app also
    /// shipped in English. `Locale.current` follows the app's effective language, including a
    /// per-app override set in System Settings.
    var uppercasedForCurrentLocale: String {
        uppercased(with: Locale.current)
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
