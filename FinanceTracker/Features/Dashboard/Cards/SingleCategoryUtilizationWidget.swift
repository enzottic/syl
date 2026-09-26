//
//  SingleCategoryUtilizationWidget.swift
//  FinanceTracker
//
//  Created by Enzo on 7/12/26.
//
import SwiftUI
import SwiftData
import SageKit

struct SingleCategoryUtilizationWidget: View {
    @Environment(AppConfiguration.self) private var config
    @Environment(AppRouter.self) private var appRouter
    @Environment(\.categoryColors) private var categoryColors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let category: ExpenseCategory
    let layout: DashboardWidgetLayout
    let isNavigable: Bool
    private let selectedMonth: Date

    @Query var monthlyExpenses: [Expense]

    init(category: ExpenseCategory, layout: DashboardWidgetLayout, selectedMonth: Date, isNavigable: Bool = true) {
        self.category = category
        self.layout = layout
        self.selectedMonth = selectedMonth
        self.isNavigable = isNavigable
        _monthlyExpenses = expenseQuery(for: selectedMonth)
    }

    private var spent: Double {
        switch category {
        case .wants: monthlyExpenses.wantsUsed
        case .needs: monthlyExpenses.needsUsed
        case .savings: monthlyExpenses.savingsUsed
        @unknown default: 0
        }
    }

    private var budget: Double {
        switch category {
        case .wants: config.wantsBudget
        case .needs: config.needsBudget
        case .savings: config.savingsBudget
        @unknown default: 0
        }
    }

    private var utilization: Double {
        budget == 0 ? 0 : spent / budget
    }

    private var clampedUtilization: Double {
        min(max(utilization, 0), 1)
    }

    private var status: BudgetStatus { BudgetStatus(spent: spent, budget: budget, goal: category.budgetGoal) }
    private var isOverBudget: Bool { status.isOverBudget }
    private var tint: Color { isOverBudget ? .red : category.color(in: categoryColors) }

    var body: some View {
        switch layout {
        case .full:
            Group {
                if isNavigable {
                    Button {
                        appRouter.push(.categoryDetail(category, selectedMonth))
                    } label: {
                        fullContent
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                } else {
                    fullContent
                        .listRowSeparator(.hidden)
                }
            }
        case .compact:
            if isNavigable {
                Button {
                    appRouter.push(.categoryDetail(category, selectedMonth))
                } label: {
                    compactContent
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                compactContent
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var fullContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(category.rawValue)
                    .fontWeight(.bold)

                Spacer()

                Text(utilization.formatted(.percent.precision(.fractionLength(0))))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            DashboardLinearProgressBar(
                progress: clampedUtilization,
                tint: tint,
                animation: reduceMotion ? nil : .dashboardProgress
            )
                .accessibilityHidden(true)

            HStack {
                HStack(spacing: 5) {
                    Text(spent.currencyString(code: config.ledgerCurrencyCode))
                        .fontWeight(.semibold)
                        .foregroundStyle(isOverBudget ? .red : .primary)
                    Text("of \(budget.currencyString(code: config.ledgerCurrencyCode))")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusText
                    .font(.caption)
                    .foregroundStyle(isOverBudget ? .red : .secondary)
            }
        }
    }

    private var statusText: Text {
        let code = config.ledgerCurrencyCode
        return switch status {
        case .noBudget: Text("No budget set")
        case .noTarget: Text("No savings target")
        case .underBudget(let remaining): Text("\(remaining.currencyString(code: code)) left")
        case .overBudget(let amount): Text("\(amount.currencyString(code: code)) over")
        case .belowTarget(let remaining): Text("\(remaining.currencyString(code: code)) to target")
        case .targetReached: Text("Target reached")
        }
    }

    private var compactContent: some View {
        VStack(spacing: 8) {
            Text(category.rawValue)
                .font(.subheadline)
                .fontWeight(.semibold)

            CircularProgressBar(progress: utilization, tint: tint, lineWidth: 10)
                .frame(width: 64, height: 64)

            Text("\(spent.currencyString(code: config.ledgerCurrencyCode)) of \(budget.currencyString(code: config.ledgerCurrencyCode))")
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DashboardLinearProgressBar: View {
    let progress: Double
    let tint: Color
    let animation: Animation?

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(.secondary.opacity(0.2))

            Capsule()
                .fill(tint)
                .scaleEffect(x: CGFloat(progress), anchor: .leading)
                .animation(animation, value: progress)
        }
        .frame(height: 4)
    }
}

#Preview("Full") {
    SingleCategoryUtilizationWidget(category: .wants, layout: .full, selectedMonth: .now)
        .environmentInjection()
}

#Preview("Compact") {
    SingleCategoryUtilizationWidget(category: .wants, layout: .compact, selectedMonth: .now)
        .environmentInjection()
}
