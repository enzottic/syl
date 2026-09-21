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
        if let category {
            let remaining = try expenseStore.remainingBudget(for: category)
            if remaining >= 0 {
                return .result(dialog: "You have \(remaining.currencyString) remaining in your \(category.rawValue.lowercased()) budget.")
            } else {
                return .result(dialog: "You're \((-remaining).currencyString) over your \(category.rawValue.lowercased()) budget.")
            }
        } else {
            let remaining = try expenseStore.totalRemainingBudget()
            if remaining >= 0 {
                return .result(dialog: "You have \(remaining.currencyString) left across all budgets this month.")
            } else {
                return .result(dialog: "You're \((-remaining).currencyString) over your total budget this month.")
            }
        }
    }
}
