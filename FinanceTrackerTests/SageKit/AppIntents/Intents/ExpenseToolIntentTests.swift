import AppIntents
import Foundation
import SwiftData
import Testing
import UIKit
@testable import SageKit

@MainActor
private func makeAddIntent(_ store: ExpenseStore, name: String = "Coffee", amount: Decimal = 4) -> AddExpenseAppIntent {
    var intent = AddExpenseAppIntent()
    intent.expenseStore = store
    intent.currencyCodeProvider = { "USD" }
    intent.name = name
    intent.amount = IntentCurrencyAmount(amount: amount, currencyCode: "USD")
    return intent
}

@MainActor
private func makeUpdateIntent(_ store: ExpenseStore, for expense: Expense) -> UpdateExpenseIntent {
    var intent = UpdateExpenseIntent()
    intent.expenseStore = store
    intent.currencyCodeProvider = { "USD" }
    intent.expense = expense.entity
    return intent
}

@MainActor
private func persisted(_ id: UUID, in container: ModelContainer) throws -> Expense? {
    try ModelContext(container).fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.id == id })).first
}

@Suite("Add expense tool", .serialized)
struct AddExpenseToolTests {
    @Test @MainActor
    func savesEveryTagAndTheNote() async throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        let coffee = ExpenseTag(name: "Coffee", uiColor: .brown, emoji: "☕")
        let work = ExpenseTag(name: "Work", uiColor: .gray, emoji: "💼")
        store.context.insert(coffee)
        store.context.insert(work)
        try store.save()
        var intent = makeAddIntent(store)
        intent.category = .wants
        intent.tags = [work.entity, coffee.entity]
        intent.note = "  Client meeting  "

        _ = try await intent.perform()

        let expense = try #require(store.fetchExpenses().first)
        // To-many relationships are unordered, so only membership is stored.
        #expect(Set(expense.tags?.map(\.id) ?? []) == [work.id, coffee.id])
        #expect(expense.note == "Client meeting")
    }

    @Test @MainActor
    func infersCategoryFromTheNewestExpenseWithTheSameName() async throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        store.addExpense(Expense(name: "Netflix", amount: 15, category: .needs, date: .now.addingTimeInterval(-86_400 * 60)))
        store.addExpense(Expense(name: "netflix", amount: 15, category: .wants, date: .now.addingTimeInterval(-86_400 * 30)))
        store.addExpense(Expense(name: "Netflix gift card", amount: 50, category: .savings, date: .now))
        try store.save()

        _ = try await makeAddIntent(store, name: "Netflix").perform()

        let newest = try #require(store.fetchRecentExpenses(limit: 1).first)
        #expect(newest.name == "Netflix")
        #expect(newest.category == .wants)
    }

    @Test @MainActor
    func infersCategoryFromTheTagsMostUsedCategory() async throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        let groceries = ExpenseTag(name: "Groceries", uiColor: .green, emoji: "🛒")
        store.context.insert(groceries)
        store.addExpense(Expense(name: "Market", amount: 30, category: .needs, tags: [groceries]))
        store.addExpense(Expense(name: "Bakery", amount: 8, category: .needs, tags: [groceries]))
        store.addExpense(Expense(name: "Snacks", amount: 5, category: .wants, tags: [groceries]))
        try store.save()
        var intent = makeAddIntent(store, name: "Corner shop")
        intent.tags = [groceries.entity]

        _ = try await intent.perform()

        let added = try #require(store.fetchExpenses().first { $0.name == "Corner shop" })
        #expect(added.category == .needs)
    }

    @Test @MainActor
    func asksForCategoryWhenThereIsNothingToInferFrom() async throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)

        await #expect(throws: (any Error).self) {
            try await makeAddIntent(store, name: "Something new").perform()
        }
        #expect(try store.fetchExpenses().isEmpty)
    }

    @Test @MainActor
    func explicitCategoryWinsOverInference() async throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        store.addExpense(Expense(name: "Coffee", amount: 4, category: .wants))
        try store.save()
        var intent = makeAddIntent(store)
        intent.category = .needs

        _ = try await intent.perform()

        #expect(try store.fetchExpenses().filter { $0.category == .needs }.count == 1)
    }

    @Test @MainActor
    func donationDescribesTheDraftExactly() throws {
        let tag = ExpenseTag(name: "Coffee", uiColor: .brown, emoji: "☕")
        var draft = ExpenseEntryDraft()
        draft.name = "  Latte "
        draft.category = .wants
        draft.date = Date(timeIntervalSince1970: 1_700_000_000)
        draft.tags = [tag]
        draft.note = " "

        let intent = AddExpenseAppIntent(donating: draft, amount: 4.1, currencyCode: "USD")

        #expect(intent.name == "Latte")
        #expect(intent.amount.amount == Decimal(string: "4.1"))
        #expect(intent.amount.currencyCode == "USD")
        #expect(intent.category == .wants)
        #expect(intent.date == draft.date)
        #expect(intent.tags?.map(\.id) == [tag.id])
        #expect(intent.note == nil)
    }
}

