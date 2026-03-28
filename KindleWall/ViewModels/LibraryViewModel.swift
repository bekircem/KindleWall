import SwiftUI
import Observation

/// Manages the state for the clipping library view.
@Observable
final class LibraryViewModel {
    // MARK: - State

    var searchText: String = ""
    var selectedBookFilter: String?
    var showFavoritesOnly: Bool = false
    var selectedClipping: Clipping?

    // MARK: - Dependencies

    private let storage: StorageServiceProtocol

    init(storage: StorageServiceProtocol = StorageService()) {
        self.storage = storage
    }

    // MARK: - Computed

    /// Filters clippings based on search text, book filter, and favorites toggle.
    func filteredClippings(from clippings: [Clipping]) -> [Clipping] {
        var result = clippings

        // Filter by favorites
        if showFavoritesOnly {
            let favorites = storage.favoriteClippingIDs
            result = result.filter { favorites.contains($0.id) }
        }

        // Filter by book
        if let book = selectedBookFilter {
            result = result.filter { $0.bookTitle == book }
        }

        // Filter by search text
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.text.lowercased().contains(query) ||
                $0.bookTitle.lowercased().contains(query) ||
                ($0.author?.lowercased().contains(query) ?? false)
            }
        }

        return result
    }

    /// Returns a sorted list of unique book titles from the clippings.
    func bookTitles(from clippings: [Clipping]) -> [String] {
        Array(Set(clippings.map { $0.bookTitle })).sorted()
    }

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
}
