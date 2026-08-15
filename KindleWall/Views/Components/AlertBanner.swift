import SwiftUI

/// Surfaces `MainViewModel.errorMessage` wherever the user happens to be.
///
/// That message is produced from roughly fifteen places — a failed import, an empty rotation
/// pool, a missing pinned book — but it used to be drawn in exactly one: a small red caption
/// under the hero on "Şu Anki Alıntı". Anything that went wrong while the user was on another
/// page simply never appeared. Sharing the bottom-overlay slot with `ImportProgressBanner` and
/// `ApplyStatusBar` keeps every transient message in one predictable place.
struct AlertBanner: View {
    @Bindable var viewModel: MainViewModel

    /// Long enough to read a sentence, short enough not to become furniture.
    private static let autoDismiss: Duration = .seconds(8)

    var body: some View {
        // Outside the conditional, so dismissal animates too.
        Group {
            if let message = viewModel.errorMessage {
                banner(message)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(Theme.Motion.smooth, value: viewModel.errorMessage)
    }

    private func banner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)

            Spacer(minLength: Theme.Spacing.s)

            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Kapat")
            .accessibilityLabel("Uyarıyı kapat")
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
        .frame(maxWidth: 460)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.card))
        // Keyed on the message so a *new* error restarts the countdown rather than inheriting
        // the remains of the previous one's.
        .task(id: message) {
            try? await Task.sleep(for: Self.autoDismiss)
            guard !Task.isCancelled else { return }
            if viewModel.errorMessage == message { viewModel.errorMessage = nil }
        }
        .accessibilityElement(children: .contain)
    }
}
