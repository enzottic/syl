//
//  RecentExpensesWidget.swift
//  FinanceTrackerWidgetExtension
//
//  Created by Enzo on 5/20/26.
//

import SwiftUI
import WidgetKit
import SageKit

struct RecentExpensesEntryView: View {
    @Environment(\.categoryColors) private var categoryColors

    let entry: RecentExpensesEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Today \(entry.currencyString(entry.todayTotal))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)

            if entry.expenses.isEmpty {
                Spacer()
                Text("No expenses yet. Add one in Syl.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(entry.expenses.prefix(3)) { expense in
                        row(for: expense)
                            .frame(maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(for expense: ExpenseSnapshot) -> some View {
        let tint = expense.tagColor ?? expense.category.color(in: categoryColors)
        return HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.18))
                if let glyph = expense.glyph {
                    TagGlyphView(glyph)
                        .font(.system(size: 14))
                        .foregroundStyle(tint)
                } else {
                    Text(expense.category.rawValue.prefix(1))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: 30, height: 30)
            .widgetAccentable()
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(expense.name)
                    .font(.subheadline)
                Text("\(expense.category.rawValue) · \(expense.date.relative(to: entry.date))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .layoutPriority(-1)

            Spacer(minLength: 8)

            Text(entry.currencyString(expense.amount))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(expense.name), \(entry.currencyString(expense.amount)), \(expense.category.rawValue), \(expense.date.formatted(date: .abbreviated, time: .omitted))")
    }
}

struct RecentExpensesWidget: Widget {
    let kind: String = "SageRecentExpensesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecentExpensesProvider()) { entry in
            Group {
                if entry.isUnavailable {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .accessibilityHidden(true)
                        Text("Spending unavailable")
                            .font(.caption.weight(.semibold))
                        Text("Open Syl to reload your data.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if entry.currencyCode == nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Confirm currency")
                            .font(.caption.weight(.semibold))
                        Text("Open Syl to confirm your currency.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    RecentExpensesEntryView(entry: entry)
                        .privacySensitive()
                }
            }
            .fontDesign(.rounded)
            .environment(\.categoryColors, CategoryColors.load())
            .containerBackground(.sageBackground, for: .widget)
        }
        .configurationDisplayName("Recent Expenses")
        .description(Text("View your most recent expenses"))
        .supportedFamilies([.systemMedium])
    }
}

#Preview(as: .systemMedium) {
    RecentExpensesWidget()
} timeline: {
    RecentExpensesEntry.preview
}
