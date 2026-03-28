import SwiftUI

/// Displays the searchable, filterable clipping library.
struct LibraryView: View {
    let clippings: [Clipping]
    var onSelectClipping: (Clipping) -> Void

    @State private var viewModel = LibraryViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Search and filter bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Alıntı veya kitap ara...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)

                Toggle(isOn: $viewModel.showFavoritesOnly) {
                    Image(systemName: viewModel.showFavoritesOnly ? Constants.Icons.favoriteFilled : Constants.Icons.favorite)
                }
                .toggleStyle(.button)
                .help("Sadece favorileri göster")

                Picker("Kitap", selection: $viewModel.selectedBookFilter) {
                    Text("Tüm Kitaplar").tag(nil as String?)
                    Divider()
                    ForEach(viewModel.bookTitles(from: clippings), id: \.self) { title in
                        Text(title).tag(title as String?)
                    }
                }
                .frame(width: 200)
            }
            .padding()

            Divider()

            // Clipping list
            let filtered = viewModel.filteredClippings(from: clippings)

            if filtered.isEmpty {
                ContentUnavailableView(
                    "Alıntı bulunamadı",
                    systemImage: "text.quote",
                    description: Text("Arama kriterlerinize uygun alıntı yok.")
                )
            } else {
                List(filtered, selection: $viewModel.selectedClipping) { clipping in
                    ClippingCard(
                        clipping: clipping,
                        isFavorite: viewModel.isFavorite(clipping)
                    )
                    .onTapGesture {
                        onSelectClipping(clipping)
                    }
                    .contextMenu {
                        Button("Wallpaper Yap") {
                            onSelectClipping(clipping)
                        }
                        Button(viewModel.isFavorite(clipping) ? "Favorilerden Çıkar" : "Favorilere Ekle") {
                            viewModel.toggleFavorite(clipping)
                        }
                        Button("Kopyala") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(clipping.text, forType: .string)
                        }
                    }
                }
            }
        }
    }
}
