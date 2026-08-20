import XCTest
@testable import KindleWall

/// The words the re-import banner puts on screen.
///
/// The phrasing lives on `ImportSummary` rather than in the view so it can be checked without
/// rendering anything — the previous version built its sentence inline and shipped two Turkish
/// literals inside it, `"\(n) yeni"` and `"%.1f sn"`, which showed up in the English build and
/// which no catalog audit could see.
@MainActor
final class ImportSummaryCopyTests: XCTestCase {

    private func summary(new: Int, newBooks: Int, books: [BookDelta]) -> ImportSummary {
        ImportSummary(totalClippings: 100, newClippings: new, totalBooks: 20,
                      newBooks: newBooks, duration: 0.5, booksWithNewClippings: books)
    }

    private func delta(_ title: String, _ count: Int, new: Bool = false) -> BookDelta {
        BookDelta(bookTitle: title, newClippings: count, isNewBook: new)
    }

    /// Every sentence carries at most one number, so each catalog entry needs one plural rule.
    /// A translator can read those; `"%lld new highlights from %lld books, %lld of them new"`
    /// they cannot.
    /// Substring matching would be useless here — "12 new highlights" contains "2" — so this
    /// pulls the digit groups out and compares them as numbers.
    private func numbers(in text: String) -> [String] {
        text.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
    }

    func test_headlineAndBooksLine_eachCarryOneCount() {
        let s = summary(new: 12, newBooks: 1, books: [delta("Sapiens", 8), delta("Walden", 4, new: true)])

        XCTAssertEqual(numbers(in: s.headline), ["12"],
                       "the headline carries the highlight count and nothing else")
        XCTAssertEqual(numbers(in: s.booksLine), ["2", "1"],
                       "the second line carries the book count, then how many of them are new")
    }

    /// Nothing new is its own sentence, not "0 new highlights".
    func test_nothingNew_saysSoPlainly() {
        let s = summary(new: 0, newBooks: 0, books: [])

        XCTAssertTrue(s.foundNothingNew)
        XCTAssertFalse(s.headline.contains("0"), "\"0 new highlights\" is not how a person says this")
    }

    /// No new books means no second clause; the line stays a single fact.
    func test_booksLine_omitsTheNewBookClauseWhenThereAreNone() {
        let s = summary(new: 3, newBooks: 0, books: [delta("Sapiens", 3)])

        XCTAssertFalse(s.booksLine.contains("·"),
                       "with nothing new to add the line must not carry an empty second half")
    }

    /// Somebody who has been reading for a month gets a banner, not a wall.
    func test_bookList_isCappedAndReportsTheRemainder() {
        let books = (1...9).map { delta("Book \($0)", 10 - $0) }
        let s = summary(new: 45, newBooks: 0, books: books)

        let (shown, hidden) = s.namedBooks
        XCTAssertEqual(shown.count, ImportSummary.namedBookLimit)
        XCTAssertEqual(hidden, 9 - ImportSummary.namedBookLimit)
        XCTAssertEqual(shown.first?.bookTitle, "Book 1", "the list keeps the order it was given")
    }

    /// Fewer books than the cap means nothing is hidden and no "and N more" line appears.
    func test_shortBookList_hidesNothing() {
        let s = summary(new: 5, newBooks: 0, books: [delta("Sapiens", 3), delta("Walden", 2)])

        let (shown, hidden) = s.namedBooks
        XCTAssertEqual(shown.count, 2)
        XCTAssertEqual(hidden, 0)
    }

    /// The banner's strings must come from the catalog, not from literals in the view. Checked
    /// through the built Turkish bundle, which is the only thing that proves the round trip.
    func test_bannerStrings_areTranslated() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "tr", ofType: "lproj"))
        let tr = try XCTUnwrap(Bundle(path: path))

        XCTAssertEqual(tr.localizedString(forKey: "No new highlights", value: nil, table: nil),
                       "Yeni alıntı yok")
        XCTAssertEqual(tr.localizedString(forKey: "Check for New Highlights", value: nil, table: nil),
                       "Yeni Alıntıları Denetle")
        XCTAssertEqual(tr.localizedString(forKey: "Your library is already up to date.", value: nil, table: nil),
                       "Kütüphanen zaten güncel.")
    }
}
