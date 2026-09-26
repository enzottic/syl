//
//  GetBudgetRemainingIntent.swift
//  FinanceTracker
//

import Foundation
import AppIntents
import SwiftData

public struct GetBudgetRemainingIntent: AppIntent {
    public static var title: LocalizedStringResource = "Check Budget Remaining"
    public static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Category") public var category: ExpenseCategory?

    @Dependency
    var expenseStore: ExpenseStore

    public static var parameterSummary: some ParameterSummary {
        Summary("How much budget do I have left?") {
            \.$category
        }
    }
    
    public init() { }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let status = try expenseStore.budgetStatus(for: category)
        return .result(dialog: IntentDialog(Self.dialog(for: status, category: category)))
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
