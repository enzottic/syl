//
//  AddExpenseIntent.swift
//  SageKit
//
//  Created by Enzo on 6/8/26.
//

import Foundation
import AppIntents
import SwiftData
import WidgetKit

public struct AddExpenseAppIntent: AppIntent {
    public static var title: LocalizedStringResource = "Add New Expense"
    public static var description = IntentDescription(
        "Records a new expense in Syl. If no category is given, Syl uses the category of earlier expenses with the same name or tag, and asks when it can't tell."
    )
    public static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(
        title: "Name",
        description: "What the money was spent on, such as a store, service, or item, like \"Groceries\" or \"Netflix\"."
    )
    var name: String

    @Parameter(
        title: "Amount",
        description: "How much was spent. Syl records the number in the ledger's currency and never converts it. A negative amount is a refund.",
        requestValueDialog: "What is the amount?"
    )
    var amount: IntentCurrencyAmount

    @Parameter(
        title: "Category",
        description: "Needs are essentials like rent, bills, and groceries. Wants are non-essentials like dining out and entertainment. Savings is money set aside. Leave empty to let Syl choose from earlier expenses.",
        requestValueDialog: "Which category: Needs, Wants, or Savings?"
    )
    var category: ExpenseCategory?

    @Parameter(title: "Date", description: "When the money was spent. Defaults to now.")
    var date: Date?

    @Parameter(title: "Tags", description: "The person's own tags to file the expense under, if any.")
    var tags: [ExpenseTagEntity]?

    @Parameter(title: "Note", description: "Optional extra detail to keep with the expense.")
    var note: String?

    @Dependency
    var expenseStore: ExpenseStore

    // Tests supply their in-memory ledger's currency without touching shared preferences.
    var currencyCodeProvider: @Sendable () throws -> String = { try LedgerCurrency.requireCode() }

    public static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$name) for \(\.$amount)") {
            \.$category
            \.$date
            \.$tags
            \.$note
        }
    }

    public init() { }

    /// An intent describing an expense someone just added in the app, for donation.
    @MainActor
    public init(donating draft: ExpenseEntryDraft, amount: Double, currencyCode: String) {
        self.init()
        self.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Via the shortest decimal text, so 4.1 donates as 4.1 rather than Double's 4.0999….
        let decimal = Decimal(string: String(amount), locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(amount)
        self.amount = IntentCurrencyAmount(amount: decimal, currencyCode: currencyCode)
        self.category = draft.category
        self.date = draft.date
        self.tags = draft.tags.isEmpty ? nil : draft.tags.map(\.entity)
        let trimmedNote = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = trimmedNote.isEmpty ? nil : trimmedNote
    }

    // MARK: Methods

    @MainActor
    public func perform() async throws -> some ReturnsValue<ExpenseEntity> & ProvidesDialog {
        let currencyCode = try currencyCodeProvider()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw $name.needsValueError("Enter an expense name.")
        }
        guard let expenseAmount = IntentAmount.ledgerValue(of: amount, currencyCode: currencyCode) else {
            throw $amount.needsValueError("\(MonetaryAmount.validationMessage(currencyCode: currencyCode))")
        }
        let tagIDs = (tags ?? []).map(\.id)
        guard let resolvedCategory = try category
                ?? expenseStore.inferredCategory(forName: trimmedName, tagID: tagIDs.first) else {
            throw $category.needsValueError("Which category: Needs, Wants, or Savings?")
        }

        let expense = Expense(
            name: trimmedName,
            amount: expenseAmount,
            category: resolvedCategory,
            date: date ?? .now,
            note: note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
        let entity = try expenseStore.addExpenseAndSave(expense, tagIDs: tagIDs)
        WidgetCenter.shared.reloadAllTimelines()
        let formattedAmount = expenseAmount.currencyString(code: currencyCode)
        return .result(
            value: entity,
            dialog: "Added \(trimmedName) for \(formattedAmount) to \(resolvedCategory.rawValue)."
        )
    }
}

/// Converts an amount from Siri or Shortcuts to the ledger's stored value.
enum IntentAmount {
    /// The numeric amount in the ledger's currency, regardless of the spoken currency; no
    /// conversion is performed. Nil when the amount isn't a valid expense amount, including
    /// when it has more fractional digits than the ledger's currency allows.
    static func ledgerValue(of amount: IntentCurrencyAmount, currencyCode: String) -> Double? {
        // Validate the original decimal before converting to the model's Double storage,
        // so the conversion can't hide extra fractional digits.
        var decimalAmount = amount.amount
        guard !decimalAmount.isNaN else { return nil }
        var roundedAmount = Decimal.zero
        NSDecimalRound(&roundedAmount, &decimalAmount, LedgerCurrency.fractionDigits(for: currencyCode), .plain)
        let value = NSDecimalNumber(decimal: decimalAmount).doubleValue
        guard decimalAmount == roundedAmount,
              MonetaryAmount.isValid(value, currencyCode: currencyCode) else { return nil }
        return value
    }
}

// Siri AI tool, built only with the iOS 27.3+ SDK so released Xcode can still archive Syl.
// Declared here because the `@AppIntent(.tool)` macro needs the whole type to be 27.3+.
#if canImport(AppIntents, _version: 301.2)
@available(iOS 27.3, *)
extension AddExpenseAppIntent: ToolIntent { }
#endif
