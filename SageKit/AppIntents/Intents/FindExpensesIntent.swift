//
//  FindExpensesIntent.swift
//  FinanceTracker
//

import Foundation
import AppIntents
import SwiftData
import SwiftUI

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

// The type keeps its original name so saved Shortcuts continue to resolve it.
public struct FindExpensesIntent: AppIntent {
    public static var title: LocalizedStringResource = "Get Spending Total"
    public static var description = IntentDescription(
        "Adds up what was spent in a time period, optionally only for one tag, one category, or expenses whose name contains some text. Returns the total in the ledger's currency."
    )
    public static var openAppWhenRun: Bool = false
    public static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(
        title: "Time Period",
        description: "The calendar period to total. Weeks and months follow the device's calendar.",
        default: .thisMonth
    )
    public var timePeriod: ExpenseTimePeriod

    @Parameter(title: "Tag", description: "Only count expenses with this tag.")
    public var tag: ExpenseTagEntity?

    @Parameter(title: "Category", description: "Only count expenses in this category: Needs, Wants, or Savings.")
    public var category: ExpenseCategory?

    @Parameter(title: "Name Contains", description: "Only count expenses whose name contains this text, ignoring case.")
    public var nameFilter: String?

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
    public func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Double> & ShowsSnippetView {
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
        let dialog: String
        if let tag, let category {
            dialog = "You spent \(total.currencyString) on \(tag.name.lowercased()) in \(category.rawValue.lowercased()) \(period)."
        } else if let tag {
            dialog = "You spent \(total.currencyString) on \(tag.name.lowercased()) \(period)."
        } else if let category {
            dialog = "You spent \(total.currencyString) on \(category.rawValue.lowercased()) \(period)."
        } else if let nameFilter, !nameFilter.isEmpty {
            dialog = "You spent \(total.currencyString) on \"\(nameFilter)\" \(period)."
        } else {
            dialog = "You spent \(total.currencyString) \(period)."
        }
        let filters = [tag?.name, category?.rawValue, nameFilter.flatMap { $0.isEmpty ? nil : "\u{201C}\($0)\u{201D}" }]
        return .result(
            value: total,
            dialog: IntentDialog(stringLiteral: dialog),
            view: AmountSummarySnippetView(
                title: "Spent \(period)",
                amount: total,
                detail: SpendingSummary.detail(count: expenses.count, filters: filters)
            )
        )
    }
}

// Released Xcode lacks the 27.3 SDK, and the `@AppIntent(.tool)` macro would make the whole type 27.3+.
#if canImport(AppIntents, _version: 301.2)
@available(iOS 27.3, *)
extension FindExpensesIntent: ToolIntent { }
#endif
