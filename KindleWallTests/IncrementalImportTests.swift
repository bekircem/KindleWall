import XCTest
@testable import KindleWall

/// Re-importing `My Clippings.txt` after more reading.
///
/// The Kindle appends to that file as you highlight, so the copy the app imported last month
/// is not the copy on the device today. Re-reading it must add only what is new and say what
/// it added — and in particular must tell a *new book* apart from a *new highlight in a book
/// you already had*. That second number was wrong: it was measured against the in-memory
/// library, which at launch holds only manually added quotes, so any book that gained a
/// highlight was announced as new.
@MainActor
final class IncrementalImportTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var dir: URL!

    private struct Entry {
        let book: String
        let author: String
        let text: String
    }

    private static let atomic = Entry(book: "Atomic Habits", author: "James Clear",
                                      text: "Every action you take is a vote for the type of person you wish to become.")
    private static let meditations = Entry(book: "Meditations", author: "Marcus Aurelius",
                                           text: "You have power over your mind - not outside events.")
    /// A second highlight in a book the library already has.
    private static let atomicAgain = Entry(book: "Atomic Habits", author: "James Clear",
                                           text: "You do not rise to the level of your goals, you fall to the level of your systems.")
    /// A book that has never been imported before.
    private static let walden = Entry(book: "Walden", author: "Henry David Thoreau",
                                      text: "I went to the woods because I wished to live deliberately.")

    private func write(_ entries: [Entry]) throws -> URL {
        let url = dir.appendingPathComponent("My Clippings.txt")
        let body = entries.map { entry in
            """
            \(entry.book) (\(entry.author))
            - Your Highlight on page 23 | location 340-342 | Added on Monday, January 15, 2024 10:30:22 AM

            \(entry.text)
            ==========
            """
        }.joined(separator: "\n")
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    override func setUp() async throws {
        suiteName = TestDefaults.makeSuiteName("incremental")
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KindleWallIncremental-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: Constants.Paths.localClippingsFile)
    }

    override func tearDown() async throws {
        TestDefaults.destroy(suiteNamed: suiteName, defaults: defaults)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.removeItem(at: Constants.Paths.localClippingsFile)
        dir = nil
    }

    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 15) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    /// Runs one import to completion and hands back its summary.
    @discardableResult
    private func importing(_ entries: [Entry], into viewModel: MainViewModel) throws -> ImportSummary {
        let url = try write(entries)
        viewModel.importState.summary = nil
        viewModel.importClippings(from: url, announce: true)
        XCTAssertTrue(waitUntil { viewModel.importState.summary != nil && !viewModel.importState.isRunning },
                      "import did not finish")
        return try XCTUnwrap(viewModel.importState.summary)
    }

    // MARK: - The counts

    func test_firstImport_countsEverythingAsNew() throws {
        let viewModel = MainViewModel(storage: StorageService(defaults: defaults))

        let summary = try importing([Self.atomic, Self.meditations], into: viewModel)

        XCTAssertEqual(summary.newClippings, 2)
        XCTAssertEqual(summary.newBooks, 2)
        XCTAssertEqual(summary.totalClippings, 2)
        XCTAssertFalse(summary.foundNothingNew)
        XCTAssertTrue(summary.booksWithNewClippings.allSatisfy(\.isNewBook))
    }

    /// The ordinary case: the user has not read anything since last time.
    func test_reimportingAnUnchangedFile_findsNothingNew() throws {
        let storage = StorageService(defaults: defaults)
        let viewModel = MainViewModel(storage: storage)
        try importing([Self.atomic, Self.meditations], into: viewModel)

        let second = try importing([Self.atomic, Self.meditations], into: viewModel)

        XCTAssertTrue(second.foundNothingNew)
        XCTAssertEqual(second.newClippings, 0)
        XCTAssertEqual(second.newBooks, 0)
        XCTAssertTrue(second.booksWithNewClippings.isEmpty)
        XCTAssertEqual(second.totalClippings, 2, "the library is still whole")
    }

    /// The regression. A new highlight in a book already in the library is not a new book.
    func test_newHighlightInAnExistingBook_isNotANewBook() throws {
        let viewModel = MainViewModel(storage: StorageService(defaults: defaults))
        try importing([Self.atomic, Self.meditations], into: viewModel)

        let second = try importing([Self.atomic, Self.meditations, Self.atomicAgain], into: viewModel)

        XCTAssertEqual(second.newClippings, 1)
        XCTAssertEqual(second.newBooks, 0, "Atomic Habits was already in the library")
        XCTAssertEqual(second.booksWithNewClippings.map(\.bookTitle), ["Atomic Habits"])
        XCTAssertEqual(second.booksWithNewClippings.first?.isNewBook, false)
    }

    func test_aBookNeverSeenBefore_countsAsNew() throws {
        let viewModel = MainViewModel(storage: StorageService(defaults: defaults))
        try importing([Self.atomic], into: viewModel)

        let second = try importing([Self.atomic, Self.walden], into: viewModel)

        XCTAssertEqual(second.newClippings, 1)
        XCTAssertEqual(second.newBooks, 1)
        XCTAssertEqual(second.booksWithNewClippings.first?.bookTitle, "Walden")
        XCTAssertEqual(second.booksWithNewClippings.first?.isNewBook, true)
    }

    /// Both at once, which is what a month of reading actually looks like.
    func test_mixedImport_separatesNewBooksFromNewHighlights() throws {
        let viewModel = MainViewModel(storage: StorageService(defaults: defaults))
        try importing([Self.atomic], into: viewModel)

        let second = try importing([Self.atomic, Self.atomicAgain, Self.walden], into: viewModel)

        XCTAssertEqual(second.newClippings, 2)
        XCTAssertEqual(second.newBooks, 1)
        XCTAssertEqual(Set(second.booksWithNewClippings.map(\.bookTitle)), ["Atomic Habits", "Walden"])
        let walden = second.booksWithNewClippings.first { $0.bookTitle == "Walden" }
        XCTAssertEqual(walden?.isNewBook, true)
        let habits = second.booksWithNewClippings.first { $0.bookTitle == "Atomic Habits" }
        XCTAssertEqual(habits?.isNewBook, false)
    }

    // MARK: - Persistence

    /// The launch case: a fresh view model whose in-memory library starts empty must still
    /// know which books it has already seen.
    func test_knownBooksSurviveANewViewModel() throws {
        let storage = StorageService(defaults: defaults)
        let first = MainViewModel(storage: storage)
        try importing([Self.atomic, Self.meditations], into: first)

        let second = MainViewModel(storage: StorageService(defaults: defaults))
        let summary = try importing([Self.atomic, Self.meditations, Self.atomicAgain], into: second)

        XCTAssertEqual(summary.newClippings, 1)
        XCTAssertEqual(summary.newBooks, 0,
                       "a relaunch must not turn every book that gained a highlight into a new one")
    }

    /// Upgrading from a build that persisted IDs but no titles. The titles are derived from
    /// the clippings the ID set already vouches for, so the first check after upgrading does
    /// not announce the whole library as new.
    func test_installWithIDsButNoTitles_doesNotReportOldBooksAsNew() throws {
        let storage = StorageService(defaults: defaults)
        let viewModel = MainViewModel(storage: storage)
        try importing([Self.atomic, Self.meditations], into: viewModel)

        // Exactly the state an older install is in.
        storage.knownBookTitles = []
        XCTAssertFalse(storage.persistedClippingIDs.isEmpty)

        let summary = try importing([Self.atomic, Self.meditations, Self.atomicAgain], into: viewModel)

        XCTAssertEqual(summary.newClippings, 1)
        XCTAssertEqual(summary.newBooks, 0)
    }

    // MARK: - Who gets told

    /// A launch import refreshes the library without interrupting; only an import the user
    /// asked for reports back.
    func test_launchImportDoesNotAnnounce_butACheckDoes() throws {
        let storage = StorageService(defaults: defaults)
        let viewModel = MainViewModel(storage: storage)
        let url = try write([Self.atomic])
        viewModel.importClippings(from: url, announce: true)
        XCTAssertTrue(waitUntil { !viewModel.importState.isRunning })

        viewModel.loadClippings()
        XCTAssertTrue(waitUntil { !viewModel.importState.isRunning })
        XCTAssertFalse(viewModel.importState.announcesResult, "the launch import must stay quiet")

        viewModel.checkForNewClippings()
        XCTAssertTrue(waitUntil { !viewModel.importState.isRunning })
        XCTAssertTrue(viewModel.importState.announcesResult, "the user pressed a button and is owed an answer")
    }

    func test_checkIsOfferedOnlyWhenThereIsAFileToReread() throws {
        let storage = StorageService(defaults: defaults)
        let viewModel = MainViewModel(storage: storage)
        XCTAssertFalse(viewModel.canCheckForNewClippings)

        try importing([Self.atomic], into: viewModel)

        XCTAssertTrue(viewModel.canCheckForNewClippings)
    }
}
