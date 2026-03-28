import Foundation

// MARK: - Protocol

/// Protocol for parsing Kindle clippings files.
protocol ClippingsParserProtocol {
    /// Parses the contents of a My Clippings.txt file and returns an array of clippings.
    /// - Parameter fileURL: The URL of the clippings file.
    /// - Returns: An array of parsed Clipping objects.
    /// - Throws: KindleWallError if the file cannot be read or parsed.
    func parse(fileURL: URL) throws -> [Clipping]
}

// MARK: - Implementation

/// Parses Kindle's My Clippings.txt format into structured Clipping objects.
final class ClippingsParser: ClippingsParserProtocol {
    private static let separator = "=========="

    // Regex patterns for metadata line
    private static let highlightPattern = /- Your Highlight on(?: page (\d+))?\s*\|?\s*(?:location (\d+(?:-\d+)?))?\s*\|?\s*Added on (.+)/
    private static let notePattern = /- Your Note on(?: page (\d+))?\s*\|?\s*(?:location (\d+(?:-\d+)?))?\s*\|?\s*Added on (.+)/
    private static let bookmarkPattern = /- Your Bookmark on(?: page (\d+))?\s*\|?\s*(?:location (\d+(?:-\d+)?))?\s*\|?\s*Added on (.+)/

    // Turkish equivalents
    private static let highlightPatternTR = /- (\d+)\. sayfadaki vurgulama.+Eklenme Tarihi: (.+)/
    private static let notePatternTR = /- (\d+)\. sayfadaki not.+Eklenme Tarihi: (.+)/

    func parse(fileURL: URL) throws -> [Clipping] {
        let content: String
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            throw KindleWallError.fileReadFailed(underlying: error)
        }

        let rawEntries = content.components(separatedBy: Self.separator)
        var clippings: [Clipping] = []
        var seenTexts: Set<String> = []

        for entry in rawEntries {
            guard let clipping = parseEntry(entry) else { continue }

            // Filter out bookmarks and empty texts
            guard clipping.type != .bookmark, !clipping.text.trimmed.isEmpty else { continue }

            // Deduplicate by text content
            let normalizedText = clipping.text.trimmed.lowercased()
            guard !seenTexts.contains(normalizedText) else { continue }

            seenTexts.insert(normalizedText)
            clippings.append(clipping)
        }

        return clippings
    }

    // MARK: - Private

    private func parseEntry(_ entry: String) -> Clipping? {
        let lines = entry.components(separatedBy: "\n")
            .map { $0.trimmed }
            .filter { !$0.isEmpty }

        // Need at least: book title line, metadata line, clipping text
        guard lines.count >= 3 else { return nil }

        let titleLine = lines[0]
        let metadataLine = lines[1]
        let text = lines.dropFirst(2).joined(separator: "\n").trimmed

        guard !text.isEmpty else { return nil }

        // Parse book title and author
        let (bookTitle, author) = parseTitleLine(titleLine)

        // Parse metadata (type, page, location, date)
        let metadata = parseMetadataLine(metadataLine)

        return Clipping(
            bookTitle: bookTitle,
            author: author,
            text: text,
            page: metadata.page,
            location: metadata.location,
            dateAdded: metadata.date,
            type: metadata.type
        )
    }

    private func parseTitleLine(_ line: String) -> (title: String, author: String?) {
        // Format: "Book Title (Author Name)" or just "Book Title"
        let cleaned = line.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}").union(.whitespacesAndNewlines))

        if let lastOpen = cleaned.lastIndex(of: "("),
           let lastClose = cleaned.lastIndex(of: ")"),
           lastOpen < lastClose {
            let title = String(cleaned[cleaned.startIndex..<lastOpen]).trimmed
            let author = String(cleaned[cleaned.index(after: lastOpen)..<lastClose]).trimmed
            return (title, author.nilIfEmpty)
        }

        return (cleaned, nil)
    }

    private struct EntryMetadata {
        let type: ClippingType
        let page: String?
        let location: String?
        let date: Date?
    }

    private func parseMetadataLine(_ line: String) -> EntryMetadata {
        // Try English highlight pattern
        if let match = line.firstMatch(of: Self.highlightPattern) {
            return EntryMetadata(
                type: .highlight,
                page: match.1.map(String.init),
                location: match.2.map(String.init),
                date: parseDate(String(match.3))
            )
        }

        // Try English note pattern
        if let match = line.firstMatch(of: Self.notePattern) {
            return EntryMetadata(
                type: .note,
                page: match.1.map(String.init),
                location: match.2.map(String.init),
                date: parseDate(String(match.3))
            )
        }

        // Try English bookmark pattern
        if let match = line.firstMatch(of: Self.bookmarkPattern) {
            return EntryMetadata(
                type: .bookmark,
                page: match.1.map(String.init),
                location: match.2.map(String.init),
                date: parseDate(String(match.3))
            )
        }

        // Try Turkish highlight pattern
        if let match = line.firstMatch(of: Self.highlightPatternTR) {
            return EntryMetadata(
                type: .highlight,
                page: String(match.1),
                location: nil,
                date: parseDate(String(match.2))
            )
        }

        // Try Turkish note pattern
        if let match = line.firstMatch(of: Self.notePatternTR) {
            return EntryMetadata(
                type: .note,
                page: String(match.1),
                location: nil,
                date: parseDate(String(match.2))
            )
        }

        // Fallback: treat as highlight with no metadata
        return EntryMetadata(type: .highlight, page: nil, location: nil, date: nil)
    }

    private func parseDate(_ dateString: String) -> Date? {
        let trimmed = dateString.trimmed
        let formatters = Self.dateFormatters
        for formatter in formatters {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }

    private static let dateFormatters: [DateFormatter] = {
        let formats = [
            "EEEE, MMMM d, yyyy h:mm:ss a",    // English: Monday, January 15, 2024 10:30:22 AM
            "EEEE, d MMMM yyyy h:mm:ss a",      // English alt
            "EEEE, MMMM d, yyyy HH:mm:ss",      // English 24h
            "d MMMM yyyy EEEE HH:mm:ss",        // Turkish: 15 Ocak 2024 Pazartesi 10:30:22
        ]

        let locales = [
            Locale(identifier: "en_US"),
            Locale(identifier: "tr_TR"),
        ]

        var formatters: [DateFormatter] = []
        for format in formats {
            for locale in locales {
                let formatter = DateFormatter()
                formatter.dateFormat = format
                formatter.locale = locale
                formatters.append(formatter)
            }
        }
        return formatters
    }()
}
