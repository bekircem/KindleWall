import SwiftUI

/// Sheet for editing a book's display title and author.
/// Shows the raw parsed value as read-only reference, lets the user override both fields,
/// and offers an auto-correct suggestion fetched from Google Books API.
struct BookMetadataEditView: View {
    let book: Book
    var existingOverride: BookMetadataOverride?
    var onSave: (BookMetadataOverride) -> Void = { _ in }
    var onReset: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var editTitle: String = ""
    @State private var editAuthor: String = ""
    @State private var suggestionState: SuggestionState = .idle
    private var isSuggestionLoading: Bool {
        if case .loading = suggestionState { return true }
        return false
    }

    fileprivate enum SuggestionState {
        case idle, loading
        case found(title: String, author: String?)
        case notFound
    }

    // Raw values from the clippings file — shown as reference, not editable
    private var rawReference: String {
        if let a = book.author { return "\(book.title) (\(a))" }
        return book.title
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Details")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    // Raw parsed value as read-only reference
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Dosyadan okunan:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(rawReference)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }

                    // Edit fields
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Book Title")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        TextField("Enter the book title", text: $editTitle)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Yazar")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        TextField("Enter the author's name", text: $editAuthor)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Auto-correct box
                    SettingsCard {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            HStack {
                                Button("Fix Automatically") {
                                    Task { await fetchSuggestion() }
                                }
                                .disabled(isSuggestionLoading)

                                if isSuggestionLoading {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .padding(.leading, 4)
                                }

                                Spacer()
                            }

                            switch suggestionState {
                            case .idle:
                                Text("Fetches a title and author suggestion from Google Books.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                            case .loading:
                                EmptyView()

                            case .found(let sugTitle, let sugAuthor):
                                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                    Text("Suggestion:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("Ad: \(sugTitle)")
                                        .font(.caption)
                                    if let a = sugAuthor {
                                        Text("Yazar: \(a)")
                                            .font(.caption)
                                    }
                                }

                                // Not "Uygula": everywhere else in the app that word means
                                // "put this on the desktop". Here it only fills two fields.
                                Button("Use Suggestion") {
                                    editTitle = sugTitle
                                    editAuthor = sugAuthor ?? ""
                                }
                                .buttonStyle(.bordered)

                            case .notFound:
                                Text("No matching book found. Please correct it by hand.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Spacing.l)
                    }
                }
                .padding()
            }

            Divider()

            // Action buttons
            HStack {
                // Reset to original — only enabled if an override exists
                Button("Reset to Default") {
                    onReset()
                    dismiss()
                }
                .foregroundStyle(.red)
                .disabled(existingOverride == nil)

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Kaydet") {
                    let author = editAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
                    let override = BookMetadataOverride(
                        originalTitle: book.title,
                        displayTitle: editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? book.title
                            : editTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                        displayAuthor: author.isEmpty ? nil : author
                    )
                    onSave(override)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 480, height: 540)
        .onAppear {
            editTitle = book.displayTitle
            editAuthor = book.displayAuthor ?? ""
        }
    }

    // MARK: - Auto-correct

    private func fetchSuggestion() async {
        suggestionState = .loading
        let query = editTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? editTitle
        let urlString = "https://www.googleapis.com/books/v1/volumes?q=intitle:\(query)&maxResults=1"
        guard let url = URL(string: urlString) else {
            suggestionState = .notFound
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let items = json["items"] as? [[String: Any]],
                let first = items.first,
                let volumeInfo = first["volumeInfo"] as? [String: Any],
                let title = volumeInfo["title"] as? String
            else {
                suggestionState = .notFound
                return
            }
            let author = (volumeInfo["authors"] as? [String])?.first
            suggestionState = .found(title: title, author: author)
        } catch {
            suggestionState = .notFound
        }
    }
}

