import SwiftUI

/// The style grid plus its typography-undo banner — the "Style" group of the "Design" page.
struct StyleSection: View {
    var viewModel: MainViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("Wallpaper Style")

            // One binding, one owner. The style write, the typography it carries and the
            // preview all happen inside `updateStyle`, so nothing here can drift.
            StylePickerView(selectedStyle: Binding(
                get: { viewModel.selectedStyle },
                set: { viewModel.updateStyle($0) }
            ))

            if let undo = viewModel.styleTypographyUndo {
                StyleTypographyUndoBanner(styleName: undo.styleName) {
                    viewModel.undoStyleTypography()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Text("Choose the visual style your quotes are rendered in. Each style comes with its own typeface and ornament; you can change it later under Typography.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.leading, Theme.Spacing.xs)
                .padding(.top, Theme.Spacing.xs)
        }
        .animation(Theme.Motion.snappy, value: viewModel.styleTypographyUndo)
    }
}

/// Tells the user a style change rewrote their typography, and offers to put it back.
/// Without this the change would be silent and irreversible — the main objection to letting
/// styles carry their own type.
private struct StyleTypographyUndoBanner: View {
    let styleName: String
    let undo: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "textformat")
                .foregroundStyle(.secondary)

            Text("Typography reset to the \"\(styleName)\" default")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer(minLength: Theme.Spacing.s)

            Button("Undo", action: undo)
                .buttonStyle(.link)
                .font(.callout)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
    }
}
