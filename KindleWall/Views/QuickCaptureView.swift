import SwiftUI

/// Compact form presented in the floating QuickCapturePanel.
/// Lets the user confirm or edit text captured via the global hotkey (⌃⌥K)
/// without leaving the app they were reading in.
struct QuickCaptureView: View {
    let existingBooks: [(title: String, author: String?)]
    let onSave: (String, String?, String, String?) -> Void
    let onCancel: () -> Void

    @State private var bookTitle: String
    @State private var text: String
    @State private var showSuggestions = false

    init(
        prefilledText: String = "",
        existingBooks: [(title: String, author: String?)] = [],
        onSave: @escaping (String, String?, String, String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _bookTitle = State(initialValue: "")
        _text      = State(initialValue: prefilledText)
        self.existingBooks = existingBooks
        self.onSave   = onSave
        self.onCancel = onCancel
    }

    private var canSave: Bool { !bookTitle.trimmed.isEmpty && !text.trimmed.isEmpty }

    private var filteredSuggestions: [(title: String, author: String?)] {
        guard !bookTitle.isEmpty else { return [] }
        let q = bookTitle.lowercased()
        return existingBooks.filter { $0.title.lowercased().contains(q) }.prefix(4).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Book title field
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
                                showSuggestions = false
                            } label: {
                                Text(suggestion.title)
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .hoverHighlight(cornerRadius: 0)
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
            .padding([.horizontal, .top], 16)

            // Quote text
            VStack(alignment: .leading, spacing: 6) {
                Label("Quote", systemImage: "quote.opening")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: 90)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Divider()
                .padding(.top, 16)

            // Action buttons
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Kaydet") {
                    onSave(bookTitle.trimmed, nil, text.trimmed, nil)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding()
        }
        .frame(width: 440, height: 320)
        // Hosted in a standalone AppKit panel, so it doesn't inherit the window's scheme.
        .preferredColorScheme(.dark)
    }
}
