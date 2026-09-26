//
//  RecentExpensesWidget.swift
//  FinanceTracker
//
//  Created by Enzo on 7/12/26.
//
import SwiftUI
import SwiftData
import SageKit

struct RecentExpensesDashboardWidget: View {
    @Environment(AppConfiguration.self) var config
    @Environment(AppRouter.self) var appRouter
    
    @Query var recentExpenses: [Expense]
    let selectedMonth: Date
    let rowStyle: ExpenseRowItem.Style
    let embedsList: Bool
    @State private var rowHeights: [PersistentIdentifier: CGFloat] = [:]

    init(
        selectedMonth: Date = .now,
        rowStyle: ExpenseRowItem.Style = .condensed,
        embedsList: Bool = false
    ) {
        _recentExpenses = expenseQuery(for: selectedMonth, limit: 5)
        self.selectedMonth = selectedMonth
        self.rowStyle = rowStyle
        self.embedsList = embedsList
    }

    var body: some View {
        if !recentExpenses.isEmpty {
            Section {
                if embedsList {
                    List {
                        ExpenseList(expenses: recentExpenses, rowStyle: rowStyle) { id, height in
                            rowHeights[id] = height
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .environment(\.defaultMinListRowHeight, 44)
                    .listRowSpacing(0)
                    .contentMargins(0, for: .scrollContent)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .frame(height: listHeight)
                } else {
                    ExpenseList(expenses: recentExpenses, rowStyle: rowStyle)
                }
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Recent Expenses")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Button("Show All") {
                        appRouter.showExpenses(for: selectedMonth)
                    }
                    .accessibilityIdentifier("show-all-expenses-button")
                    .font(.subheadline)
                }
            }
        }
    }

    // A List needs an explicit height inside the dashboard ScrollView. Measure
    // its row content so the card also fits larger text and shrinks on deletion.
    private var listHeight: CGFloat {
        recentExpenses.reduce(0) { height, expense in
            let contentHeight = rowHeights[expense.persistentModelID]
                ?? (rowStyle == .regular ? 48 : 32)
            return height + max(44, contentHeight + 12)
        }
    }
}

#Preview {
    List {
        RecentExpensesDashboardWidget(selectedMonth: .now)
            .environmentInjection()
    }
}
