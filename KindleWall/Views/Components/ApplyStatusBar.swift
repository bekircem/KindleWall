import SwiftUI

/// The one place the app answers "did my change actually reach the desktop?".
///
/// Floats over the bottom of the main window on every screen, not just the design page,
/// because design-affecting controls are scattered across several of them — the long-quote
/// settings live under "Behavior", and a style can be picked from the toolbar. Wherever the
/// user changed something, the answer appears in the same spot.
struct ApplyStatusBar: View {
    /// Plain `let`: reading an `@Observable`'s properties inside `body` is tracked already, and
    /// nothing here needs a binding.
    let viewModel: MainViewModel

    var body: some View {
        // The animation modifier sits outside the conditional on purpose — inside, it would be
        // removed along with the view and the disappearance would not animate.
        Group {
            if let presentation {
                content(presentation)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(Theme.Motion.smooth, value: viewModel.applyStatus)
    }

    // MARK: - Content

    private func content(_ p: Presentation) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            icon(p)
                .frame(width: 16)

            // Truncates rather than pushing the button off the edge at the minimum window size.
            Text(p.message)
                .font(.callout)
                .foregroundStyle(p.isError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.tail)

            if let action = p.action {
                Divider().frame(height: 14)

                Button(action.title) { action.perform() }
                    .buttonStyle(.link)
                    .font(.callout)
                    .fixedSize()
                    .accessibilityLabel(action.title)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s + 2)
        .frame(maxWidth: 460)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(p.message)
    }

    @ViewBuilder private func icon(_ p: Presentation) -> some View {
        if p.showsSpinner {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: p.symbol)
                .font(.callout)
                .foregroundStyle(p.isError ? AnyShapeStyle(.red) : AnyShapeStyle(p.tint))
        }
    }

    // MARK: - Status → presentation

    private struct Action {
        let title: String
        let perform: () -> Void
    }

    private struct Presentation {
        var symbol: String = "checkmark.circle.fill"
        var showsSpinner = false
        var tint: Color = .secondary
        var message: String
        var isError = false
        var action: Action?
    }

    /// `nil` means the desktop and the app agree, so there is nothing worth saying.
    private var presentation: Presentation? {
        switch viewModel.applyStatus {
        case .idle:
            return nil

        case .pending:
            return Presentation(
                symbol: "clock",
                message: "Changes will be applied shortly…",
                action: Action(title: "Apply Now") { viewModel.applyDesignNow() }
            )

        case .applying:
            return Presentation(showsSpinner: true, message: "Applying to the desktop…")

        case let .applied(at, reason, degraded):
            if let degraded {
                // A fallback still changed the wallpaper, so this is a caveat rather than a
                // failure — it must not read as if nothing happened.
                return Presentation(
                    symbol: "exclamationmark.triangle.fill",
                    tint: .orange,
                    message: degraded
                )
            }
            return Presentation(
                symbol: "checkmark.circle.fill",
                tint: .green,
                message: "Applied to the desktop · \(Self.timeFormatter.string(from: at))",
                action: undoAction(for: reason)
            )

        case let .failed(message):
            return Presentation(
                symbol: "exclamationmark.triangle.fill",
                message: message,
                isError: true,
                action: Action(title: "Yeniden Dene") { viewModel.applyDesignNow() }
            )

        case .unapplied:
            return Presentation(
                symbol: "eye",
                message: "Changes are preview-only",
                action: Action(title: "Apply") { viewModel.applyDesignNow() }
            )
        }
    }

    /// Undo is only offered when the design is what changed. After a scheduler tick it was the
    /// *quote* that moved, so offering to restore a design would be a lie.
    private func undoAction(for reason: ApplyReason) -> Action? {
        guard reason.offersDesignUndo, viewModel.designUndo != nil else { return nil }
        return Action(title: "Undo") { viewModel.undoDesign() }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

// MARK: - Apply toolbar button

/// The primary action on every surface that can change the wallpaper.
///
/// Shared so that the top-right of the window means the same thing everywhere. It used to
/// exist only on "Current Quote", while on the design pages that same slot held a preview
/// toggle — so the one place users had learned to look for "Apply" showed something else.
struct ApplyToolbarButton: View {
    let viewModel: MainViewModel

    var body: some View {
        Button {
            viewModel.applyDesignNow()
        } label: {
            Group {
                switch viewModel.applyStatus {
                case .applying:
                    Label("Applying…", systemImage: Constants.Icons.refresh)
                case .applied:
                    Label("Applied", systemImage: "checkmark.circle.fill")
                default:
                    Label("Apply", systemImage: Constants.Icons.wallpaper)
                }
            }
            .animation(Theme.Motion.snappy, value: viewModel.applyStatus)
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderedProminent)
        .tint(viewModel.applySuccess ? .green : .accentColor)
        .disabled(viewModel.isApplying)
        .keyboardShortcut(.return, modifiers: .command)
        .help("Apply this design as the desktop wallpaper")
        .accessibilityLabel("Apply as wallpaper")
    }
}
