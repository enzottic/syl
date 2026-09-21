//
//  FindExpensesIntent.swift
//  FinanceTracker
//

import Foundation
import AppIntents
import SwiftData

public enum ExpenseTimePeriod: String, AppEnum {
    case today
    case yesterday
    case thisWeek
    case lastWeek
    case thisMonth
    case lastMonth

    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Time Period"

    public static var caseDisplayRepresentations: [ExpenseTimePeriod: DisplayRepresentation] = [
        .today: "Today",
        .yesterday: "Yesterday",
        .thisWeek: "This Week",
        .lastWeek: "Last Week",
        .thisMonth: "This Month",
        .lastMonth: "Last Month",
    ]

    public var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date.now
        switch self {
        case .today:
            let start = calendar.startOfDay(for: now)
            return (start, calendar.date(byAdding: .day, value: 1, to: start) ?? now)
        case .yesterday:
            let today = calendar.startOfDay(for: now)
            return (calendar.date(byAdding: .day, value: -1, to: today) ?? today, today)
        case .thisWeek:
            let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            return (start, calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? now)
        case .lastWeek:
            let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            let start = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) ?? thisWeekStart
            return (start, thisWeekStart)
        case .thisMonth:
            let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
            return (start, calendar.date(byAdding: .month, value: 1, to: start) ?? now)
        case .lastMonth:
            let thisMonthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
            let start = calendar.date(byAdding: .month, value: -1, to: thisMonthStart) ?? thisMonthStart
            return (start, thisMonthStart)
        }
    }

    var dialogDescription: String {
        switch self {
        case .today: "today"
        case .yesterday: "yesterday"
        case .thisWeek: "this week"
        case .lastWeek: "last week"
        case .thisMonth: "this month"
        case .lastMonth: "last month"
        }
    }
}

public struct FindExpensesIntent: AppIntent {
    public static var title: LocalizedStringResource = "Find Expenses"
    public static var openAppWhenRun: Bool = false
    public static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    

    @Parameter(title: "Time Period", default: .thisMonth) public var timePeriod: ExpenseTimePeriod
    @Parameter(title: "Tag") public var tag: ExpenseTagEntity?
    @Parameter(title: "Category") public var category: ExpenseCategory?
    @Parameter(title: "Name Contains") public var nameFilter: String?

    @Dependency
    var expenseStore: ExpenseStore

    public static var parameterSummary: some ParameterSummary {
        Summary("How much did I spend \(\.$timePeriod)?") {
            \.$tag
            \.$category
            \.$nameFilter
        }
    }

    public init() { }
    
    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Double> {
        let (start, end) = timePeriod.dateRange
        var expenses = expenseStore.fetchExpenses(from: start, to: end)

        if let tag {
            expenses = expenses.filter { ($0.tags ?? []).contains { $0.id == tag.id } }
        }
        if let category {
            expenses = expenses.filter { $0.category == category }
        }
        if let nameFilter, !nameFilter.isEmpty {
            expenses = expenses.filter { $0.name.localizedCaseInsensitiveContains(nameFilter) }
        }

        let total = expenses.total
        let period = timePeriod.dialogDescription

        if let tag, let category {
            return .result(value: total, dialog: "You spent \(total.currencyString) on \(tag.name.lowercased()) in \(category.rawValue.lowercased()) \(period).")
        } else if let tag {
            return .result(value: total, dialog: "You spent \(total.currencyString) on \(tag.name.lowercased()) \(period).")
        } else if let category {
            return .result(value: total, dialog: "You spent \(total.currencyString) on \(category.rawValue.lowercased()) \(period).")
        } else if let nameFilter, !nameFilter.isEmpty {
            return .result(value: total, dialog: "You spent \(total.currencyString) on \"\(nameFilter)\" \(period).")
        }
        return .result(value: total, dialog: "You spent \(total.currencyString) \(period).")
    }
}
