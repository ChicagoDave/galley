//
//  FlowLayout.swift
//  UntitledApp
//
//  Purpose: A wrapping flow `Layout` for the reveal pane — lays subviews left to
//  right, wrapping to the next line when the row is full (ADR-0006 reveal pane).
//  Used to render the interleaved text segments and code chips of the reveal
//  stream where each chip is its own interactive view.
//  Public interface: `FlowLayout`.
//  Owner context: UntitledApp — the macOS shell's SwiftUI layout.
//

import SwiftUI

/// A simple left-to-right wrapping layout.
struct FlowLayout: Layout {

    /// Horizontal gap between items on a row.
    var horizontalSpacing: CGFloat = 2

    /// Vertical gap between rows.
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        arrange(subviews: subviews, maxWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let result = arrange(subviews: subviews, maxWidth: bounds.width)
        for index in subviews.indices {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + result.points[index].x, y: bounds.minY + result.points[index].y),
                anchor: .topLeading,
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> (points: [CGPoint], sizes: [CGSize], size: CGSize) {
        var points: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            sizes.append(size)
            x += size.width + horizontalSpacing
            widest = max(widest, x)
            rowHeight = max(rowHeight, size.height)
        }

        let totalWidth = maxWidth.isFinite ? maxWidth : widest
        return (points, sizes, CGSize(width: totalWidth, height: y + rowHeight))
    }
}
