import AppIntents
import SwiftUI

public struct GetMonthlySpendingTotalIntent: AppIntent {
    public static var title: LocalizedStringResource = "Monthly Spending Total"
    public static var openAppWhenRun: Bool = false
    public static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Category") public var category: ExpenseCategory?
    @Parameter(title: "Tag") public var tag: ExpenseTagEntity?

    @Dependency
    var expenseStore: ExpenseStore

    public static var parameterSummary: some ParameterSummary {
        Summary("Get this month's spending total") {
            \.$category
            \.$tag
        }
    }

    public init() { }

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog & ShowsSnippetView {
        var expenses = try expenseStore.fetchExpenses(for: .now)
        if let category {
            expenses = expenses.filter { $0.category == category }
        }
        if let tag {
            expenses = expenses.filter { ($0.tags ?? []).contains { $0.id == tag.id } }
        }
        let total = expenses.total
        let dialog: String
        if let tag, let category {
            dialog = "You've spent \(total.currencyString) on \(tag.name.lowercased()) in \(category.rawValue.lowercased()) this month."
        } else if let tag {
            dialog = "You've spent \(total.currencyString) on \(tag.name.lowercased()) this month."
        } else if let category {
            dialog = "You've spent \(total.currencyString) on \(category.rawValue.lowercased()) this month."
        } else {
            dialog = "You've spent \(total.currencyString) this month."
        }
        return .result(
            value: total,
            dialog: IntentDialog(stringLiteral: dialog),
            view: AmountSummarySnippetView(
                title: "Spent this month",
                amount: total,
                detail: SpendingSummary.detail(count: expenses.count, filters: [tag?.name, category?.rawValue])
            )
        )
    }
}
