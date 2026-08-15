import Foundation

// MARK: - Protocol

/// Protocol for parsing Kindle clippings files.
///
/// `Sendable` because importing hands the parser to a background task: parsing a large
/// My Clippings.txt on the main actor is exactly the freeze this app has been removing.
protocol ClippingsParserProtocol: Sendable {
    /// Parses the contents of a My Clippings.txt file and returns an array of clippings.
    /// - Parameter fileURL: The URL of the clippings file.
    /// - Returns: An array of parsed Clipping objects.
    /// - Throws: KindleWallError if the file cannot be read or parsed.
    func parse(fileURL: URL) throws -> [Clipping]

    /// Async variant with progress reporting for background imports.
    /// - Parameters:
    ///   - fileURL: The URL of the clippings file.
    ///   - progressHandler: Called periodically with (0.0–1.0 progress, current book title).
    /// - Returns: An array of parsed Clipping objects.
    func parse(
        fileURL: URL,
        progressHandler: @MainActor @Sendable (Double, String?) -> Void
    ) async throws -> [Clipping]
}

// MARK: - Implementation

/// Parses Kindle's My Clippings.txt format into structured Clipping objects.
final class ClippingsParser: ClippingsParserProtocol {
    private static let separator = "=========="

    /// Metadata-line patterns, built per parse call rather than stored.
    ///
    /// `Regex` is not `Sendable`. Held as a stored property — static or instance — it would make
    /// the parser itself unsendable, and the parser is handed to a background task on every
    /// import. Building them per call leaves the type with no shared state at all, so it is
    /// safe by construction instead of by assertion. The cost is five regex compilations per
    /// import, not per entry.
    private struct Patterns {
        let highlight = /- Your Highlight on(?: [Pp]age (\d+))?\s*\|?\s*(?:[Ll]ocation (\d+(?:-\d+)?))?\s*\|?\s*Added on (.+)/
        let note = /- Your Note on(?: [Pp]age (\d+))?\s*\|?\s*(?:[Ll]ocation (\d+(?:-\d+)?))?\s*\|?\s*Added on (.+)/
        let bookmark = /- Your Bookmark on(?: [Pp]age (\d+))?\s*\|?\s*(?:[Ll]ocation (\d+(?:-\d+)?))?\s*\|?\s*Added on (.+)/

        // Turkish equivalents
        let highlightTR = /- (\d+)\. sayfadaki vurgulama(?:\s*\|\s*konum (\d+(?:-\d+)?))?.+Eklenme Tarihi: (.+)/
        let noteTR = /- (\d+)\. sayfadaki not(?:\s*\|\s*konum (\d+(?:-\d+)?))?.+Eklenme Tarihi: (.+)/
    }

    func parse(fileURL: URL) throws -> [Clipping] {
        let content: String
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            throw KindleWallError.fileReadFailed(underlying: error)
        }

        let rawEntries = content.components(separatedBy: Self.separator)
        let patterns = Patterns()
        var clippings: [Clipping] = []
        var seenTexts: Set<String> = []

        for entry in rawEntries {
            guard let clipping = parseEntry(entry, patterns: patterns) else { continue }

            // Filter out bookmarks, notes, and empty texts — only highlights shown
            guard clipping.type != .bookmark, clipping.type != .note, !clipping.text.trimmed.isEmpty else { continue }

            // Deduplicate by text content
            let normalizedText = clipping.text.trimmed.lowercased()
            guard !seenTexts.contains(normalizedText) else { continue }

            seenTexts.insert(normalizedText)
            clippings.append(clipping)
        }

        return clippings
    }

    func parse(
        fileURL: URL,
        progressHandler: @MainActor @Sendable (Double, String?) -> Void
    ) async throws -> [Clipping] {
        let content: String
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            throw KindleWallError.fileReadFailed(underlying: error)
        }

        let rawEntries = content.components(separatedBy: Self.separator)
        let patterns = Patterns()
        let total = max(rawEntries.count, 1)
        var clippings: [Clipping] = []
        var seenTexts: Set<String> = []

        for (index, entry) in rawEntries.enumerated() {
            if index % 50 == 0 {
                try Task.checkCancellation()
                let progress = Double(index) / Double(total)
                let firstLine = entry.components(separatedBy: "\n")
                    .map { $0.trimmed }
                    .first(where: { !$0.isEmpty })
                await progressHandler(progress, firstLine)
            }

            guard let clipping = parseEntry(entry, patterns: patterns) else { continue }
            guard clipping.type != .bookmark, clipping.type != .note, !clipping.text.trimmed.isEmpty else { continue }

            let normalizedText = clipping.text.trimmed.lowercased()
            guard !seenTexts.contains(normalizedText) else { continue }

            seenTexts.insert(normalizedText)
            clippings.append(clipping)
        }

        return clippings
    }

    // MARK: - Private

    private func parseEntry(_ entry: String, patterns: Patterns) -> Clipping? {
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
        let metadata = parseMetadataLine(metadataLine, patterns: patterns)

        let id = Clipping.deterministicID(bookTitle: bookTitle, text: text)

        return Clipping(
            id: id,
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

    private func parseMetadataLine(_ line: String, patterns: Patterns) -> EntryMetadata {
        // Try English highlight pattern
        if let match = line.firstMatch(of: patterns.highlight) {
            return EntryMetadata(
                type: .highlight,
                page: match.1.map(String.init),
                location: match.2.map(String.init),
                date: parseDate(String(match.3))
            )
        }

        // Try English note pattern
        if let match = line.firstMatch(of: patterns.note) {
            return EntryMetadata(
                type: .note,
                page: match.1.map(String.init),
                location: match.2.map(String.init),
                date: parseDate(String(match.3))
            )
        }

        // Try English bookmark pattern
        if let match = line.firstMatch(of: patterns.bookmark) {
            return EntryMetadata(
                type: .bookmark,
                page: match.1.map(String.init),
                location: match.2.map(String.init),
                date: parseDate(String(match.3))
            )
        }

        // Try Turkish highlight pattern
        if let match = line.firstMatch(of: patterns.highlightTR) {
            return EntryMetadata(
                type: .highlight,
                page: String(match.1),
                location: match.2.map(String.init),
                date: parseDate(String(match.3))
            )
        }

        // Try Turkish note pattern
        if let match = line.firstMatch(of: patterns.noteTR) {
            return EntryMetadata(
                type: .note,
                page: String(match.1),
                location: match.2.map(String.init),
                date: parseDate(String(match.3))
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