@Suite("Update expense tool", .serialized)
struct UpdateExpenseToolTests {
    @Test @MainActor
    func changesOnlyTheGivenValues() async throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let expense = Expense(name: "Latte", amount: 5, category: .wants, date: date, note: "Morning")
        store.addExpense(expense)
        try store.save()
        var intent = makeUpdateIntent(store, for: expense)
        intent.amount = IntentCurrencyAmount(amount: 14, currencyCode: "USD")

        _ = try await intent.perform()

        let saved = try #require(try persisted(expense.id, in: container))
        #expect(saved.amount == 14)
        #expect(saved.name == "Latte")
        #expect(saved.category == .wants)
        #expect(saved.date == date)
        #expect(saved.note == "Morning")
    }

    @Test @MainActor
    func replacesTagsAndClearsTheNote() async throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        let old = ExpenseTag(name: "Coffee", uiColor: .brown, emoji: "☕")
        let new = ExpenseTag(name: "Work", uiColor: .gray, emoji: "💼")
        store.context.insert(old)
        store.context.insert(new)
        let expense = Expense(name: "Latte", amount: 5, tags: [old], note: "Morning")
        store.addExpense(expense)
        try store.save()
        var intent = makeUpdateIntent(store, for: expense)
        intent.tags = [new.entity]
        intent.note = ""

        _ = try await intent.perform()

        let saved = try #require(try persisted(expense.id, in: container))
        #expect(saved.tags?.map(\.id) == [new.id])
        #expect(saved.note.isEmpty)
    }

    @Test @MainActor
    func rejectsInvalidAmountWithoutChangingAnything() async throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        let expense = Expense(name: "Latte", amount: 5)
        store.addExpense(expense)
        try store.save()
        var intent = makeUpdateIntent(store, for: expense)
        intent.name = "Flat white"
        intent.amount = IntentCurrencyAmount(amount: Decimal(string: "4.005")!, currencyCode: "USD")

        await #expect(throws: (any Error).self) { try await intent.perform() }

        let saved = try #require(try persisted(expense.id, in: container))
        #expect(saved.name == "Latte")
        #expect(saved.amount == 5)
    }

    @Test @MainActor
    func requiresSomethingToChange() async throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        let expense = Expense(name: "Latte", amount: 5)
        store.addExpense(expense)
        try store.save()

        await #expect(throws: UpdateExpenseIntent.UpdateError.nothingToChange) {
            try await makeUpdateIntent(store, for: expense).perform()
        }
    }

    @Test @MainActor
    func reportsAnExpenseThatNoLongerExists() async throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        let expense = Expense(name: "Latte", amount: 5)
        var intent = makeUpdateIntent(store, for: expense)
        intent.name = "Flat white"

        await #expect(throws: ExpenseStore.WriteError.expenseNotFound) { try await intent.perform() }
    }
}

@Suite("Delete and open expense tools", .serialized)
struct DeleteAndOpenExpenseToolTests {
    @Test @MainActor
    func deletesOnlyTheExpenseAndKeepsItsRecurringRule() throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        let rule = RecurringExpenseRule(
            name: "Netflix", amount: 15, note: "", category: .wants, tags: [],
            frequency: .monthly, startDate: .now, lastGeneratedDate: .now
        )
        let expense = Expense(name: "Netflix", amount: 15, recurringExpenseId: rule.id)
        let other = Expense(name: "Rent", amount: 1_200)
        store.context.insert(rule)
        store.addExpense(expense)
        store.addExpense(other)
        try store.save()
        var intent = DeleteExpenseIntent()
        intent.expenseStore = store
        intent.expense = expense.entity

        try intent.deleteConfirmed()

        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<Expense>()).map(\.id) == [other.id])
        #expect(try context.fetch(FetchDescriptor<RecurringExpenseRule>()).map(\.id) == [rule.id])
    }

    @Test @MainActor
    func openingAnExpenseRequestsItForTheApp() async throws {
        let expense = Expense(name: "Latte", amount: 5)
        ExpenseOpenRequest.shared.expenseID = nil
        defer { ExpenseOpenRequest.shared.expenseID = nil }
        var intent = OpenExpenseIntent()
        intent.target = expense.entity

        _ = try await intent.perform()

        #expect(ExpenseOpenRequest.shared.expenseID == expense.id)
    }
}
