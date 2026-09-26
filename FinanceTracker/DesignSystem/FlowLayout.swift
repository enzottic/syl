//
//  FlowLayout.swift
//  FinanceTracker
//

import SwiftUI

/// Lays subviews out left to right, wrapping to a new row whenever the next subview would
/// overflow the proposed width. Used for chip-style content whose count isn't known up front.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    /// How each row is positioned within the available width. `.center` suits standalone
    /// chip clouds; `.leading` lines rows up with surrounding form content.
    var alignment: HorizontalAlignment = .center

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = finiteWidth(proposal.width)
        let rows = computeRows(maxWidth: width, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * spacing
        return CGSize(width: width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(maxWidth: finiteWidth(bounds.width), subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = alignment == .leading ? bounds.minX : bounds.minX + (bounds.width - row.width) / 2
            for item in row.items {
                item.subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: item.proposal)
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Item {
        let subview: LayoutSubview
        let size: CGSize
        let proposal: ProposedViewSize
    }

    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func finiteWidth(_ width: CGFloat?) -> CGFloat? {
        guard let width, width.isFinite else { return nil }
        return max(0, width)
    }

    private func computeRows(maxWidth: CGFloat?, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()

        for subview in subviews {
            var proposal = ProposedViewSize.unspecified
            var size = subview.sizeThatFits(proposal)
            if let maxWidth, size.width > maxWidth {
                // Allow a long chip to wrap vertically, then retain that measurement and
                // proposal so row height and placement describe the same rendered content.
                proposal = ProposedViewSize(width: maxWidth, height: nil)
                size = subview.sizeThatFits(proposal)
            }
            let gap = row.items.isEmpty ? 0 : spacing
            if !row.items.isEmpty, row.width + gap + size.width > (maxWidth ?? .infinity) {
                rows.append(row)
                row = Row()
            }
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append(Item(subview: subview, size: size, proposal: proposal))
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
