//
//  GetBudgetRemainingIntent.swift
//  FinanceTracker
//

import Foundation
import AppIntents
import SwiftData
import SwiftUI

public struct GetBudgetRemainingIntent: AppIntent {
    public static var title: LocalizedStringResource = "Check Budget Remaining"
    public static var description = IntentDescription(
        "Tells how much of this month's budget is left, or how far over it is. For Savings, tells how far from the month's savings target. Without a category, covers the total budget."
    )
    public static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(
        title: "Category",
        description: "The budget to check: Needs, Wants, or Savings. Leave empty for the total budget."
    )
    public var category: ExpenseCategory?

    @Dependency
    var expenseStore: ExpenseStore

    public static var parameterSummary: some ParameterSummary {
        Summary("How much budget do I have left?") {
            \.$category
        }
    }
    
    public init() { }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let status = try expenseStore.budgetStatus(for: category)
        let spent = try category.map { try expenseStore.monthlyTotal(category: $0) } ?? expenseStore.monthlyTotal()
        let budget = category.map(expenseStore.budget(for:)) ?? expenseStore.totalBudget()
        let summary = BudgetSummary(status: status, category: category, spent: spent, budget: budget)
        return .result(
            dialog: IntentDialog(Self.dialog(for: status, category: category)),
            view: AmountSummarySnippetView(
                title: summary.title,
                amount: summary.amount,
                detail: summary.detail,
                progress: summary.progress,
                tint: category.map { CategoryColors.load().color(for: $0) } ?? .accentColor
            )
        )
    }

    /// What Siri says for a budget status. With no category, `status` is for the total budget.
    static func dialog(for status: BudgetStatus, category: ExpenseCategory?) -> LocalizedStringResource {
        guard let category else {
            switch status {
            case .underBudget(let remaining):
                return "You have \(remaining.currencyString) left across all budgets this month."
            case .overBudget(let amount):
                return "You're \(amount.currencyString) over your total budget this month."
            // The total is a spending limit, so the savings-target statuses don't occur.
            case .noBudget, .noTarget, .belowTarget, .targetReached:
                return "You haven't set a monthly budget."
            }
        }
        let name = category.rawValue.lowercased()
        switch status {
        case .noBudget:
            return "You haven't set a \(name) budget."
        case .noTarget:
            return "You haven't set a savings target."
        case .underBudget(let remaining):
            return "You have \(remaining.currencyString) remaining in your \(name) budget."
        case .overBudget(let amount):
            return "You're \(amount.currencyString) over your \(name) budget."
        case .belowTarget(let remaining):
            return "You're \(remaining.currencyString) away from your savings target this month."
        case .targetReached:
            return "You've reached your savings target this month."
        }
    }
}

// Siri AI tool, built only with the iOS 27.3+ SDK so released Xcode can still archive Syl.
// Declared here because the `@AppIntent(.tool)` macro needs the whole type to be 27.3+.
#if canImport(AppIntents, _version: 301.2)
@available(iOS 27.3, *)
extension GetBudgetRemainingIntent: ToolIntent { }

struct BudgetSummary: Equatable {
    let title: String
    let amount: Double
    let detail: String?
    let progress: Double?

    init(status: BudgetStatus, category: ExpenseCategory?, spent: Double, budget: Double) {
        let name = category.map { "\($0.rawValue) budget" } ?? "total budget"
        let used = budget > 0 ? spent / budget : nil
        let ofBudget = "\(spent.currencyString) of \(budget.currencyString)"
        switch status {
        case .underBudget(let remaining):
            self.init(title: "Left in your \(name)", amount: remaining, detail: "\(ofBudget) spent this month", progress: used)
        case .overBudget(let amount):
            self.init(title: "Over your \(name)", amount: amount, detail: "\(ofBudget) spent this month", progress: used)
        case .belowTarget(let remaining):
            self.init(title: "To go for your savings target", amount: remaining, detail: "\(ofBudget) saved this month", progress: used)
        case .targetReached:
            self.init(title: "Saved this month", amount: spent, detail: "Savings target of \(budget.currencyString) reached", progress: used)
        case .noBudget, .noTarget:
            self.init(title: "Spent this month", amount: spent, detail: "No budget set", progress: nil)
        }
    }

    private init(title: String, amount: Double, detail: String?, progress: Double?) {
        self.title = title
        self.amount = amount
        self.detail = detail
        self.progress = progress
    }
}

enum SpendingSummary {
    static func detail(count: Int, filters: [String?]) -> String {
        let countText = count == 1 ? "1 expense" : "\(count) expenses"
        return ([countText] + filters.compactMap { $0 }).joined(separator: " · ")
    }
}
#endif
