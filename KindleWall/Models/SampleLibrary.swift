import Foundation

/// A handful of public-domain highlights used to get someone through setup without a Kindle
/// plugged in.
///
/// First launch used to be a dead end: both "Next" and "Begin" were disabled until a
/// `My Clippings.txt` was chosen, so anyone whose device was elsewhere could not reach the app
/// at all — not even to look at it. These give the design step something real to render and
/// leave a working wallpaper behind.
///
/// Titles and passages are localized: an English reader should meet the English original, not
/// a Turkish translation of it. Note that this changes their deterministic IDs, so someone who
/// seeded the samples before 1.1 keeps the old copies — acceptable for a starter set that can
/// be deleted one by one from the library.
enum SampleLibrary {
    static let clippings: [Clipping] = [
        make(
            book: String(localized: "Crime and Punishment"), author: "Fyodor Dostoyevsky",
            text: String(localized: "Taking a new step, uttering a new word, is what people fear most.")
        ),
        make(
            book: String(localized: "Moby-Dick"), author: "Herman Melville",
            text: String(localized: "It is better to sail in an unknown sea than to rot in a known harbor.")
        ),
        make(
            book: String(localized: "A Tale of Two Cities"), author: "Charles Dickens",
            text: String(localized: "It was the best of times, it was the worst of times, it was the age of wisdom, it was the age of foolishness.")
        ),
        make(
            book: String(localized: "Pride and Prejudice"), author: "Jane Austen",
            text: String(localized: "There is a very fine line between vanity and pride.")
        ),
        make(
            book: String(localized: "Walden"), author: "Henry David Thoreau",
            text: String(localized: "I went to the woods because I wished to live deliberately, to front only the essential facts of life.")
        ),
        make(
            book: String(localized: "Meditations"), author: "Marcus Aurelius",
            text: String(localized: "The happiness of your life depends upon the quality of your thoughts.")
        ),
        make(
            book: String(localized: "Faust"), author: "Johann Wolfgang von Goethe",
            text: String(localized: "Man errs as long as he strives.")
        ),
        make(
            book: String(localized: "Essays"), author: "Michel de Montaigne",
            text: String(localized: "My life has been filled with terrible misfortune, most of which never happened.")
        )
    ]

    /// Deterministic IDs, so re-running setup does not duplicate them or lose their
    /// favourite/shown state — the same guarantee real imported clippings get.
    private static func make(book: String, author: String, text: String) -> Clipping {
        Clipping(
            id: Clipping.deterministicID(bookTitle: book, text: text),
            bookTitle: book,
            author: author,
            text: text,
            dateAdded: Date(),
            isManualEntry: true
        )
    }
}
