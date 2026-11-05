//
//  ExpenseSearchTool.swift
//  SageKit
//
//  Siri AI's expense search and expense cards. These types exist only in the iOS 27.3+ SDK,
//  so they're compiled out of released-Xcode builds, which App Store uploads require.
//

#if canImport(AppIntents, _version: 301.2)
import AppIntents
import Foundation
import SwiftUI

/// A search Siri fills in directly from what the person asked, such as
/// "dining expenses over $20 last month, largest first".
@available(iOS 27.3, *)
@AppEntity(.generable)
public struct ExpenseSearch: TransientAppEntity {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Expense Search"

    @Property(title: "From", description: "The first day to include. Leave empty to search from the earliest expense.")
    public var startDate: Date?

    @Property(title: "Through", description: "The last day to include; the whole day counts. Leave empty to search through today and later.")
    public var endDate: Date?

    @Property(title: "Text", description: "Words to find in the expense's name, note, or tag names, such as a store or item. Leave empty to match any text.")
    public var text: String?

    @Property(title: "Category", description: "Only expenses in this category: Needs, Wants, or Savings.")
    public var category: ExpenseCategory?

    @Property(title: "Tag Names", description: "Names of the person's own tags, such as \"Coffee\". An expense matches if it has any of them.")
    public var tagNames: [String]?

    @Property(title: "Minimum Amount", description: "Only expenses of at least this much, as a plain number in the ledger's currency.")
    public var minimumAmount: Double?

    @Property(title: "Maximum Amount", description: "Only expenses of at most this much, as a plain number in the ledger's currency.")
    public var maximumAmount: Double?

    @Property(title: "Order", description: "How to order the expenses. Use Largest First for questions about the biggest expenses.")
    public var order: ExpenseSearchOrder?

    @Property(title: "Limit", description: "The most expenses to list, from 1 to 100. Defaults to 25.")
    public var limit: Int?

    public var displayRepresentation: DisplayRepresentation { "Expense Search" }

    public init() { }

    var criteria: ExpenseSearchCriteria {
        ExpenseSearchCriteria(
            startDate: startDate,
            endDate: endDate,
            text: text,
            category: category,
            tagNames: tagNames ?? [],
            minimumAmount: minimumAmount,
            maximumAmount: maximumAmount,
            order: order ?? .newest,
            limit: limit
        )
    }
}

@available(iOS 27.3, *)
@AppIntent(.tool)
public struct SearchExpensesIntent: AppIntent {
    public static var title: LocalizedStringResource = "Search Expenses"
    public static var description = IntentDescription(
        "Lists the expenses that match a search, such as a date range, category, tags, text, or amount, along with how many matched and their total. Use it to show or compare specific expenses; for only a total, use the spending total tool."
    )
    public static var openAppWhenRun: Bool = false
    public static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Search", description: "What to look for, filled in from the person's request.")
    public var search: ExpenseSearch

    @Dependency
    var expenseStore: ExpenseStore

    public init() { }

    @MainActor
    public func perform() async throws -> some ReturnsValue<[ExpenseEntity]> & ProvidesDialog {
        let currencyCode = try LedgerCurrency.requireCode()
        let result = try expenseStore.searchExpenses(search.criteria)
        return .result(
            value: result.expenses.map(\.entity),
            dialog: IntentDialog(stringLiteral: result.dialog(currencyCode: currencyCode))
        )
    }
}

@available(iOS 27.3, *)
extension ExpenseEntity: SnippetRepresentableEntity {
    public static var snippet: some EntitySnippetContent<ExpenseEntity> {
        CardSnippet(supportedFamilies: [.standard]) { expense, _ in
            ExpenseCardView(expense: expense)
        }
    }
}
#endif
