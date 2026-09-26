import SwiftUI
import SwiftData
import SageKit

/// Filter before forming rows, so temporarily empty cards don't leave holes.
struct DashboardVisibleWidgets<Content: View>: View {
    @Query private var monthlyExpenses: [Expense]
    @Query private var recurringRules: [RecurringExpenseRule]
    let order: [DashboardWidgetID]
    let content: ([DashboardWidgetID]) -> Content

    init(selectedMonth: Date, order: [DashboardWidgetID], @ViewBuilder content: @escaping ([DashboardWidgetID]) -> Content) {
        _monthlyExpenses = expenseQuery(for: selectedMonth)
        self.order = order
        self.content = content
    }

    var body: some View {
        let hasTags = monthlyExpenses.contains { ($0.tags ?? []).contains { !$0.isDeleted } }
        let hasUpcoming = recurringRules.contains { $0.nextOccurrence(calendar: .current) != nil }
        content(order.filter {
            switch $0 {
            case .mostSpentTags: hasTags
            case .upcomingRecurring: hasUpcoming
            case .recentExpenses: !monthlyExpenses.isEmpty
            default: true
            }
        })
    }
}
