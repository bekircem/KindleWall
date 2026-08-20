import SwiftUI

/// Sheet form for adding or editing a manually entered clipping.
struct ManualClippingFormView: View {
    let clippingToEdit: Clipping?
    let prefilledBookTitle: String
    let existingBooks: [(title: String, author: String?)]
    let onSave: (String, String?, String, String?) -> Void
    let onCancel: () -> Void

    @State private var bookTitle: String
    @State private var author: String
    @State private var text: String
    @State private var page: String
    @State private var showSuggestions = false

    private var isEditMode: Bool { clippingToEdit != nil }
    private var canSave: Bool { !bookTitle.trimmed.isEmpty && !text.trimmed.isEmpty }

    private var filteredSuggestions: [(title: String, author: String?)] {
        guard !bookTitle.isEmpty else { return [] }
        let q = bookTitle.lowercased()
        return existingBooks.filter { $0.title.lowercased().contains(q) }.prefix(5).map { $0 }
    }

    init(
        clippingToEdit: Clipping? = nil,
        prefilledBookTitle: String = "",
        prefilledText: String = "",
        existingBooks: [(title: String, author: String?)] = [],
        onSave: @escaping (String, String?, String, String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.clippingToEdit = clippingToEdit
        self.prefilledBookTitle = prefilledBookTitle
        self.existingBooks = existingBooks
        self.onSave = onSave
        self.onCancel = onCancel

        if let c = clippingToEdit {
            _bookTitle = State(initialValue: c.bookTitle)
            _author    = State(initialValue: c.author ?? "")
            _text      = State(initialValue: c.text)
            _page      = State(initialValue: c.page ?? "")
        } else {
            _bookTitle = State(initialValue: prefilledBookTitle)
            _author    = State(initialValue: "")
            _text      = State(initialValue: prefilledText)
            _page      = State(initialValue: "")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditMode ? "Edit Quote" : "Add Quote by Hand")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Book title + autocomplete
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Book Title", systemImage: "book.closed")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField("Enter the book title…", text: $bookTitle)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: bookTitle) { _, _ in
                                showSuggestions = !filteredSuggestions.isEmpty
                            }

                        if showSuggestions {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(filteredSuggestions, id: \.title) { suggestion in
                                    Button {
                                        bookTitle = suggestion.title
                                        if author.isEmpty, let a = suggestion.author {
                                            author = a
                                        }
                                        showSuggestions = false
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(suggestion.title)
                                                    .font(.caption)
                                                if let a = suggestion.author {
                                                    Text(a)
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            Spacer()
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .hoverHighlight(cornerRadius: 0)

                                    if suggestion.title != filteredSuggestions.last?.title {
                                        Divider().padding(.leading, 10)
                                    }
                                }
                            }
                            .background(.background)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }

                    // Author
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Author (optional)", systemImage: "person")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Author's name…", text: $author)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Quote text
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Quote", systemImage: "quote.opening")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $text)
                            .font(.body)
                            .frame(minHeight: 120)
                            .padding(6)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }

                    // Page number
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Page (optional)", systemImage: "number")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Page number…", text: $page)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                }
                .padding()
            }

            Divider()

            // Action buttons
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    onSave(
                        bookTitle.trimmed,
                        author.trimmed.nilIfEmpty,
                        text.trimmed,
                        page.trimmed.nilIfEmpty
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding()
        }
        .frame(width: 480, height: 520)
    }
}
