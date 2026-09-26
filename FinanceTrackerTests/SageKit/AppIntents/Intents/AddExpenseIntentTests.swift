import AppIntents
import Foundation
import SwiftData
import Testing
import UIKit
@testable import SageKit

@Suite("Add expense shortcut", .serialized)
struct AddExpenseIntentTests {
    @Test @MainActor
    func savesSelectedCategoryAndDate() async throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        var intent = AddExpenseAppIntent()
        intent.expenseStore = store
        intent.currencyCodeProvider = { "USD" }
        intent.name = "  Groceries  "
        intent.amount = IntentCurrencyAmount(amount: Decimal(string: "24.50")!, currencyCode: "USD")
        intent.category = .needs
        intent.date = Date(timeIntervalSince1970: 1_700_000_000)

        _ = try await intent.perform()

        let expense = try #require(store.fetchExpenses().first)
        #expect(expense.name == "Groceries")
        #expect(expense.amount == 24.50)
        #expect(expense.category == .needs)
        #expect(expense.date == intent.date)
    }

    @Test(arguments: ExpenseCategory.allCases) @MainActor
    func savesRequestedCategory(category: ExpenseCategory) async throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        var intent = AddExpenseAppIntent()
        intent.expenseStore = store
        intent.currencyCodeProvider = { "USD" }
        intent.name = "Coffee"
        intent.amount = IntentCurrencyAmount(amount: 4, currencyCode: "USD")
        intent.category = category

        _ = try await intent.perform()

        #expect(try store.fetchExpenses().first?.category == category)
    }

    @Test @MainActor
    func savesSelectedTag() async throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        let tag = ExpenseTag(name: "Dining", uiColor: .systemBlue, emoji: "")
        store.context.insert(tag)
        try store.save()
        var intent = AddExpenseAppIntent()
        intent.expenseStore = store
        intent.currencyCodeProvider = { "USD" }
        intent.name = "Coffee"
        intent.amount = IntentCurrencyAmount(amount: 4, currencyCode: "USD")
        intent.tag = tag.entity
        intent.category = .wants

        _ = try await intent.perform()

        let expense = try #require(store.fetchExpenses().first)
        #expect(expense.tags?.map(\.id) == [tag.id])
    }

    @Test @MainActor
    func rejectsInvalidValuesWithoutSaving() async throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        for (name, amount) in [
            ("  ", Decimal(5)), ("Coffee", .zero),
            ("Coffee", Decimal(string: "0.004")!), ("Coffee", Decimal(string: "-0.004")!),
            ("Coffee", Decimal(1_000_000_001)), ("Coffee", .greatestFiniteMagnitude), ("Coffee", .nan)
        ] {
            var intent = AddExpenseAppIntent()
            intent.expenseStore = store
            intent.currencyCodeProvider = { "USD" }
            intent.name = name
            intent.amount = IntentCurrencyAmount(amount: amount, currencyCode: "USD")
            intent.category = .wants
            do {
                _ = try await intent.perform()
                Issue.record("Invalid shortcut values were accepted.")
            } catch {
                #expect(try store.fetchExpenses().isEmpty)
            }
        }
    }

    @Test(arguments: [("USD", -12.34), ("JPY", -123.0), ("KWD", -12.345)]) @MainActor
    func savesRefundWithoutChangingAmount(currencyCode: String, amount: Double) async throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        var intent = AddExpenseAppIntent()
        intent.expenseStore = store
        intent.currencyCodeProvider = { currencyCode }
        intent.name = "Refund"
        intent.category = .wants
        intent.amount = IntentCurrencyAmount(amount: Decimal(string: String(amount))!, currencyCode: currencyCode)

        _ = try await intent.perform()

        let expense = try #require(store.fetchExpenses().first)
        #expect(expense.amount == amount)
    }

    @Test(arguments: [("USD", 12.345), ("JPY", 12.34), ("KWD", 12.3456)]) @MainActor
    func rejectsCurrencyPrecisionBeforeSaving(currencyCode: String, amount: Double) async throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        var intent = AddExpenseAppIntent()
        intent.category = .wants
        intent.expenseStore = store
        intent.currencyCodeProvider = { currencyCode }
        intent.name = "Coffee"
        intent.amount = IntentCurrencyAmount(amount: Decimal(string: String(amount))!, currencyCode: currencyCode)

        do {
            _ = try await intent.perform()
            Issue.record("Extra currency precision was accepted.")
        } catch {
            #expect(try store.fetchExpenses().isEmpty)
        }
    }

    @Test @MainActor
    func requiresConfirmedCurrencyBeforeWriting() async throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        var intent = AddExpenseAppIntent()
        intent.category = .wants
        intent.expenseStore = store
        intent.currencyCodeProvider = { throw LedgerCurrency.Error.notEstablished }
        intent.name = "Coffee"
        intent.amount = IntentCurrencyAmount(amount: 4, currencyCode: "USD")
        do {
            _ = try await intent.perform()
            Issue.record("An expense was accepted before currency confirmation.")
        } catch LedgerCurrency.Error.notEstablished {
            #expect(try store.fetchExpenses().isEmpty)
        }
    }

    @Test(arguments: ["USD", "EUR", "CAD", ""]) @MainActor
    func usesLedgerCurrencyWithoutConvertingAmount(inputCurrency: String) async throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        var intent = AddExpenseAppIntent()
        intent.category = .wants
        intent.expenseStore = store
        intent.currencyCodeProvider = { "USD" }
        intent.name = "Coffee"
        intent.amount = IntentCurrencyAmount(amount: 25, currencyCode: inputCurrency)

        _ = try await intent.perform()

        let expense = try #require(store.fetchExpenses().first)
        #expect(expense.amount == 25)
        #expect(expense.category == .wants)
    }

    @Test @MainActor
    func validatesPrecisionUsingLedgerRatherThanSpokenCurrency() async throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        var intent = AddExpenseAppIntent()
        intent.category = .wants
        intent.expenseStore = store
        intent.currencyCodeProvider = { "JPY" }
        intent.name = "Coffee"
        intent.amount = IntentCurrencyAmount(amount: Decimal(string: "25.50")!, currencyCode: "USD")

        await #expect(throws: (any Error).self) {
            try await intent.perform()
        }
        #expect(try store.fetchExpenses().isEmpty)
    }

    @Test @MainActor
    func rejectsPrecisionThatDoubleConversionWouldHide() async throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        var intent = AddExpenseAppIntent()
        intent.category = .wants
        intent.expenseStore = store
        intent.currencyCodeProvider = { "USD" }
        intent.name = "Coffee"
        intent.amount = IntentCurrencyAmount(amount: Decimal(string: "25.000000000000000001")!, currencyCode: "USD")

        await #expect(throws: (any Error).self) {
            try await intent.perform()
        }
        #expect(try store.fetchExpenses().isEmpty)
    }
}
