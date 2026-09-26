//
//  MonthExpensesList.swift
//  FinanceTracker
//
//  Created by Enzo on 3/13/26.
//
import SwiftUI
import SwiftData
import SageKit

struct MonthExpensesList: View {
    @Query private var expenses: [Expense]
    var searchText: String

    init(month: Date, searchText: String = "") {
        _expenses = Query(ExpenseFetchDescriptors.month(month))
        self.searchText = searchText
    }
    
    var filteredExpenses: [Expense] {
        if searchText.isEmpty { return expenses }
        return expenses.filter { expense in
            expense.name.localizedCaseInsensitiveContains(searchText)
            || expense.note.localizedCaseInsensitiveContains(searchText)
            || (expense.tags ?? []).contains { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var groupedExpenses: [Date: [Expense]] {
        Dictionary(grouping: filteredExpenses) { expense in
            Calendar.current.startOfDay(for: expense.date)
        }
    }
    
    var sortedDates: [Date] {
        groupedExpenses.keys.sorted(by: >)
    }

    var body: some View {
        VStack {
            if (filteredExpenses.isEmpty) {
                ContentUnavailableView(
                    searchText.isEmpty ? "No expenses for this month" : "No matching expenses",
                    systemImage: searchText.isEmpty ? "receipt" : "magnifyingglass",
                )
            } else {
                List {
                    ForEach(sortedDates, id: \.self) { date in
                        let expenses = groupedExpenses[date] ?? []
                        Section {
                            ExpenseList(expenses: expenses)
                        } header: {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
           }
        }
    }
}

#Preview {
    @Previewable @State var month = Date()

    NavigationStack {
        MonthExpensesList(month: month)
    }
    .environmentInjection()
}
