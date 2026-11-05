//
//  GetUpcomingRecurringExpensesIntent.swift
//  SageKit
//

import Foundation
import AppIntents

public struct GetUpcomingRecurringExpensesIntent: AppIntent {
    public static var title: LocalizedStringResource = "Get Upcoming Recurring Expenses"
    public static var description = IntentDescription(
        "Lists recurring expenses, such as subscriptions and bills, that are due soon, with their dates and total."
    )
    public static var openAppWhenRun: Bool = false
    public static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(
        title: "Days Ahead",
        description: "How many days ahead to look, from 1 to 365. Defaults to 30.",
        default: 30,
        inclusiveRange: (1, 365)
    )
    public var days: Int

    @Dependency
    var expenseStore: ExpenseStore

    var currencyCodeProvider: @Sendable () throws -> String = { try LedgerCurrency.requireCode() }

    public static var parameterSummary: some ParameterSummary {
        Summary("Get recurring expenses due in the next \(\.$days) days")
    }

    public init() { }

    @MainActor
    public func perform() async throws -> some ReturnsValue<[UpcomingExpenseEntity]> & ProvidesDialog {
        let currencyCode = try currencyCodeProvider()
        let upcoming = try expenseStore.upcomingRecurringExpenses(within: min(max(days, 1), 365))
        return .result(
            value: upcoming.map(UpcomingExpenseEntity.init),
            dialog: IntentDialog(stringLiteral: Self.dialog(for: upcoming, days: days, currencyCode: currencyCode))
        )
    }

    static func dialog(for upcoming: [UpcomingRecurringExpense], days: Int, currencyCode: String) -> String {
        let window = days == 1 ? "the next day" : "the next \(days) days"
        guard let first = upcoming.first else { return "No recurring expenses are due in \(window)." }
        let total = upcoming.reduce(0) { $0 + $1.amount }.currencyString(code: currencyCode)
        let next = "\(first.name) on \(first.date.formatted(.dateTime.month(.abbreviated).day()))"
        if upcoming.count == 1 {
            return "One recurring expense is due in \(window): \(next), for \(total)."
        }
        return "\(upcoming.count) recurring expenses are due in \(window), totaling \(total). Next is \(next)."
    }
}

#if canImport(AppIntents, _version: 301.2)
@available(iOS 27.3, *)
extension GetUpcomingRecurringExpensesIntent: ToolIntent { }
#endif

/// A future occurrence of a recurring expense, as Siri and Shortcuts see it.
public struct UpcomingExpenseEntity: TransientAppEntity {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Upcoming Expense"

    @Property(title: "Name") public var name: String
    @Property(title: "Amount") public var amount: Double
    @Property(title: "Category") public var category: ExpenseCategory
    @Property(title: "Due Date") public var date: Date

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(amount.currencyString) · \(date.formatted(date: .abbreviated, time: .omitted))"
        )
    }

    public init() {
        name = ""
        amount = 0
        category = .needs
        date = .now
    }

    init(_ upcoming: UpcomingRecurringExpense) {
        self.init()
        name = upcoming.name
        amount = upcoming.amount
        category = upcoming.category
        date = upcoming.date
    }
}
