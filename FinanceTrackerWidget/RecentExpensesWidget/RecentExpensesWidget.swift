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
    @Environment(\.widgetFamily) var family
    @Environment(\.categoryColors) private var categoryColors

    let entry: RecentExpensesEntry

    var displayCount: Int { family == .systemSmall ? 2 : 5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent Expenses")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if entry.expenses.isEmpty {
                Spacer()
                Text("No expenses yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(entry.expenses.prefix(displayCount)) { expense in
                    HStack(spacing: 6) {
                        Circle()
                            .frame(width: 8, height: 8)
                            .foregroundStyle(expense.category.color(in: categoryColors))
                        Text(expense.name)
                            .font(.caption)
                            .lineLimit(1)
                            .layoutPriority(-1)
                        if family != .systemSmall {
                            Spacer()
                            Text(entry.currencyString(expense.amount))
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(expense.name), \(entry.currencyString(expense.amount)), \(expense.category.rawValue), \(expense.date.formatted(date: .abbreviated, time: .omitted))")
                    if family == .systemSmall {
                        Text(entry.currencyString(expense.amount))
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.leading, 14)
                            .accessibilityHidden(true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                }
            }
            .fontDesign(.rounded)
            .environment(\.categoryColors, CategoryColors.load())
            .containerBackground(.sageBackground, for: .widget)
        }
        .configurationDisplayName("Recent Expenses")
        .description(Text("View your most recent expenses"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    RecentExpensesWidget()
} timeline: {
    RecentExpensesEntry.preview
}

#Preview(as: .systemMedium) {
    RecentExpensesWidget()
} timeline: {
    RecentExpensesEntry.preview
}
