import Foundation
import Observation

/// Tracks the phase and progress of a clippings file import.
@Observable
final class ImportState {
    var phase: ImportPhase = .idle
    var progress: Double = 0.0
    var currentBook: String? = nil
    var summary: ImportSummary? = nil

    /// Whether a finished import should report itself on screen.
    ///
    /// The app re-reads `My Clippings.txt` on every launch, so without this the user was
    /// shown a completion banner every single time they opened the window — including the
    /// overwhelmingly common case where nothing had changed. A launch import now refreshes
    /// the library silently; only an import the user asked for reports back. Failures are
    /// announced either way: an import that could not run is worth interrupting for.
    var announcesResult: Bool = false

    var isRunning: Bool { phase == .running }
}

/// The discrete phases of an import operation.
enum ImportPhase: Equatable {
    case idle
    case running
    case completed
    case failed(String)
}

/// One book's share of an import's new highlights.
struct BookDelta: Equatable, Identifiable {
    let bookTitle: String
    let newClippings: Int
    /// True when the book itself had never been imported before, as opposed to an old book
    /// that gained highlights. The distinction is the whole point of the re-import summary.
    let isNewBook: Bool

    var id: String { bookTitle }
}

/// Statistics shown to the user after an import completes.
struct ImportSummary: Equatable {
    let totalClippings: Int
    let newClippings: Int
    let totalBooks: Int
    let newBooks: Int
    let duration: TimeInterval
    /// Books that gained highlights, most first. Empty when the import found nothing new.
    let booksWithNewClippings: [BookDelta]

    /// Nothing changed since the last import — the ordinary outcome of re-reading a file
    /// the Kindle has not touched.
    var foundNothingNew: Bool { newClippings == 0 }

    /// How many books the banner names before it starts counting them instead.
    static let namedBookLimit = 4

    /// The banner's first line.
    ///
    /// The phrasing lives here rather than in the view so it can be tested without rendering
    /// anything. One count per string on purpose: a sentence carrying two or three numbers
    /// needs a plural rule for each, and the catalog entry stops being something a translator
    /// can read.
    var headline: String {
        foundNothingNew
            ? String(localized: "No new highlights")
            : String(localized: "\(newClippings) new highlights")
    }

    /// The banner's second line: how the new highlights are spread across books.
    var booksLine: String {
        let books = String(localized: "in \(booksWithNewClippings.count) books")
        guard newBooks > 0 else { return books }
        return books + " · " + String(localized: "\(newBooks) new books")
    }

    /// The books the banner names, and how many it had to leave out.
    var namedBooks: (shown: [BookDelta], hidden: Int) {
        let shown = Array(booksWithNewClippings.prefix(Self.namedBookLimit))
        return (shown, booksWithNewClippings.count - shown.count)
    }
}
