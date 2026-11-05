//
//  DeleteExpenseIntent.swift
//  SageKit
//

import Foundation
import AppIntents
import SwiftData
import WidgetKit

public struct DeleteExpenseIntent: AppIntent {
    public static var title: LocalizedStringResource = "Delete Expense"
    public static var description = IntentDescription(
        "Deletes one expense from Syl after confirming. For a recurring expense, only this occurrence is deleted; future ones still arrive."
    )
    public static var openAppWhenRun: Bool = false
    public static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Expense", description: "The expense to delete.")
    public var expense: ExpenseEntity

    @Dependency
    var expenseStore: ExpenseStore

    public static var parameterSummary: some ParameterSummary {
        Summary("Delete \(\.$expense)")
    }

    public init() { }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        // App Intents has no Delete action name, so the prompt itself says what will happen.
        try await requestConfirmation(
            dialog: "Delete \(expense.name) for \(expense.amount.currencyString)? This can't be undone."
        )
        try deleteConfirmed()
        return .result(dialog: "Deleted \(expense.name).")
    }

    /// Separate from `perform()` so tests can skip the system prompt.
    @MainActor
    func deleteConfirmed() throws {
        try expenseStore.deleteExpenseAndSave(id: expense.id)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// Released Xcode lacks the 27.3 SDK, and the `@AppIntent(.tool)` macro would make the whole type 27.3+.
#if canImport(AppIntents, _version: 301.2)
@available(iOS 27.3, *)
extension DeleteExpenseIntent: ToolIntent { }
#endif
