import XCTest
@testable import KindleWall

/// The parser is the app's only door for user data, and the data comes from a device we do not
/// control. Every case here is something a real `My Clippings.txt` can contain — Kindle writes
/// UTF-8 with a BOM and CRLF line endings, users copy files between machines, and a highlight can
/// hold any character a book can. None of it may crash, and none of it may silently lose a
/// clipping that should have parsed.
final class ClippingsParserRobustnessTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KindleWallParser-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Helpers

    private func write(_ contents: String, encoding: String.Encoding = .utf8) throws -> URL {
        let url = directory.appendingPathComponent("My Clippings.txt")
        try contents.data(using: encoding)!.write(to: url)
        return url
    }

    private func writeRaw(_ data: Data) throws -> URL {
        let url = directory.appendingPathComponent("My Clippings.txt")
        try data.write(to: url)
        return url
    }

    private func entry(title: String = "Atomic Habits (James Clear)",
                       metadata: String = "- Your Highlight on page 23 | location 340-342 | Added on Monday, January 15, 2024 10:30:22 AM",
                       text: String) -> String {
        "\(title)\n\(metadata)\n\n\(text)\n==========\n"
    }

    // MARK: - Degenerate input

    func test_emptyFile_parsesToNothingRatherThanThrowing() throws {
        let url = try write("")
        XCTAssertEqual(try ClippingsParser().parse(fileURL: url).count, 0)
    }

    func test_fileOfOnlySeparators_parsesToNothing() throws {
        let url = try write(String(repeating: "==========\n", count: 50))
        XCTAssertEqual(try ClippingsParser().parse(fileURL: url).count, 0)
    }

    func test_entryTooShortToBeAClipping_isSkippedNotCrashed() throws {
        // Title and metadata but no highlight body — Kindle writes these when a note is deleted.
        let url = try write("Atomic Habits (James Clear)\n- Your Highlight on page 23\n==========\n")
        XCTAssertEqual(try ClippingsParser().parse(fileURL: url).count, 0)
    }

    func test_whitespaceOnlyHighlight_isDropped() throws {
        let url = try write(entry(text: "   \n\t  "))
        XCTAssertEqual(try ClippingsParser().parse(fileURL: url).count, 0)
    }

    func test_missingTrailingSeparator_stillYieldsTheLastClipping() throws {
        // A file that was truncated mid-write, or hand-edited.
        let url = try write("Atomic Habits (James Clear)\n"
                            + "- Your Highlight on page 23 | location 340-342 | Added on Monday, January 15, 2024 10:30:22 AM\n\n"
                            + "Habits are the compound interest of self-improvement.")
        XCTAssertEqual(try ClippingsParser().parse(fileURL: url).count, 1)
    }

    // MARK: - What real Kindle files actually contain

    func test_crlfLineEndings_parseIdenticallyToLf() throws {
        let lf = entry(text: "Systems beat goals.")
        let lfURL = try write(lf)
        let lfResult = try ClippingsParser().parse(fileURL: lfURL)

        let crlfURL = try write(lf.replacingOccurrences(of: "\n", with: "\r\n"))
        let crlfResult = try ClippingsParser().parse(fileURL: crlfURL)

        XCTAssertEqual(lfResult.count, 1)
        XCTAssertEqual(crlfResult.count, 1)
        // Identical content must produce the identical deterministic ID, or a user who moves a
        // file between machines loses every favourite.
        XCTAssertEqual(crlfResult.first?.id, lfResult.first?.id)
        XCTAssertEqual(crlfResult.first?.bookTitle, "Atomic Habits")
        XCTAssertEqual(crlfResult.first?.page, "23")
    }

    func test_byteOrderMark_doesNotLeakIntoTheFirstBookTitle() throws {
        // Kindle writes UTF-8 with a BOM; left in place it becomes an invisible prefix on the
        // first book's title, which then sorts oddly and never matches the same book elsewhere.
        let url = try write("\u{FEFF}" + entry(text: "Every action is a vote."))
        let result = try ClippingsParser().parse(fileURL: url)
        XCTAssertEqual(result.first?.bookTitle, "Atomic Habits")
    }

    func test_turkishFormat_isParsedWithPageAndAuthor() throws {
        let url = try write(entry(
            title: "Kürk Mantolu Madonna (Sabahattin Ali)",
            metadata: "- 45. sayfadaki vurgulama | konum 512-514 | Eklenme Tarihi: 15 Ocak 2024 Pazartesi 10:30:22",
            text: "İnsanlar birbirini tanımaktan niçin bu kadar kaçarlar?"
        ))
        let result = try ClippingsParser().parse(fileURL: url)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.bookTitle, "Kürk Mantolu Madonna")
        XCTAssertEqual(result.first?.author, "Sabahattin Ali")
        XCTAssertEqual(result.first?.page, "45")
    }

    func test_titleWithParenthesesInIt_takesTheLastPairAsTheAuthor() throws {
        let url = try write(entry(
            title: "Slaughterhouse-Five (or The Children's Crusade) (Kurt Vonnegut)",
            text: "So it goes."
        ))
        let result = try ClippingsParser().parse(fileURL: url)
        XCTAssertEqual(result.first?.author, "Kurt Vonnegut")
        XCTAssertEqual(result.first?.bookTitle, "Slaughterhouse-Five (or The Children's Crusade)")
    }

    func test_titleWithoutAnAuthor_keepsTheWholeLineAsTheTitle() throws {
        let url = try write(entry(title: "Untitled Manuscript", text: "A line worth keeping."))
        let result = try ClippingsParser().parse(fileURL: url)
        XCTAssertEqual(result.first?.bookTitle, "Untitled Manuscript")
        XCTAssertNil(result.first?.author)
    }

    func test_bookmarksAndNotesAreFilteredOutButHighlightsSurvive() throws {
        let contents =
            entry(metadata: "- Your Bookmark on page 12 | location 100 | Added on Monday, January 15, 2024 10:30:22 AM",
                  text: "bookmark body")
            + entry(metadata: "- Your Note on page 13 | location 110 | Added on Monday, January 15, 2024 10:31:22 AM",
                    text: "a note to self")
            + entry(text: "the only highlight")
        let url = try write(contents)
        let result = try ClippingsParser().parse(fileURL: url)
        XCTAssertEqual(result.map(\.text), ["the only highlight"])
    }

    func test_theSameHighlightTwice_isKeptOnce() throws {
        // Kindle appends rather than rewrites, so re-syncing a device duplicates entries.
        let url = try write(entry(text: "Repeated wisdom.") + entry(text: "REPEATED WISDOM.")
                            + entry(text: "Something else."))
        let result = try ClippingsParser().parse(fileURL: url)
        XCTAssertEqual(result.count, 2, "dedup is case-insensitive on trimmed text")
    }

    func test_metadataLineInAnUnknownFormat_stillKeepsTheHighlight() throws {
        // A future Kindle firmware, or a locale we have no pattern for. Losing the page number
        // is acceptable; losing the highlight is not.
        let url = try write(entry(metadata: "- Markering på sidan 12 | tillagd 15 januari 2024",
                                  text: "A highlight in an unsupported locale."))
        let result = try ClippingsParser().parse(fileURL: url)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.text, "A highlight in an unsupported locale.")
    }

    func test_multiLineHighlight_keepsEveryLine() throws {
        let url = try write(entry(text: "First line.\nSecond line.\nThird line."))
        let result = try ClippingsParser().parse(fileURL: url)
        XCTAssertEqual(result.first?.text, "First line.\nSecond line.\nThird line.")
    }

    // MARK: - Hostile input

    func test_fileThatIsNotUtf8_failsWithOurErrorRatherThanCrashing() throws {
        // A Latin-1 file with a high byte: not valid UTF-8. The user must get a message, not a
        // trap. 0xFF is never a legal UTF-8 lead byte.
        let url = try writeRaw(Data([0x41, 0x42, 0xFF, 0xFE, 0x43]))
        XCTAssertThrowsError(try ClippingsParser().parse(fileURL: url)) { error in
            guard case KindleWallError.fileReadFailed = error else {
                return XCTFail("beklenen fileReadFailed, gelen: \(error)")
            }
        }
    }

    func test_missingFile_failsWithOurErrorRatherThanCrashing() throws {
        let url = directory.appendingPathComponent("does-not-exist.txt")
        XCTAssertThrowsError(try ClippingsParser().parse(fileURL: url)) { error in
            guard case KindleWallError.fileReadFailed = error else {
                return XCTFail("beklenen fileReadFailed, gelen: \(error)")
            }
        }
    }

    func test_veryLongSingleHighlight_isParsedWhole() throws {
        // A user highlighting an entire chapter. Nothing may truncate it silently.
        let long = String(repeating: "kelime ", count: 20_000).trimmed
        let url = try write(entry(text: long))
        let result = try ClippingsParser().parse(fileURL: url)
        XCTAssertEqual(result.first?.text.count, long.count)
    }

    // MARK: - Async variant

    @MainActor
    func test_asyncParse_reportsProgressAndMatchesTheSyncResult() async throws {
        let contents = (0..<300).map { entry(text: "Highlight number \($0).") }.joined()
        let url = try write(contents)

        let syncResult = try ClippingsParser().parse(fileURL: url)

        let progress = Progress()
        let asyncResult = try await ClippingsParser().parse(fileURL: url) { fraction, _ in
            progress.record(fraction)
        }

        XCTAssertEqual(asyncResult.map(\.id), syncResult.map(\.id),
                       "iki yol aynı dosyada aynı sonucu vermeli")
        XCTAssertGreaterThan(progress.count, 1, "ilerleme en az bir kez raporlanmalı")
        XCTAssertTrue(progress.isMonotonic, "ilerleme geri gitmemeli")
        XCTAssertTrue(progress.isWithinUnitRange, "ilerleme 0…1 aralığında kalmalı")
    }

    func test_asyncParse_stopsWhenTheTaskIsCancelled() async throws {
        let contents = (0..<5_000).map { entry(text: "Highlight number \($0).") }.joined()
        let url = try write(contents)

        let task = Task { try await ClippingsParser().parse(fileURL: url) { _, _ in } }
        task.cancel()

        do {
            _ = try await task.value
            // Cancellation is checked every 50 entries, so a very fast machine may finish the
            // whole file first. Completing is acceptable; hanging or crashing is not.
        } catch is CancellationError {
            // Expected on any machine that has not already finished.
        }
    }

    /// Collects progress callbacks so the assertions can talk about the sequence, not one value.
    @MainActor
    private final class Progress {
        private var values: [Double] = []
        var count: Int { values.count }
        var isMonotonic: Bool { zip(values, values.dropFirst()).allSatisfy { $0 <= $1 } }
        var isWithinUnitRange: Bool { values.allSatisfy { $0 >= 0 && $0 <= 1 } }
        func record(_ value: Double) { values.append(value) }
    }
}
