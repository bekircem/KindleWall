import AppKit
import Observation

// MARK: - Protocol

@MainActor
protocol BookCoverServiceProtocol: AnyObject {
    /// Currently loaded covers keyed by book title (Book.id). Observable — UI updates automatically.
    var loadedCovers: [String: NSImage] { get }
    /// Returns a cover for the book. Loads from cache or starts a background fetch.
    @discardableResult
    func cover(for book: Book) async -> NSImage?
    /// Bypasses all caches and re-fetches from the network.
    @discardableResult
    func refreshCover(for book: Book) async -> NSImage?
    /// Fire-and-forget: starts background fetches for the given books (non-async).
    func prefetch(books: [Book])
}

// MARK: - Implementation

/// Fetches and caches book cover images from Google Books and Open Library.
///
/// **Thread safety:** `@MainActor` ensures all state mutations happen on the main actor.
/// URLSession `await` calls suspend without blocking the main thread (Swift structured concurrency).
///
/// Resolution order per book:
///   1. Memory cache (`loadedCovers`)
///   2. Disk cache (`~/...KindleWall/covers/`)
///   3. Google Books API (language-restricted for correct edition)
///   4. Open Library API (fallback)
///   5. nil → caller shows gradient+initials placeholder
@MainActor
@Observable
final class BookCoverService: BookCoverServiceProtocol {

    // MARK: - Observable state (main actor protected)

    private(set) var loadedCovers: [String: NSImage] = [:]

    // MARK: - Private state (main actor protected)

    /// Tracks books currently being fetched to prevent duplicate network requests.
    private var inFlight: Set<String> = []

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        return URLSession(configuration: config)
    }()

    // MARK: - Public interface

    func cover(for book: Book) async -> NSImage? {
        let key = cacheKey(for: book.title)

        // 1. Memory cache
        if let cached = loadedCovers[book.id] { return cached }

        // 2. Disk cache (synchronous read — fast, file is small JPEG)
        if let disk = loadFromDisk(key: key) {
            loadedCovers[book.id] = disk
            return disk
        }

        // 3. Network fetch — guard against duplicate in-flight requests.
        // Safe: inFlight is on @MainActor, no concurrent mutation possible.
        guard !inFlight.contains(key) else { return nil }
        inFlight.insert(key)

        let image = await fetchAndCache(book: book, key: key)

        inFlight.remove(key)
        if let image {
            loadedCovers[book.id] = image
        }
        return image
    }

    func refreshCover(for book: Book) async -> NSImage? {
        let key = cacheKey(for: book.title)
        deleteDiskCache(key: key)
        loadedCovers.removeValue(forKey: book.id)
        inFlight.remove(key)
        return await cover(for: book)
    }

    /// Starts background fetches for books that don't have a cover yet.
    /// Non-async: returns immediately, tasks run concurrently in the background.
    func prefetch(books: [Book]) {
        for book in books.prefix(20) where loadedCovers[book.id] == nil {
            Task { await cover(for: book) }
        }
    }

    // MARK: - Fetch pipeline

    private func fetchAndCache(book: Book, key: String) async -> NSImage? {
        let lang = detectLanguage(from: book.title)

        // Try Google Books, fall back to Open Library
        var image = await fetchFromGoogleBooks(title: book.title, author: book.author, lang: lang)
        if image == nil {
            image = await fetchFromOpenLibrary(title: book.title, author: book.author)
        }

        if let image {
            saveToDisk(image: image, key: key)
        }
        return image
    }

    // MARK: - Google Books API

    private func fetchFromGoogleBooks(title: String, author: String?, lang: String?) async -> NSImage? {
        var query = "intitle:\"\(title)\""
        if let author, !author.isEmpty {
            query += "+inauthor:\"\(author)\""
        }

        guard var components = URLComponents(string: "https://www.googleapis.com/books/v1/volumes") else {
            return nil
        }
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: "3"),
            URLQueryItem(name: "fields", value: "items(volumeInfo/imageLinks,volumeInfo/language)")
        ]
        if let lang {
            queryItems.append(URLQueryItem(name: "langRestrict", value: lang))
        }
        components.queryItems = queryItems

        guard let url = components.url else { return nil }

        do {
            let (data, _) = try await session.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else { return nil }

            // Prefer language-matched result, fall back to first
            let candidates: [(lang: String?, thumbURL: String?)] = items.compactMap { item in
                let info = item["volumeInfo"] as? [String: Any]
                let itemLang = info?["language"] as? String
                let links = info?["imageLinks"] as? [String: Any]
                let thumb = (links?["extraLarge"] ?? links?["large"] ?? links?["medium"] ?? links?["thumbnail"]) as? String
                return (itemLang, thumb)
            }

            let best = candidates.first(where: { $0.lang == lang }) ?? candidates.first
            guard var thumbURL = best?.thumbURL else { return nil }

            // Force HTTPS (Google returns http)
            thumbURL = thumbURL.replacingOccurrences(of: "http://", with: "https://")

            return await downloadImage(from: thumbURL)
        } catch {
            return nil
        }
    }

    // MARK: - Open Library API

    private func fetchFromOpenLibrary(title: String, author: String?) async -> NSImage? {
        guard var components = URLComponents(string: "https://openlibrary.org/search.json") else {
            return nil
        }
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "limit", value: "3"),
            URLQueryItem(name: "fields", value: "cover_i")
        ]
        if let author, !author.isEmpty {
            queryItems.append(URLQueryItem(name: "author", value: author))
        }
        components.queryItems = queryItems

        guard let url = components.url else { return nil }

        do {
            let (data, _) = try await session.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let docs = json["docs"] as? [[String: Any]],
                  let first = docs.first,
                  let coverID = first["cover_i"] as? Int else { return nil }

            let coverURL = "https://covers.openlibrary.org/b/id/\(coverID)-M.jpg"
            return await downloadImage(from: coverURL)
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    private func downloadImage(from urlString: String) async -> NSImage? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return NSImage(data: data)
        } catch {
            return nil
        }
    }

    /// Returns "tr" if the title contains Turkish-specific characters, nil otherwise.
    private func detectLanguage(from title: String) -> String? {
        let turkishChars = CharacterSet(charactersIn: "çÇğĞşŞıİöÖüÜ")
        return title.unicodeScalars.contains(where: turkishChars.contains) ? "tr" : nil
    }

    /// Deterministic, filesystem-safe key from book title (UInt64 hex hash).
    private func cacheKey(for bookTitle: String) -> String {
        let hash = bookTitle.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 31) &+ UInt64($1.value) }
        return String(hash, radix: 16)
    }

    // MARK: - Disk cache

    private func ensureCacheDirectory() {
        try? FileManager.default.createDirectory(
            at: Constants.Paths.coversDirectory,
            withIntermediateDirectories: true
        )
    }

    private func diskURL(for key: String) -> URL {
        Constants.Paths.coversDirectory.appendingPathComponent("\(key).jpg")
    }

    private func loadFromDisk(key: String) -> NSImage? {
        let url = diskURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return NSImage(data: data)
    }

    private func saveToDisk(image: NSImage, key: String) {
        ensureCacheDirectory()
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return }
        try? jpegData.write(to: diskURL(for: key))
    }

    private func deleteDiskCache(key: String) {
        try? FileManager.default.removeItem(at: diskURL(for: key))
    }
}
