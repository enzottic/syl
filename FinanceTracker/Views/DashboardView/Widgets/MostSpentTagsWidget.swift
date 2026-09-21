//
//  MostSpentTagsWidget.swift
//  FinanceTracker
//
//  Created by Enzo on 8/17/26.
//
import SwiftUI
import SwiftData
import SageKit

struct MostSpentTagsWidget: View {
    @Query private var monthlyExpenses: [Expense]

    let layout: DashboardWidgetLayout

    private var hasTaggedExpenses: Bool {
        monthlyExpenses.contains { expense in
            (expense.tags ?? []).contains { !$0.isDeleted }
        }
    }

    init(
        selectedMonth: Date,
        layout: DashboardWidgetLayout = .full
    ) {
        _monthlyExpenses = expenseQuery(for: selectedMonth)
        self.layout = layout
    }

    var body: some View {
        if hasTaggedExpenses {
            if layout == .compact {
                VStack(alignment: .leading, spacing: 8) {
                    header
                        .padding(.horizontal, 16)
                    breakdown
                }
                .padding(.top, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(
                    Color(.secondarySystemGroupedBackground),
                    in: .rect(cornerRadius: DashboardCardStyle.cornerRadius)
                )
            } else {
                Section {
                    breakdown
                } header: {
                    header
                }
            }
        }
    }

    private var header: some View {
        Text("Top Tags")
            .font(.subheadline)
            .fontWeight(.semibold)
    }

    private var breakdown: some View {
        TopSpendingBreakdown(
            expenses: monthlyExpenses,
            accentColor: .sage,
            maximumRows: 3,
            includesUntaggedExpenses: false,
            contentPadding: layout == .compact ? 16 : 0,
            showsCardBackground: false
        )
    }
}

#Preview {
    MostSpentTagsWidget(selectedMonth: .now)
        .environmentInjection()
}

#Preview("Empty State") {
    MostSpentTagsWidget(selectedMonth: .now)
        .environmentInjection(empty: true)
}
