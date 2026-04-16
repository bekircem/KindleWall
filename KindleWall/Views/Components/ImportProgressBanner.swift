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
                if let summary = importState.summary {
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
        .animation(.spring(duration: 0.35), value: importState.phase)
        .allowsHitTesting(importState.phase != .idle)
        .task(id: importState.phase) {
            if case .completed = importState.phase {
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                withAnimation {
                    importState.phase = .idle
                    importState.summary = nil
                }
            }
        }
    }

    // MARK: - Running

    private var runningBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("İçeri Aktarılıyor...")
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
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("İçeri Aktarma Tamamlandı")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(summaryText(summary))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation {
                    importState.phase = .idle
                    importState.summary = nil
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

    // MARK: - Failed

    private func failedBanner(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("İçeri Aktarma Başarısız")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                withAnimation {
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

    // MARK: - Summary Text

    private func summaryText(_ s: ImportSummary) -> String {
        var parts: [String] = []
        parts.append("\(s.totalClippings) alıntı")
        if s.newClippings > 0 {
            parts.append("\(s.newClippings) yeni")
        }
        parts.append("\(s.totalBooks) kitap")
        if s.newBooks > 0 {
            parts.append("\(s.newBooks) yeni kitap")
        }
        let durationStr = String(format: "%.1f sn", s.duration)
        return parts.joined(separator: " · ") + " (\(durationStr))"
    }
}
