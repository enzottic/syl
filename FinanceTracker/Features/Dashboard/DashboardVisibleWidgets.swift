import SwiftUI
import SwiftData
import SageKit

/// Filter before forming rows, so temporarily empty cards don't leave holes.
struct DashboardVisibleWidgets<Content: View>: View {
    @Query private var monthlyExpenses: [Expense]
    @Query private var recurringRules: [RecurringExpenseRule]
    let selectedMonth: Date
    let order: [DashboardWidgetID]
    let content: ([DashboardWidgetID]) -> Content

    init(selectedMonth: Date, order: [DashboardWidgetID], @ViewBuilder content: @escaping ([DashboardWidgetID]) -> Content) {
        _monthlyExpenses = expenseQuery(for: selectedMonth)
        self.selectedMonth = selectedMonth
        self.order = order
        self.content = content
    }

    var body: some View {
        let hasTags = monthlyExpenses.contains { ($0.tags ?? []).contains { !$0.isDeleted } }
        let hasUpcoming = recurringRules.contains { $0.nextOccurrence(calendar: .current) != nil }
        let isCurrentMonth = Calendar.current.isDate(selectedMonth, equalTo: .now, toGranularity: .month)
        content(order.filter {
            switch $0 {
            case .mostSpentTags: hasTags
            case .upcomingRecurring: isCurrentMonth && hasUpcoming
            case .recentExpenses: isCurrentMonth && !monthlyExpenses.isEmpty
            default: true
            }
        })
    }
}
