//
//  OpenExpenseIntent.swift
//  SageKit
//

import Foundation
import AppIntents
import Observation

public struct OpenExpenseIntent: OpenIntent {
    public static var title: LocalizedStringResource = "Open Expense"
    public static var description = IntentDescription("Opens an expense's details in Syl, where it can be edited.")
    public static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Expense", description: "The expense to show.")
    public var target: ExpenseEntity

    public init() { }

    @MainActor
    public func perform() async throws -> some IntentResult {
        ExpenseOpenRequest.shared.expenseID = target.id
        return .result()
    }
}

@available(iOS 27.3, *)
extension OpenExpenseIntent: ToolIntent { }

/// Hands an expense from `OpenExpenseIntent` to the app's navigation, which shows it once
/// no sheet is in the way and then clears the request.
@MainActor @Observable
public final class ExpenseOpenRequest {
    public static let shared = ExpenseOpenRequest()
    public var expenseID: UUID?
}
