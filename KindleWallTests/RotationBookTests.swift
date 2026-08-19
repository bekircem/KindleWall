import XCTest
@testable import KindleWall

/// Pins the two things the rotation scope UI now depends on: per-book quote counts, and a
/// search that survives Turkish typing.
@MainActor
final class RotationBookTests: XCTestCase {

    /// Isolated defaults so the suite never writes to the machine running it — via the
    /// project's `TestDefaults`, which also handles the plist that `cfprefsd` recreates.
    private let suiteName = TestDefaults.makeSuiteName("RotationBook")
    private var defaults: UserDefaults!

    // The async variants, not `setUpWithError`/`tearDown`: an override of a nonisolated
    // superclass method stays nonisolated even inside a `@MainActor` class, so the
    // synchronous forms cannot touch `defaults`. Every other suite here uses these.
    override func setUp() async throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        TestDefaults.destroy(suiteNamed: suiteName, defaults: defaults)
        defaults = nil
    }

    private func makeViewModel() -> MainViewModel {
        MainViewModel(storage: StorageService(defaults: defaults))
    }

    private func book(_ title: String, author: String? = nil, count: Int = 1) -> RotationBook {
        RotationBook(title: title, author: author, quoteCount: count)
    }

    // MARK: - Search

    func test_matches_isCaseInsensitive() {
        XCTAssertTrue(book("Sisifos Söyleni").matches("sisifos"))
        XCTAssertTrue(book("Sisifos Söyleni").matches("SÖYLENI"))
    }

    /// The reason `matches` exists rather than a bare `localizedCaseInsensitiveContains`:
    /// a Turkish keyboard is not a given, and "sifrepunk" must find "Şifrepunk".
    func test_matches_ignoresTurkishDiacritics() {
        XCTAssertTrue(book("Şifrepunk").matches("sifrepunk"))
        XCTAssertTrue(book("Yaşam Bilgeliği").matches("yasam"))
        XCTAssertTrue(book("Kitlelerin Ayaklanması").matches("ayaklanmasi"))
        XCTAssertTrue(book("Hayatın Kaynağı").matches("hayatin kaynagi"))
        // And the reverse direction: a Turkish keyboard searching an ASCII title.
        XCTAssertTrue(book("Cypherpunk").matches("cypherpunk"))
    }

    /// Folding must not turn search into a free-for-all — unrelated books still miss.
    func test_matches_doesNotOverMatch() {
        XCTAssertFalse(book("Şifrepunk", author: "Julian Assange").matches("sisifos"))
        XCTAssertFalse(book("Hayatın Kaynağı").matches("kaynaksiz"))
    }

    func test_matches_searchesAuthorToo() {
        let b = book("Sisifos Söyleni", author: "Albert Camus")
        XCTAssertTrue(b.matches("camus"))
        XCTAssertFalse(b.matches("kafka"))
    }

    func test_matches_emptyQueryMatchesEverything() {
        XCTAssertTrue(book("Herhangi").matches(""))
    }

    // MARK: - Counts

    /// Counts are what make pinning an informed choice, so they must follow the clippings.
    func test_availableBooks_carriesPerBookQuoteCounts() {
        let vm = makeViewModel()
        vm.clippings = [
            Clipping(bookTitle: "A", author: "Yazar A", text: "bir"),
            Clipping(bookTitle: "A", author: "Yazar A", text: "iki"),
            Clipping(bookTitle: "A", author: "Yazar A", text: "üç"),
            Clipping(bookTitle: "B", author: "Yazar B", text: "tek"),
        ]

        let books = vm.availableBooks
        XCTAssertEqual(books.count, 2)
        XCTAssertEqual(books.first { $0.title == "A" }?.quoteCount, 3)
        XCTAssertEqual(books.first { $0.title == "B" }?.quoteCount, 1)
        XCTAssertEqual(books.first { $0.title == "A" }?.author, "Yazar A")
    }

    func test_availableBooks_isSortedByTitle() {
        let vm = makeViewModel()
        vm.clippings = [
            Clipping(bookTitle: "Zeplin", author: nil, text: "z"),
            Clipping(bookTitle: "Adalet", author: nil, text: "a"),
        ]
        XCTAssertEqual(vm.availableBooks.map(\.title), ["Adalet", "Zeplin"])
    }
}
