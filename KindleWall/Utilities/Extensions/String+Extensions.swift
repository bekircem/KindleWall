import Foundation

extension String {
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
