import Foundation

/// A handful of public-domain highlights used to get someone through setup without a Kindle
/// plugged in.
///
/// First launch used to be a dead end: both "İleri" and "Başla" were disabled until a
/// `My Clippings.txt` was chosen, so anyone whose device was elsewhere could not reach the app
/// at all — not even to look at it. These give the design step something real to render and
/// leave a working wallpaper behind.
enum SampleLibrary {
    static let clippings: [Clipping] = [
        make(
            book: "Suç ve Ceza", author: "Fyodor Dostoyevski",
            text: "Yeni bir adım atmak, yeni bir söz söylemek, insanların en çok korktuğu şeydir."
        ),
        make(
            book: "Moby Dick", author: "Herman Melville",
            text: "Bilmediğim bir denizde yol almak, bildiğim bir limanda çürümekten iyidir."
        ),
        make(
            book: "Bir Şehrin İki Hikâyesi", author: "Charles Dickens",
            text: "Zamanların en iyisiydi, zamanların en kötüsüydü; bilgelik çağıydı, aptallık çağıydı."
        ),
        make(
            book: "Gurur ve Önyargı", author: "Jane Austen",
            text: "İnsanın kendini beğenmesi ile gururlanması arasında çok ince bir çizgi vardır."
        ),
        make(
            book: "Walden", author: "Henry David Thoreau",
            text: "Ormana gittim, çünkü hayatı bilinçli yaşamak, yalnızca temel gerçeklerle yüzleşmek istiyordum."
        ),
        make(
            book: "Düşünceler", author: "Marcus Aurelius",
            text: "Hayatının mutluluğu, düşüncelerinin niteliğine bağlıdır."
        ),
        make(
            book: "Faust", author: "Johann Wolfgang von Goethe",
            text: "İnsan çabaladığı sürece yanılır."
        ),
        make(
            book: "Denemeler", author: "Michel de Montaigne",
            text: "Hayatım korkunç talihsizliklerle doluydu, çoğu hiç başıma gelmedi."
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
