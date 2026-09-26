import Foundation
import SwiftData
import Testing
import UIKit
@testable import SageKit

@Suite("Persistent ledger currency")
struct LedgerCurrencyTests {
    @Test
    func replacementIgnoresLegacyConflictFlags() throws {
        let suite = "LedgerCurrencyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try LedgerCurrency.setCode("EUR", defaults: defaults)
        defaults.set(true, forKey: LedgerCurrency.storageKey + ".conflict")
        try LedgerCurrency.setCode("GBP", defaults: defaults)
        #expect(LedgerCurrency.persistedCode(defaults: defaults) == "GBP")
    }

    @Test @MainActor
    func replacingCurrencyPreservesStoredAmounts() throws {
        let suite = "LedgerCurrencyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try SageModelContainer.make(for: .test)
        let context = container.mainContext
        context.insert(Expense(name: "Coffee", amount: 4.25))
        context.insert(RecurringExpenseRule(name: "Rent", amount: 100.50, note: "", category: .needs, frequency: .monthly, startDate: .now))
        context.insert(ExpenseTag(name: "Food", uiColor: .blue, emoji: "", budget: 200.75))
        try context.save()
        try LedgerCurrency.setCode("USD", defaults: defaults)
        try LedgerCurrency.setCode("JPY", defaults: defaults)

        let reopened = ModelContext(container)
        #expect(try reopened.fetch(FetchDescriptor<Expense>()).map(\.amount) == [4.25])
        #expect(try reopened.fetch(FetchDescriptor<RecurringExpenseRule>()).map(\.amount) == [100.50])
        #expect(try reopened.fetch(FetchDescriptor<ExpenseTag>()).map(\.budget) == [200.75])
        #expect(LedgerCurrency.persistedCode(defaults: defaults) == "JPY")
    }

    @Test
    func editableCurrencyPersistsWithoutUsingLaterLocaleSuggestions() throws {
        let suite = "LedgerCurrencyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(LedgerCurrency.persistedCode(defaults: defaults) == nil)
        try LedgerCurrency.setCode("EUR", defaults: defaults)
        #expect(LedgerCurrency.suggestedCode(locale: Locale(identifier: "en_US")) == "USD")
        #expect(LedgerCurrency.suggestedCode(locale: Locale(identifier: "ja_JP")) == "JPY")
        let reopenedDefaults = try #require(UserDefaults(suiteName: suite))
        #expect(LedgerCurrency.persistedCode(defaults: reopenedDefaults) == "EUR")
        try LedgerCurrency.setCode("EUR", defaults: reopenedDefaults)
        try LedgerCurrency.setCode("JPY", defaults: reopenedDefaults)
        #expect(LedgerCurrency.persistedCode(defaults: defaults) == "JPY")
    }

    @Test
    func resetRemovesSavedCurrencyAndLegacyConflictFlag() throws {
        let suite = "LedgerCurrencyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try LedgerCurrency.setCode("USD", defaults: defaults)
        defaults.set(true, forKey: LedgerCurrency.storageKey + ".conflict")
        LedgerCurrency.reset(defaults: defaults)
        #expect(LedgerCurrency.persistedCode(defaults: defaults) == nil)
        #expect(defaults.object(forKey: LedgerCurrency.storageKey + ".conflict") == nil)
        try LedgerCurrency.setCode("EUR", defaults: defaults)
        #expect(LedgerCurrency.persistedCode(defaults: defaults) == "EUR")
    }

    @Test(arguments: ["", "usd", "ZZZ", " USD "])
    func invalidCurrencyIsNeitherReadNorSaved(code: String) throws {
        let suite = "LedgerCurrencyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(code, forKey: LedgerCurrency.storageKey)
        #expect(LedgerCurrency.persistedCode(defaults: defaults) == nil)
        #expect(throws: LedgerCurrency.Error.invalidCode(code)) {
            try LedgerCurrency.setCode(code, defaults: defaults)
        }
        try LedgerCurrency.setCode("EUR", defaults: defaults)
        #expect(throws: LedgerCurrency.Error.invalidCode(code)) {
            try LedgerCurrency.setCode(code, defaults: defaults)
        }
        #expect(LedgerCurrency.persistedCode(defaults: defaults) == "EUR")
    }

    @Test
    func unavailableSharedStorageDoesNotFallBackToPrivateDefaults() {
        #expect(LedgerCurrency.persistedCode(defaults: nil) == nil)
        #expect(throws: LedgerCurrency.Error.storageUnavailable) {
            try LedgerCurrency.setCode("USD", defaults: nil)
        }
    }

    @Test
    func minorUnitsFollowCurrencyRatherThanDeviceRegion() {
        #expect(LedgerCurrency.fractionDigits(for: "USD") == 2)
        #expect(LedgerCurrency.fractionDigits(for: "JPY") == 0)
        #expect(LedgerCurrency.fractionDigits(for: "KWD") == 3)
    }
}
