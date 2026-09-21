//
//  AddExpenseIntent.swift
//  SageKit
//
//  Created by Enzo on 6/8/26.
//

import Foundation
import AppIntents
import SwiftData

public struct AddExpenseAppIntent: AppIntent {
    public static var title: LocalizedStringResource = "Add New Expense"
    
    @Parameter(title: "Name") var name: String
    @Parameter(title: "Amount", requestValueDialog: "What is the amount?") var amount: IntentCurrencyAmount
    @Parameter(title: "Category", requestValueDialog: "Which category: Needs, Wants, or Savings?") var category: ExpenseCategory
    @Parameter(title: "Date") var date: Date?
    @Parameter(title: "Tag") var tag: ExpenseTagEntity?
    
    @Dependency
    var expenseStore: ExpenseStore

    // Tests supply their in-memory ledger's currency without touching shared preferences.
    var currencyCodeProvider: @Sendable () throws -> String = { try LedgerCurrency.requireCode() }

    public static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$name) for \(\.$amount) in \(\.$category)") {
            \.$date
            \.$tag
        }
    }

    public init() { }
    
    // MARK: Methods
    
    @MainActor
    public func perform() async throws -> some ReturnsValue<ExpenseEntity> & ProvidesDialog {
        let currencyCode = try currencyCodeProvider()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw $name.needsValueError("Enter an expense name.")
        }
        // Use the numeric amount in the ledger's currency, regardless of the spoken currency.
        // No currency conversion is performed.
        // Validate the original decimal before converting to the model's Double storage.
        // Conversion must not hide extra fractional digits supplied by the user.
        var decimalAmount = amount.amount
        guard !decimalAmount.isNaN else {
            throw $amount.needsValueError("\(MonetaryAmount.validationMessage(currencyCode: currencyCode))")
        }
        var roundedAmount = Decimal.zero
        NSDecimalRound(&roundedAmount, &decimalAmount, LedgerCurrency.fractionDigits(for: currencyCode), .plain)
        let expenseAmount = NSDecimalNumber(decimal: decimalAmount).doubleValue
        guard decimalAmount == roundedAmount,
              MonetaryAmount.isValid(expenseAmount, currencyCode: currencyCode) else {
            throw $amount.needsValueError("\(MonetaryAmount.validationMessage(currencyCode: currencyCode))")
        }

        let expense = Expense(
            name: trimmedName,
            amount: expenseAmount,
            category: category,
            date: date ?? .now
        )
        
        let entity = try expenseStore.addExpenseAndSave(expense, tagID: tag?.id)
        let formattedAmount = expenseAmount.currencyString(code: currencyCode)
        return .result(value: entity, dialog: "Added \(trimmedName) for \(formattedAmount).")
    }
}
