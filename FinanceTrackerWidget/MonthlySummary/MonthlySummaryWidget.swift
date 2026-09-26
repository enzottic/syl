//
//  MonthlySummaryWidget.swift
//  FinanceTrackerWidgetExtension
//
//  Created by Enzo on 5/20/26.
//

import SwiftUI
import WidgetKit
import SageKit

struct MonthlySummaryEntryView: View {
    @Environment(\.widgetFamily) var family
    @Environment(\.categoryColors) private var categoryColors
    let entry: MonthlySummaryEntry

    /// Income is the overall budget, so the total only turns red once income is set and exceeded.
    var isOverBudget: Bool { BudgetStatus(spent: entry.totalSpent, budget: Double(entry.totalIncome)).isOverBudget }

    var body: some View {
        Group {
            switch family {
            case .systemSmall: smallBody
            case .systemMedium: mediumBody
            default: largeBody
            }
        }
    }

    // MARK: - Small: spending + compact category bars

    var smallBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.date.formatted(.dateTime.month(.wide).year()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.currencyString(entry.totalSpent))
                        .font(.title3)
                        .fontWeight(.black)
                        .foregroundStyle(isOverBudget ? .red : .primary)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("spent")
                        .font(.caption)
                        .fixedSize()
                }
            }

            Divider()

            VStack(spacing: 6) {
                compactCategoryRow(.needs, spent: entry.needsSpent, budget: entry.needsBudget)
                compactCategoryRow(.wants, spent: entry.wantsSpent, budget: entry.wantsBudget)
                compactCategoryRow(.savings, spent: entry.savingsSpent, budget: entry.savingsBudget)
            }
        }
    }

    func compactCategoryRow(_ category: ExpenseCategory, spent: Double, budget: Double) -> some View {
        let name = category.rawValue
        let color = category.color(in: categoryColors)
        let utilization = budget > 0 ? spent / budget : 0
        let status = BudgetStatus(spent: spent, budget: budget, goal: category.budgetGoal)
        let isOverBudget = status.isOverBudget
        return VStack(spacing: 3) {
            HStack {
                Circle()
                    .frame(width: 6, height: 6)
                    .foregroundStyle(color)
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(status.hasBudget ? utilization.formatted(.percent.precision(.fractionLength(0))) : entry.description(of: status))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(isOverBudget ? .red : .primary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.15))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isOverBudget ? .red : color)
                        .frame(width: geo.size.width * min(max(utilization, 0), 1), height: 4)
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(categoryAccessibilityValue(spent: spent, budget: budget, status: status))
    }

    // MARK: - Medium/Large: header + full category rows

    var mediumBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.date.formatted(.dateTime.month(.wide).year()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(entry.currencyString(entry.totalSpent))
                            .font(.title2)
                            .fontWeight(.black)
                            .foregroundStyle(isOverBudget ? .red : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("spent")
                            .fixedSize()
                    }
                }
                Spacer()
            }

            VStack(spacing: 8) {
                fullCategoryRow(.needs, spent: entry.needsSpent, budget: entry.needsBudget)
                fullCategoryRow(.wants, spent: entry.wantsSpent, budget: entry.wantsBudget)
                fullCategoryRow(.savings, spent: entry.savingsSpent, budget: entry.savingsBudget)
            }
        }
    }

    var largeBody: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date.formatted(.dateTime.month(.wide).year()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(entry.currencyString(entry.totalSpent))
                        .font(.title)
                        .fontWeight(.black)
                        .foregroundStyle(isOverBudget ? .red : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("spent")
                        .fixedSize()
                }
            }
            
            Spacer()

            VStack(spacing: 10) {
                fullCategoryRow(.needs, spent: entry.needsSpent, budget: entry.needsBudget)
                fullCategoryRow(.wants, spent: entry.wantsSpent, budget: entry.wantsBudget)
                fullCategoryRow(.savings, spent: entry.savingsSpent, budget: entry.savingsBudget)
            }
            
            Spacer()
            
            VStack(alignment: .leading) {
                Text("Recent Expenses")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(entry.recentExpenses.prefix(5)) { expense in
                    HStack(spacing: 6) {
                        Circle()
                            .frame(width: 8, height: 8)
                            .foregroundStyle(expense.category.color(in: categoryColors))
                        Text(expense.name)
                            .font(.caption)
                            .lineLimit(1)
                            .layoutPriority(-1)
                        Spacer()
                        Text(entry.currencyString(expense.amount))
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(expense.name), \(entry.currencyString(expense.amount)), \(expense.category.rawValue), \(expense.date.formatted(date: .abbreviated, time: .omitted))")
                }

            }
        }
    }

    func fullCategoryRow(_ category: ExpenseCategory, spent: Double, budget: Double) -> some View {
        let name = category.rawValue
        let color = category.color(in: categoryColors)
        let utilization = budget > 0 ? spent / budget : 0
        let status = BudgetStatus(spent: spent, budget: budget, goal: category.budgetGoal)
        let isOverBudget = status.isOverBudget
        return VStack(spacing: 4) {
            HStack {
                Text(isOverBudget ? "\(name) (over)" : name)
                    .font(.caption)
                    .foregroundStyle(isOverBudget ? .red : .secondary)
                    .layoutPriority(-1)
                Spacer()
                Text(entry.currencyString(spent))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(isOverBudget ? .red : .primary)
                Text(status.hasBudget ? "/ \(entry.currencyString(budget))" : entry.description(of: status))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            ProgressView(value: min(max(utilization, 0), 1), total: 1)
                .tint(isOverBudget ? .red : color)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(categoryAccessibilityValue(spent: spent, budget: budget, status: status))
    }

    func categoryAccessibilityValue(spent: Double, budget: Double, status: BudgetStatus) -> String {
        "\(entry.currencyString(spent)) spent, budget \(entry.currencyString(budget)), \(entry.description(of: status))"
    }
}

struct MonthlySummaryWidget: Widget {
    let kind: String = "SageMonthlySummaryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MonthlySummaryProvider()) { entry in
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
                    MonthlySummaryEntryView(entry: entry)
                }
            }
            .fontDesign(.rounded)
            .environment(\.categoryColors, CategoryColors.load())
            .containerBackground(.sageBackground, for: .widget)
        }
        .configurationDisplayName("Monthly Summary")
        .description(Text("View spending across all budget categories"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview("Small", as: .systemSmall) {
    MonthlySummaryWidget()
} timeline: {
    MonthlySummaryEntry.preview
    MonthlySummaryEntry.noIncomePreview
}

#Preview("Medium", as: .systemMedium) {
    MonthlySummaryWidget()
} timeline: {
    MonthlySummaryEntry.preview
    MonthlySummaryEntry.noIncomePreview
}

#Preview("Large", as: .systemLarge) {
    MonthlySummaryWidget()
} timeline: {
    MonthlySummaryEntry.preview
    MonthlySummaryEntry.noIncomePreview
}
