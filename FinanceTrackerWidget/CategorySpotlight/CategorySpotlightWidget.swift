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

    private var status: BudgetStatus { entry.status }
    private var isSavings: Bool { entry.category.budgetGoal == .target }
    private var color: Color { entry.category.color(in: categoryColors) }
    private var wholeCurrency: FloatingPointFormatStyle<Double>.Currency {
        .currency(code: entry.currencyCode ?? LedgerCurrency.currentCode ?? "USD").precision(.fractionLength(0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8).widgetAccentable()
                Text(entry.category.rawValue)
                    .font(.headline)
            }
            Spacer(minLength: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(isSavings ? "Saved" : "Spent")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(entry.currencyString(entry.spent))
                    .font(.title2.bold())
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
                if entry.budget > 0 {
                    Text(isSavings ? "of \(entry.budget.formatted(wholeCurrency)) target"
                                   : "of \(entry.budget.formatted(wholeCurrency))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 6)
            if entry.budget > 0 {
                CategorySpotlightBar(fraction: entry.utilization, pace: isSavings ? nil : entry.monthProgress, color: color)
                    .padding(.bottom, 8)
            }
            remainingText
                .font(.caption.weight(.semibold))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.65)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.category.rawValue)
        .accessibilityValue("\(entry.currencyString(entry.spent)) spent, budget \(entry.currencyString(entry.budget)), \(entry.description(of: status))")
    }

    private var remainingText: some View {
        let text: Text
        let style: Color
        switch status {
        case .noBudget: (text, style) = (Text("No budget set"), .primary)
        case .noTarget: (text, style) = (Text("No savings target"), .primary)
        case .underBudget(let remaining): (text, style) = (Text("\(remaining.formatted(wholeCurrency)) left"), .green)
        case .overBudget(let amount): (text, style) = (Text("\(amount.formatted(wholeCurrency)) over"), .red)
        case .belowTarget(let remaining): (text, style) = (Text("\(remaining.formatted(wholeCurrency)) to go"), .primary)
        case .targetReached: (text, style) = (Text("Target reached"), .green)
        }
        return text.foregroundStyle(style)
    }
}

private struct CategorySpotlightBar: View {
    let fraction: Double
    let pace: Double?
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.22))
                Capsule()
                    .fill(color)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
                    .widgetAccentable()
                if let pace {
                    Capsule()
                        .fill(.primary)
                        .frame(width: 2, height: geometry.size.height + 6)
                        .offset(x: geometry.size.width * min(max(pace, 0), 1) - 1)
                }
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
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
                        .privacySensitive()
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
    CategorySpotlightEntry(date: .now, category: .wants, spent: 2400, budget: 2100, currencyCode: "USD")
}
