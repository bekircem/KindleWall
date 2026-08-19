import SwiftUI

/// Lays subviews out left to right, wrapping to a new line when the next one would not fit.
///
/// SwiftUI ships no wrapping stack, and the alternatives both fail this job: an `HStack`
/// pushes past the container instead of wrapping, and a `LazyVGrid` forces every cell to one
/// width, which looks wrong for chips whose labels are book titles of wildly different length.
///
/// Sizing and placement share `rows(for:proposal:)`, so what is measured is exactly what is
/// drawn — the usual source of a layout that reports one height and paints another.
struct FlowLayout: Layout {
    var spacing: CGFloat = Theme.Spacing.s
    var lineSpacing: CGFloat = Theme.Spacing.s

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = rows(for: subviews, maxWidth: maxWidth)
        guard !rows.isEmpty else { return .zero }

        let height = rows.map(\.height).reduce(0, +)
            + lineSpacing * CGFloat(rows.count - 1)
        let width = rows.map(\.width).max() ?? 0
        // Report the width actually used, not the width offered: inside a leading-aligned
        // card an infinite proposal would otherwise stretch the chips' container edge to edge.
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(for: subviews, maxWidth: bounds.width)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    // MARK: - Row breaking

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width

            if needed > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
                current.indices = [index]
                current.width = size.width
                current.height = size.height
            } else {
                current.indices.append(index)
                current.width = needed
                current.height = max(current.height, size.height)
            }
        }

        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
