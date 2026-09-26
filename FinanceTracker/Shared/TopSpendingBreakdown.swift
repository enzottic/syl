//
//  TopSpendingBreakdown.swift
//  FinanceTracker
//
//  Ranked "where the money went" list for the current Stats period.
//

import SwiftUI
import SwiftData
import SageKit

struct TopSpendingBreakdown: View {
    @Environment(AppConfiguration.self) private var config
    let expenses: [Expense]
    let accentColor: Color
    var maximumRows: Int = 5
    var includesUntaggedExpenses: Bool = true
    var contentPadding: CGFloat = 0
    var untaggedLabel: String? = nil
    /// The Stats screen presents this breakdown as a standalone card, while
    /// dashboard widgets supply their own container surface.
    var showsCardBackground: Bool = true

    private struct Row: Identifiable {
        let id: String
        let label: String
        let glyph: TagGlyph?
        let tintColor: Color?
        let amount: Double
    }

    private var rows: [Row] {
        var accumulator: [String: Row] = [:]

        func add(key: String, label: String, glyph: TagGlyph?, tintColor: Color? = nil, amount: Double) {
            if let existing = accumulator[key] {
                accumulator[key] = Row(
                    id: key,
                    label: existing.label,
                    glyph: existing.glyph,
                    tintColor: existing.tintColor,
                    amount: existing.amount + amount
                )
            } else {
                accumulator[key] = Row(id: key, label: label, glyph: glyph, tintColor: tintColor, amount: amount)
            }
        }

        for expense in expenses {
            let activeTags = (expense.tags ?? []).filter { !$0.isDeleted }
            if activeTags.isEmpty, includesUntaggedExpenses {
                add(key: "cat-\(expense.category.rawValue)", label: untaggedLabel ?? expense.category.rawValue, glyph: nil, amount: expense.amount)
            } else {
                for tag in activeTags {
                    add(key: "tag-\(tag.id)", label: tag.name, glyph: tag.glyph, tintColor: tag.color, amount: expense.amount)
                }
            }
        }

        return accumulator.values
            .sorted { $0.amount > $1.amount }
            .prefix(maximumRows)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rows) { row in
                rowView(row)
            }
        }
        .padding(contentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if showsCardBackground {
                RoundedRectangle(cornerRadius: 15).fill(.cardBackground)
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        HStack(spacing: 8) {
            if let glyph = row.glyph {
                TagGlyphView(glyph)
                    .foregroundStyle(row.tintColor ?? accentColor)
                    .frame(width: 24, alignment: .center)
            } else {
                Circle()
                    .fill(accentColor)
                    .frame(width: 10, height: 10)
                    .frame(width: 24, alignment: .center)
            }

            Text(row.label)
                .font(.subheadline)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(row.amount.currencyString(code: config.ledgerCurrencyCode))
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.label)
        .accessibilityValue(row.amount.currencyString(code: config.ledgerCurrencyCode))
    }
}
