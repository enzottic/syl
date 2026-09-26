import SageKit
import SwiftData
import SwiftUI

/// Keeps Stats' date window and oldest matching record live as expenses change.
struct StatsExpenseHistory<Content: View>: View {
    @Query private var windowExpenses: [Expense]
    @Query private var earliestExpense: [Expense]
    private let content: ([Expense], Date?) -> Content

    init(
        selectedMonth: Date,
        currentMonth: Date,
        category: ExpenseCategory?,
        tagID: UUID?,
        @ViewBuilder content: @escaping ([Expense], Date?) -> Content
    ) {
        _windowExpenses = Query(StatsExpenseFetchDescriptors.window(
            selectedMonth: selectedMonth, currentMonth: currentMonth
        ))
        _earliestExpense = Query(StatsExpenseFetchDescriptors.earliest(
            category: category, tagID: tagID
        ))
        self.content = content
    }

    var body: some View {
        content(windowExpenses, earliestExpense.first?.date)
    }
}
