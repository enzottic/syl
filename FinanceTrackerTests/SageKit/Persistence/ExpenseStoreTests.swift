import SwiftData
import Testing
import UIKit
@testable import SageKit

@Suite("Expense store")
struct ExpenseStoreTests {
    private enum SaveFailure: Error {
        case expected
    }

    @Test @MainActor
    func isolatedWriteDoesNotSavePendingAppEdits() throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        store.context.autosaveEnabled = false
        let existing = Expense(name: "Original", amount: 18, category: .needs)
        store.addExpense(existing)
        try store.save()
        existing.name = "Pending edit"

        let entity = try store.addExpenseAndSave(
            Expense(name: "Shortcut", amount: 4, category: .wants),
            tagID: nil
        )

        let verificationContext = ModelContext(container)
        let persisted = try verificationContext.fetch(FetchDescriptor<Expense>())
        #expect(Set(persisted.map(\.name)) == ["Original", "Shortcut"])
        #expect(persisted.contains { $0.id == entity.id })
        #expect(existing.name == "Pending edit")
        #expect(store.context.hasChanges)
    }

    @Test @MainActor
    func failedIsolatedWriteRollsBackWithoutDiscardingPendingAppEdits() throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        store.context.autosaveEnabled = false
        let tag = ExpenseTag(name: "Dining", uiColor: .systemBlue, emoji: "")
        let existing = Expense(name: "Original", amount: 18, category: .needs, tags: [tag])
        store.context.insert(tag)
        store.addExpense(existing)
        try store.save()
        existing.name = "Pending edit"
        var failedContext: ModelContext?

        do {
            _ = try store.addExpenseAndSave(
                Expense(name: "Failed shortcut", amount: 4, category: .wants),
                tagID: tag.id
            ) { context in
                failedContext = context
                #expect(context.hasChanges)
                throw SaveFailure.expected
            }
            Issue.record("The save failure was suppressed.")
        } catch SaveFailure.expected {
            let context = try #require(failedContext)
            #expect(!context.hasChanges)
            // A later save must not resurrect the failed insertion or its tag relationship.
            try context.save()
            let verificationContext = ModelContext(container)
            let persisted = try verificationContext.fetch(FetchDescriptor<Expense>())
            #expect(persisted.map(\.name) == ["Original"])
            #expect(persisted.first?.tags?.map(\.id) == [tag.id])
            let persistedTag = try #require(verificationContext.fetch(FetchDescriptor<ExpenseTag>()).first)
            #expect(persistedTag.taggedExpenses?.map(\.id) == [existing.id])
            #expect(existing.name == "Pending edit")
            #expect(store.context.hasChanges)
            #expect(tag.taggedExpenses?.map(\.id) == [existing.id])
        }
    }

    @Test @MainActor
    func monthlyFetchAndSnapshotUseHalfOpenMonthInterval() throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        let calendar = Calendar.current
        let month = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 15)))
        let interval = try #require(calendar.dateInterval(of: .month, for: month))
        let beforeMonth = Expense(name: "Before month", amount: 100, category: .needs, date: interval.start.addingTimeInterval(-1))
        let atStart = Expense(name: "Month start", amount: 10, category: .needs, date: interval.start)
        let middle = Expense(name: "Midmonth", amount: 20, category: .wants, date: month)
        let beforeEnd = Expense(name: "Month end", amount: 30, category: .savings, date: interval.end.addingTimeInterval(-1))
        let atEnd = Expense(name: "Next month start", amount: 200, category: .wants, date: interval.end)
        for expense in [middle, atEnd, beforeMonth, atStart, beforeEnd] {
            store.addExpense(expense)
        }
        try store.save()

        let expenses = try store.fetchExpenses(for: month)
        #expect(expenses.map(\.id) == [beforeEnd.id, middle.id, atStart.id])
        #expect(try store.fetchExpenses(for: interval.end).map(\.id) == [atEnd.id])

        let snapshot = try store.monthlySnapshot(for: month)
        #expect(snapshot.totalSpent == 60)
        #expect(snapshot.needsSpent == 10)
        #expect(snapshot.wantsSpent == 20)
        #expect(snapshot.savingsSpent == 30)
        #expect(snapshot.recentExpenses.map(\.id) == [beforeEnd.id, middle.id, atStart.id])
    }

    @Test @MainActor
    func recentExpensesSelectNewestAcrossMonthsBeforeApplyingLimit() throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        let calendar = Calendar.current
        let month = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 15)))
        let boundary = try #require(calendar.dateInterval(of: .month, for: month)).end
        let oldest = Expense(name: "Oldest", amount: 1, date: month)
        let previousMonth = Expense(name: "Previous month", amount: 2, date: boundary.addingTimeInterval(-1))
        let atBoundary = Expense(name: "Month start", amount: 3, date: boundary)
        let newest = Expense(name: "Newest", amount: 4, date: boundary.addingTimeInterval(1))
        for expense in [previousMonth, newest, oldest, atBoundary] {
            store.addExpense(expense)
        }
        try store.save()

        let expenses = try store.fetchRecentExpenses(limit: 3)
        #expect(expenses.map(\.id) == [newest.id, atBoundary.id, previousMonth.id])
    }

    @Test @MainActor
    func deleteRemovesSavedExpense() throws {
        let container = try SageModelContainer.make(for: .test)
        let store = ExpenseStore(modelContainer: container)
        let expense = Expense(name: "Delete Me", amount: 18, category: .needs)

        store.addExpense(expense)
        try store.save()
        #expect(try store.fetchExpenses().map(\.name) == ["Delete Me"])

        store.deleteExpense(expense)
        try store.save()

        #expect(try store.fetchExpenses().isEmpty)
    }
}
