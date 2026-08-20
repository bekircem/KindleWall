import SwiftUI

/// Floating overlay shown during and after a clippings import.
struct ImportProgressBanner: View {
    @Environment(ImportState.self) private var importState

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            switch importState.phase {
            case .running:
                runningBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))

            case .completed:
                // Only when the user asked. The launch import runs on every window open and
                // has nothing worth interrupting for when the file has not changed.
                if importState.announcesResult, let summary = importState.summary {
                    completedBanner(summary: summary)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

            case .failed(let message):
                failedBanner(message: message)
                    .transition(.move(edge: .bottom).combined(with: .opacity))

            case .idle:
                EmptyView()
            }
        }
        .animation(Theme.Motion.smooth, value: importState.phase)
        .allowsHitTesting(importState.phase != .idle)
        .task(id: importState.phase) {
            // "Nothing new" dismisses itself; a list of books does not — reading it takes
            // longer than six seconds, and it is the answer the user pressed a button for.
            guard case .completed = importState.phase,
                  importState.summary?.foundNothingNew ?? true
            else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    // MARK: - Running

    private var runningBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Importing…")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(Int(importState.progress * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: importState.progress)
                .tint(.accentColor)

            if let book = importState.currentBook {
                Text(book)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }

    // MARK: - Completed

    private func completedBanner(summary: ImportSummary) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: summary.foundNothingNew ? "checkmark.circle" : "sparkles")
                .foregroundStyle(summary.foundNothingNew ? .secondary : Color.accentColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.headline)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .fixedSize(horizontal: false, vertical: true)

                if summary.foundNothingNew {
                    Text("Your library is already up to date.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(summary.booksLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    bookList(summary)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .frame(maxWidth: 420, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }

    /// Which books grew, most first. Capped so a reader who has been away for months gets a
    /// banner rather than a wall.
    @ViewBuilder private func bookList(_ summary: ImportSummary) -> some View {
        let (shown, hidden) = summary.namedBooks

        VStack(alignment: .leading, spacing: 2) {
            ForEach(shown) { book in
                HStack(spacing: 4) {
                    Text(verbatim: "\(book.newClippings)×")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(verbatim: book.bookTitle)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if book.isNewBook {
                        Text("new")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.22), in: Capsule())
                    }
                }
            }
            if hidden > 0 {
                Text("and \(hidden) more books")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func dismiss() {
        withAnimation(Theme.Motion.smooth) {
            importState.phase = .idle
            importState.summary = nil
            importState.announcesResult = false
        }
    }

    // MARK: - Failed

    private func failedBanner(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Import Failed")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                withAnimation(Theme.Motion.smooth) {
                    importState.phase = .idle
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }

}
