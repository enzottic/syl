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

// Released Xcode lacks the 27.3 SDK, and the `@AppIntent(.tool)` macro would make the whole type 27.3+.
#if canImport(AppIntents, _version: 301.2)
@available(iOS 27.3, *)
extension OpenExpenseIntent: ToolIntent { }
#endif

@MainActor @Observable
public final class ExpenseOpenRequest {
    public static let shared = ExpenseOpenRequest()
    public var expenseID: UUID?
}
