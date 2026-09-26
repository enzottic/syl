import AppIntents
import Foundation
import SwiftData
import Testing
import UIKit
@testable import SageKit

@Suite("Monthly spending shortcut")
struct GetMonthlySpendingTotalIntentTests {
    @Test @MainActor
    func returnsCurrentMonthTotalAcrossCategories() async throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        let now = Date.now
        let month = try #require(Calendar.current.dateInterval(of: .month, for: now))
        store.addExpense(Expense(name: "Groceries", amount: 25, category: .needs, date: now))
        store.addExpense(Expense(name: "Coffee", amount: 5, category: .wants, date: now))
        store.addExpense(Expense(name: "Savings", amount: 10, category: .savings, date: now))
        store.addExpense(Expense(name: "Refund", amount: -2, date: now))
        store.addExpense(Expense(name: "Previous month", amount: 100, date: month.start.addingTimeInterval(-1)))
        store.addExpense(Expense(name: "Next month", amount: 200, date: month.end))
        try store.save()
        let intent = GetMonthlySpendingTotalIntent()
        intent.expenseStore = store

        let result = try await intent.perform()

        #expect(result.value == 38)
    }

    @Test @MainActor
    func returnsZeroForEmptyLedger() async throws {
        let container = try SageModelContainer.make(for: .test)
        let intent = GetMonthlySpendingTotalIntent()
        intent.expenseStore = ExpenseStore(modelContainer: container)

        let result = try await intent.perform()

        #expect(result.value == 0)
    }

    @Test(arguments: [(true, false, 30.0), (false, true, 50.0), (true, true, 20.0)]) @MainActor
    func filtersByCategoryTagOrBoth(useCategory: Bool, useTag: Bool, expected: Double) async throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        let tag = ExpenseTag(name: "Dining", uiColor: .systemBlue, emoji: "")
        store.context.insert(tag)
        let needs = Expense(name: "Lunch", amount: 20, category: .needs, date: .now)
        needs.tags = [tag]
        let wants = Expense(name: "Dinner", amount: 30, category: .wants, date: .now)
        wants.tags = [tag]
        store.addExpense(needs)
        store.addExpense(wants)
        store.addExpense(Expense(name: "Groceries", amount: 10, category: .needs, date: .now))
        let month = try #require(Calendar.current.dateInterval(of: .month, for: .now))
        let previous = Expense(name: "Old lunch", amount: 100, category: .needs, date: month.start.addingTimeInterval(-1))
        previous.tags = [tag]
        store.addExpense(previous)
        try store.save()
        let intent = GetMonthlySpendingTotalIntent()
        intent.expenseStore = store
        if useCategory { intent.category = .needs }
        if useTag { intent.tag = tag.entity }

        let result = try await intent.perform()

        #expect(result.value == expected)
    }

    @Test @MainActor
    func expenseTotalUsesRequestedTimePeriod() async throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        let yesterday = ExpenseTimePeriod.yesterday.dateRange
        store.addExpense(Expense(name: "Yesterday", amount: 25, date: yesterday.start))
        store.addExpense(Expense(name: "Today", amount: 50, date: yesterday.end))
        store.addExpense(Expense(name: "Earlier", amount: 100, date: yesterday.start.addingTimeInterval(-1)))
        try store.save()
        let intent = FindExpensesIntent()
        intent.expenseStore = store
        intent.timePeriod = .yesterday

        let result = try await intent.perform()

        #expect(result.value == 25)
    }
}
