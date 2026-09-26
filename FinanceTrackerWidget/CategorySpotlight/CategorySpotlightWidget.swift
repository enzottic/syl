//
//  CategorySpotlightWidget.swift
//  FinanceTrackerWidgetExtension
//
//  Created by Enzo on 5/20/26.
//

import SwiftUI
import WidgetKit
import SageKit

struct CategorySpotlightEntryView: View {
    @Environment(\.categoryColors) private var categoryColors
    let entry: CategorySpotlightEntry

    var status: BudgetStatus { entry.status }
    var isOverBudget: Bool { status.isOverBudget }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.category.rawValue.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Spacer()
                Text(status.hasBudget ? entry.utilization.formatted(.percent.precision(.fractionLength(0))) : entry.description(of: status))
                    .font(.caption2)
                    .foregroundStyle(isOverBudget ? .red : .secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            Text(entry.currencyString(entry.spent))
                .font(.title2)
                .fontWeight(.black)
                .foregroundStyle(isOverBudget ? .red : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: min(max(entry.utilization, 0), 1), total: 1)
                    .tint(isOverBudget ? .red : entry.category.color(in: categoryColors))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("of \(entry.currencyString(entry.budget))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(isOverBudget ? "over budget" : entry.description(of: status))
                        .font(.caption2)
                        .foregroundStyle(isOverBudget ? .red : .secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.category.rawValue)
        .accessibilityValue("\(entry.currencyString(entry.spent)) spent, budget \(entry.currencyString(entry.budget)), \(entry.description(of: status))")
    }
}

struct CategorySpotlightWidget: Widget {
    let kind: String = "SageCategorySpotlightWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: CategorySpotlightAppIntent.self, provider: CategorySpotlightProvider()) { entry in
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
                    CategorySpotlightEntryView(entry: entry)
                }
            }
            .fontDesign(.rounded)
            .environment(\.categoryColors, CategoryColors.load())
            .containerBackground(.sageBackground, for: .widget)
        }
        .configurationDisplayName("Category Spotlight")
        .description(Text("Track spending for a specific budget category"))
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    CategorySpotlightWidget()
} timeline: {
    CategorySpotlightEntry.preview(category: .needs)
    CategorySpotlightEntry(date: .now, category: .needs, spent: 86.40, budget: 0, currencyCode: "USD")
    CategorySpotlightEntry(date: .now, category: .savings, spent: 1600, budget: 1400, currencyCode: "USD")
}
