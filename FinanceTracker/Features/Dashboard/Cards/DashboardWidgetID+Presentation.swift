import SwiftUI
import SageKit

extension DashboardWidgetID {
    var title: LocalizedStringKey {
        switch self {
        case .monthlyOverview: "Monthly Overview"
        case .categories: "Categories"
        case .expenseCalendar: "Expense Calendar"
        case .mostSpentTags: "Top Tags"
        case .upcomingRecurring: "Upcoming Expenses"
        case .recentExpenses: "Recent Expenses"
        }
    }

    var symbol: String {
        switch self {
        case .monthlyOverview: "chart.pie"
        case .categories: "chart.bar"
        case .expenseCalendar: "calendar"
        case .mostSpentTags: "tag"
        case .upcomingRecurring: "arrow.trianglehead.2.clockwise.rotate.90"
        case .recentExpenses: "list.bullet.rectangle"
        }
    }

    var widget: DashboardWidget {
        switch self {
        case .monthlyOverview: .monthlyOverview
        case .categories: .categoryUtilization
        case .expenseCalendar: .expenseCalendar
        case .mostSpentTags: .mostSpentTags
        case .upcomingRecurring: .upcomingRecurring
        case .recentExpenses: .recentExpenses(.regular)
        }
    }

}
