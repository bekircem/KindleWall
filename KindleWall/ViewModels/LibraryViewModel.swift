import SwiftUI
import Observation

enum LibraryViewMode {
    case list, card
}

/// Manages the state for the clipping library view.
@Observable
final class LibraryViewModel {
    // MARK: - State

    var searchText: String = ""
    var showFavoritesOnly: Bool = false
    var selectedClipping: Clipping?
    var viewMode: LibraryViewMode = .list

    /// In-memory cache of user metadata overrides (keyed by original title).
    var metadataOverrides: [String: BookMetadataOverride] = [:]

    // MARK: - Dependencies

    private var storage: StorageServiceProtocol

    init(storage: StorageServiceProtocol = StorageService()) {
        self.storage = storage
        self.metadataOverrides = storage.bookMetadataOverrides
    }

    // MARK: - Book grouping

    /// Groups clippings into Book objects, applies metadata overrides, sorts by displayTitle.
    func books(from clippings: [Clipping]) -> [Book] {
        var dict: [String: (author: String?, clippings: [Clipping])] = [:]
        for c in clippings {
            if dict[c.bookTitle] == nil {
                dict[c.bookTitle] = (c.author, [c])
            } else {
                dict[c.bookTitle]?.clippings.append(c)
            }
        }
        return dict.map { key, value in
            let ov = metadataOverrides[key]
            return Book(
                title: key,
                author: value.author,
                clippings: value.clippings,
                displayTitle: ov?.displayTitle,
                displayAuthor: ov?.displayAuthor
            )
        }
        .sorted { $0.displayTitle.localizedCompare($1.displayTitle) == .orderedAscending }
    }

    /// Filters books by search text (against displayTitle/displayAuthor) and favorites toggle.
    func filteredBooks(from clippings: [Clipping]) -> [Book] {
        var result = books(from: clippings)

        if showFavoritesOnly {
            let favIDs = storage.favoriteClippingIDs
            result = result.filter { book in
                book.clippings.contains { favIDs.contains($0.id) }
            }
        }

        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.displayTitle.lowercased().contains(q) ||
                ($0.displayAuthor?.lowercased().contains(q) ?? false)
            }
        }

        return result
    }

    /// Checks if a book has at least one favorite clipping.
    func hasFavorite(_ book: Book) -> Bool {
        let favIDs = storage.favoriteClippingIDs
        return book.clippings.contains { favIDs.contains($0.id) }
    }

    // MARK: - Clipping-level favorites (used in BookDetailView)

    /// Checks if a clipping is a favorite.
    func isFavorite(_ clipping: Clipping) -> Bool {
        storage.favoriteClippingIDs.contains(clipping.id)
    }

    /// Toggles the favorite status of a clipping.
    func toggleFavorite(_ clipping: Clipping) {
        var favorites = storage.favoriteClippingIDs
        if favorites.contains(clipping.id) {
            favorites.remove(clipping.id)
        } else {
            favorites.insert(clipping.id)
        }
        storage.favoriteClippingIDs = favorites
    }

    // MARK: - Metadata Overrides

    /// Saves or updates a metadata override and persists it to storage.
    func saveMetadataOverride(_ override: BookMetadataOverride) {
        metadataOverrides[override.originalTitle] = override
        storage.bookMetadataOverrides = metadataOverrides
    }

    /// Removes the metadata override for the given original title.
    func removeMetadataOverride(forTitle title: String) {
        metadataOverrides.removeValue(forKey: title)
        storage.bookMetadataOverrides = metadataOverrides
    }
}
