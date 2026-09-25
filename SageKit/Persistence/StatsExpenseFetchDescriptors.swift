import Foundation
import SwiftData

/// The dates needed by Stats' selected-month summary and six history bars.
public enum StatsExpenseFetchDescriptors {
    public static func window(
        selectedMonth: Date,
        currentMonth: Date,
        calendar: Calendar = .current
    ) -> FetchDescriptor<Expense> {
        let recentStart = calendar.date(byAdding: .month, value: -5, to: currentMonth)!
        let chartEnd = selectedMonth < recentStart ? selectedMonth : currentMonth
        let start = calendar.date(byAdding: .month, value: -6, to: selectedMonth)!
        let end = calendar.date(byAdding: .month, value: 1, to: chartEnd)!
        return ExpenseFetchDescriptors.range(start: start, end: end)
    }

    /// The first matching record establishes which months are known history.
    /// Fetching one row keeps the average's zero-spend gaps without loading old expenses.
    public static func earliest(category: ExpenseCategory?, tagID: UUID?) -> FetchDescriptor<Expense> {
        let predicate: Predicate<Expense>?
        switch (category, tagID) {
        case (let category?, let tagID?):
            predicate = #Predicate { expense in
                expense.category == category &&
                (expense.tags?.contains { $0.id == tagID } == true)
            }
        case (let category?, nil):
            predicate = #Predicate { $0.category == category }
        case (nil, let tagID?):
            predicate = #Predicate { expense in
                expense.tags?.contains { $0.id == tagID } == true
            }
        case (nil, nil):
            predicate = nil
        }

        var descriptor = FetchDescriptor<Expense>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.date)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }
}
