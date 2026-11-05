//
//  UpdateExpenseIntent.swift
//  SageKit
//

import Foundation
import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

public struct UpdateExpenseIntent: AppIntent {
    public static var title: LocalizedStringResource = "Update Expense"
    public static var description = IntentDescription(
        "Changes details of an existing expense in Syl. Only the values provided are changed; everything else stays as it was."
    )
    public static var openAppWhenRun: Bool = false
    public static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Expense", description: "The expense to change.")
    public var expense: ExpenseEntity

    @Parameter(title: "Name", description: "A new name for what the money was spent on.")
    public var name: String?

    @Parameter(
        title: "Amount",
        description: "A new amount. Syl records the number in the ledger's currency and never converts it. A negative amount is a refund."
    )
    public var amount: IntentCurrencyAmount?

    @Parameter(title: "Category", description: "A new category: Needs, Wants, or Savings.")
    public var category: ExpenseCategory?

    @Parameter(title: "Date", description: "A new date for when the money was spent.")
    public var date: Date?

    @Parameter(title: "Tags", description: "Tags that replace the expense's current tags.")
    public var tags: [ExpenseTagEntity]?

    @Parameter(title: "Note", description: "A note that replaces the expense's current note. An empty note removes it.")
    public var note: String?

    @Dependency
    var expenseStore: ExpenseStore

    var currencyCodeProvider: @Sendable () throws -> String = { try LedgerCurrency.requireCode() }

    public static var parameterSummary: some ParameterSummary {
        Summary("Update \(\.$expense)") {
            \.$name
            \.$amount
            \.$category
            \.$date
            \.$tags
            \.$note
        }
    }

    public init() { }

    @MainActor
    public func perform() async throws -> some ReturnsValue<ExpenseEntity> & ProvidesDialog & ShowsSnippetView {
        let currencyCode = try currencyCodeProvider()
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedName, trimmedName.isEmpty {
            throw $name.needsValueError("Enter an expense name.")
        }
        var newAmount: Double?
        if let amount {
            guard let value = IntentAmount.ledgerValue(of: amount, currencyCode: currencyCode) else {
                throw $amount.needsValueError("\(MonetaryAmount.validationMessage(currencyCode: currencyCode))")
            }
            newAmount = value
        }
        guard trimmedName != nil || newAmount != nil || category != nil || date != nil
                || tags != nil || note != nil else {
            throw UpdateError.nothingToChange
        }

        let tagIDs = tags?.map(\.id)
        let updated = try expenseStore.updateExpenseAndSave(id: expense.id) { model, context in
            if let trimmedName { model.name = trimmedName }
            if let newAmount { model.amount = newAmount }
            if let category { model.category = category }
            if let date { model.date = date }
            if let note { model.note = note.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let tagIDs { model.tags = try ExpenseStore.tags(withIDs: tagIDs, in: context) }
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result(
            value: updated,
            dialog: "Updated \(updated.name): \(updated.amount.currencyString(code: currencyCode)) in \(updated.category.rawValue).",
            view: ExpenseCardView(expense: updated)
        )
    }

    enum UpdateError: Error, CustomLocalizedStringResourceConvertible {
        case nothingToChange

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .nothingToChange: "Say what to change, such as the amount, name, category, date, tags, or note."
            }
        }
    }
}

// Released Xcode lacks the 27.3 SDK, and the `@AppIntent(.tool)` macro would make the whole type 27.3+.
#if canImport(AppIntents, _version: 301.2)
@available(iOS 27.3, *)
extension UpdateExpenseIntent: ToolIntent { }
#endif
