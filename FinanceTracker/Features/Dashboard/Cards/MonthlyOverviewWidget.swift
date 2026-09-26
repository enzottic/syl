//
//  MonthlyOverviewWidget.swift
//  FinanceTracker
//
//  Created by Enzo on 7/12/26.
//
import SwiftUI
import SwiftData
import SageKit

struct MonthlyOverviewWidget: View {
    @Environment(AppConfiguration.self) private var config
    @Environment(\.categoryColors) private var categoryColors

    private let calendar = Calendar.current
    private let selectedMonth: Date

    @Query var monthlyExpenses: [Expense]
    @Query var comparisonExpenses: [Expense]

    private var totalSpent: Double { monthlyExpenses.total }

    private var totalBudget: Double { Double(config.totalMonthlyIncome) }

    private var totalUtilization: Double {
        totalBudget == 0 ? 0 : totalSpent / totalBudget
    }

    private var remaining: Double { max(totalBudget - totalSpent, 0) }

    private var isOverBudget: Bool { totalSpent > totalBudget + 0.001 }

    private var tint: Color { isOverBudget ? .red : .sage }

    init(selectedMonth: Date) {
        self.selectedMonth = selectedMonth
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
        let startOfLastMonth = calendar.dateInterval(of: .month, for: lastMonth)?.start ?? lastMonth
        let endOfSelectedMonth = calendar.dateInterval(of: .month, for: selectedMonth)?.end ?? selectedMonth

        _monthlyExpenses = expenseQuery(for: selectedMonth)
        _comparisonExpenses = expenseQuery(start: startOfLastMonth, end: endOfSelectedMonth)
    }
    
    var body: some View {
        let summary = SpendingMonthSummary(month: selectedMonth, expenses: comparisonExpenses)
        Section {
            VStack(spacing: 12) {
                ArcProgressGauge(progress: totalUtilization, tint: tint) {
                    gaugeLabel
                }
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

                HStack {
                    Text(isOverBudget
                         ? "\((totalSpent - totalBudget).currencyString(code: config.ledgerCurrencyCode)) over"
                         : "\(remaining.currencyString(code: config.ledgerCurrencyCode)) remaining")
                        .font(.subheadline)
                        .foregroundStyle(isOverBudget ? .red : .secondary)

                    Spacer()

                    if summary.previousTotal > 0 {
                        trendPill(change: (summary.total - summary.previousTotal) / summary.previousTotal)
                    }
                }
            }
        }
    }

    private var gaugeLabel: some View {
        VStack(spacing: 2) {
            Text("Total Spent")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text(totalSpent.currencyString(code: config.ledgerCurrencyCode))
                .font(.largeTitle)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func trendPill(change: Double) -> some View {
        let isSpendingMore = change > 0
        let trendColor: Color = isSpendingMore ? .red : .green
        return HStack(spacing: 4) {
            Image(systemName: isSpendingMore ? "arrow.up.right" : "arrow.down.right")
                .foregroundStyle(trendColor)
            Text("\((abs(change)).formatted(.percent.precision(.fractionLength(0)))) vs last month")
        }
        .font(.caption)
        .fontWeight(.medium)
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(trendColor.opacity(0.12), in: .capsule)
    }
}

#Preview {
    MonthlyOverviewWidget(selectedMonth: .now)
        .environmentInjection()
}
