//
//  DashboardWidget.swift
//  FinanceTracker
//
//  Created by Enzo on 7/12/26.
//
import Foundation
import SageKit

enum DashboardCardStyle {
    static let cornerRadius: CGFloat = 24
}

/// How a widget renders inside its dashboard column.
enum DashboardWidgetLayout: Codable, Hashable {
    case full
    case compact
}

enum DashboardWidget: Hashable, Codable {
    case monthlyOverview
    case expenseCalendar
    case mostSpentTags
    case categoryUtilization
    case upcomingRecurring
    case recentExpenses(ExpenseRowItem.Style)
}
