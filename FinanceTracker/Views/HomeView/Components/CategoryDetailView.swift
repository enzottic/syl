//
//  CategoryDetailView.swift
//  FinanceTracker
//
//  Created by Enzo on 3/13/26.
//

import SwiftUI
import SwiftData
import SageKit

struct CategoryDetailView: View {
    @Environment(AppConfiguration.self) private var config
    @Environment(\.categoryColors) private var categoryColors
    
    let category: ExpenseCategory
    let month: Date

    @Query(sort: [SortDescriptor(\Expense.date, order: .reverse)])
    private var monthExpenses: [Expense]

    init(category: ExpenseCategory, month: Date) {
        self.category = category
        self.month = month

        _monthExpenses = Query(ExpenseFetchDescriptors.month(month))
    }

    var expenses: [Expense] {
        monthExpenses.filter { $0.category == category }
    }
    
    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Text("Spending")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(expenses.total.currencyString(code: config.ledgerCurrencyCode))
                        .font(.largeTitle.bold())
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
            }

            if !expenses.isEmpty {
                Section {
                    TopSpendingBreakdown(
                        expenses: expenses,
                        accentColor: category.color(in: categoryColors),
                        untaggedLabel: "Untagged"
                    )
                } header: {
                    Text("Top Tags")
                        .font(.subheadline)
                }
            }

            Section {
                ExpenseList(expenses: expenses)
            } header: {
                Text("Recent Purchases")
                    .font(.subheadline)
            }
        }
        .navigationTitle(category.rawValue)
        .navigationSubtitle(month.formatted(.dateTime.month(.wide).year()))
        .navigationBarTitleDisplayMode(.large)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .background(.sageBackground)
        .gradientBackground(color: category.color(in: categoryColors))
    }
}

#Preview {
    NavigationStack {
        CategoryDetailView(category: .wants, month: .now)
    }
    .environmentInjection()
}
