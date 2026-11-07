import Foundation
import SwiftData
import Testing
import UIKit
@testable import SageKit

@MainActor
private final class RecordingIndex: SpotlightEntityIndexing {
    var indexedExpenses: [UUID] = []
    var deletedExpenses: [UUID] = []
    var deleteAllExpensesCount = 0
    var indexedTags: [ExpenseTagEntity] = []
    var deleteAllTagsCount = 0

    func indexExpenses(_ expenses: [ExpenseEntity]) async throws { indexedExpenses += expenses.map(\.id) }
    func deleteExpenses(withIDs ids: [UUID]) async throws { deletedExpenses += ids }
    func deleteAllExpenses() async throws { deleteAllExpensesCount += 1 }
    func indexTags(_ tags: [ExpenseTagEntity]) async throws { indexedTags += tags }
    func deleteAllTags() async throws { deleteAllTagsCount += 1 }

    func reset() {
        indexedExpenses = []
        deletedExpenses = []
        deleteAllExpensesCount = 0
        indexedTags = []
        deleteAllTagsCount = 0
    }
}

@MainActor
private struct Harness {
    let container: ModelContainer
    let index = RecordingIndex()
    let indexer: ExpenseSpotlightIndexer
    let directory: URL

    var context: ModelContext { container.mainContext }

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Persistent history needs an on-disk store.
        let schema = Schema(versionedSchema: SageSchemaV10.self)
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema,
                url: directory.appendingPathComponent("Sage.sqlite"),
                cloudKitDatabase: .none
            )]
        )
        indexer = ExpenseSpotlightIndexer(
            modelContainer: container,
            index: index,
            stateURL: directory.appendingPathComponent("state.json")
        )
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}

@Suite("Expense Spotlight indexer", .serialized)
struct ExpenseSpotlightIndexerTests {
    @Test @MainActor
    func firstUpdateRebuildsEveryExpenseAndTag() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let tag = ExpenseTag(name: "Coffee", uiColor: .brown, emoji: "☕")
        let first = Expense(name: "Latte", amount: 5, tags: [tag])
        let second = Expense(name: "Rent", amount: 1_200, category: .needs)
        harness.context.insert(tag)
        harness.context.insert(first)
        harness.context.insert(second)
        try harness.context.save()

        try await harness.indexer.update()

        #expect(harness.index.deleteAllExpensesCount == 1)
        #expect(Set(harness.index.indexedExpenses) == [first.id, second.id])
        #expect(harness.index.indexedTags.map(\.id) == [tag.id])
        let state = try #require(harness.indexer.loadState())
        #expect(state.version == ExpenseSpotlightIndexer.indexVersion)
        #expect(state.expenseIDs == [first.id, second.id])
        #expect(state.token != nil)
    }

    @Test @MainActor
    func laterUpdatesIndexOnlyChangedExpenses() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let existing = Expense(name: "Rent", amount: 1_200)
        harness.context.insert(existing)
        try harness.context.save()
        try await harness.indexer.update()
        harness.index.reset()

        let added = Expense(name: "Groceries", amount: 80)
        harness.context.insert(added)
        existing.amount = 1_250
        try harness.context.save()
        try await harness.indexer.update()

        #expect(harness.index.deleteAllExpensesCount == 0)
        #expect(Set(harness.index.indexedExpenses) == [existing.id, added.id])
        #expect(harness.index.deletedExpenses.isEmpty)
        #expect(harness.indexer.loadState()?.expenseIDs == [existing.id, added.id])
    }

    @Test @MainActor
    func updateWithNoNewHistoryDoesNothing() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        harness.context.insert(Expense(name: "Rent", amount: 1_200))
        try harness.context.save()
        try await harness.indexer.update()
        harness.index.reset()

        try await harness.indexer.update()

        #expect(harness.index.indexedExpenses.isEmpty)
        #expect(harness.index.deletedExpenses.isEmpty)
        #expect(harness.index.deleteAllExpensesCount == 0)
    }

    @Test @MainActor
    func deletingAnExpenseRemovesItsEntry() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let kept = Expense(name: "Rent", amount: 1_200)
        let removed = Expense(name: "Latte", amount: 5)
        harness.context.insert(kept)
        harness.context.insert(removed)
        try harness.context.save()
        try await harness.indexer.update()
        harness.index.reset()
        let removedID = removed.id

        harness.context.delete(removed)
        try harness.context.save()
        try await harness.indexer.update()

        #expect(harness.index.deletedExpenses == [removedID])
        #expect(harness.index.indexedExpenses.isEmpty)
        #expect(harness.indexer.loadState()?.expenseIDs == [kept.id])
    }

    @Test @MainActor
    func bulkDeletionRemovesEveryEntry() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let expenses = (0..<3).map { Expense(name: "Item \($0)", amount: 1) }
        expenses.forEach(harness.context.insert)
        try harness.context.save()
        try await harness.indexer.update()
        harness.index.reset()

        // The path Delete All Data takes, which never registers the deleted models.
        try harness.context.delete(model: Expense.self)
        try harness.context.save()
        try await harness.indexer.update()

        #expect(Set(harness.index.deletedExpenses) == Set(expenses.map(\.id)))
        #expect(harness.indexer.loadState()?.expenseIDs.isEmpty == true)
    }

    @Test @MainActor
    func renamingATagReindexesItsExpenses() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let tag = ExpenseTag(name: "Coffee", uiColor: .brown, emoji: "☕")
        let tagged = Expense(name: "Latte", amount: 5, tags: [tag])
        let untagged = Expense(name: "Rent", amount: 1_200)
        harness.context.insert(tag)
        harness.context.insert(tagged)
        harness.context.insert(untagged)
        try harness.context.save()
        try await harness.indexer.update()
        harness.index.reset()

        tag.name = "Cafés"
        try harness.context.save()
        try await harness.indexer.update()

        #expect(harness.index.deleteAllTagsCount == 1)
        #expect(harness.index.indexedTags.map(\.name) == ["Cafés"])
        #expect(harness.index.indexedExpenses == [tagged.id])
    }

    @Test @MainActor
    func taggingAnExpenseDoesNotReindexTags() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let tag = ExpenseTag(name: "Coffee", uiColor: .brown, emoji: "☕")
        harness.context.insert(tag)
        try harness.context.save()
        try await harness.indexer.update()
        harness.index.reset()

        let expense = Expense(name: "Latte", amount: 5, tags: [tag])
        harness.context.insert(expense)
        try harness.context.save()
        try await harness.indexer.update()

        #expect(harness.index.deleteAllTagsCount == 0)
        #expect(harness.index.indexedExpenses == [expense.id])
    }

    @Test @MainActor
    func addingATagReindexesTags() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        try await harness.indexer.update()
        harness.index.reset()

        let tag = ExpenseTag(name: "Travel", uiColor: .blue, emoji: "✈️")
        harness.context.insert(tag)
        try harness.context.save()
        try await harness.indexer.update()

        #expect(harness.index.deleteAllTagsCount == 1)
        #expect(harness.index.indexedTags.map(\.id) == [tag.id])
    }

    @Test @MainActor
    func unreadableStateRebuilds() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let expense = Expense(name: "Rent", amount: 1_200)
        harness.context.insert(expense)
        try harness.context.save()
        try await harness.indexer.update()
        harness.index.reset()

        try Data("not json".utf8).write(to: harness.directory.appendingPathComponent("state.json"))
        try await harness.indexer.update()

        #expect(harness.index.deleteAllExpensesCount == 1)
        #expect(harness.index.indexedExpenses == [expense.id])
    }

    @Test @MainActor
    func systemReindexDropsMissingExpenses() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let expense = Expense(name: "Rent", amount: 1_200)
        harness.context.insert(expense)
        try harness.context.save()
        try await harness.indexer.update()
        harness.index.reset()
        let missing = UUID()

        try await harness.indexer.reindexExpenses(withIDs: [expense.id, missing])

        #expect(harness.index.indexedExpenses == [expense.id])
        #expect(harness.index.deletedExpenses == [missing])
        #expect(harness.indexer.loadState()?.expenseIDs == [expense.id])
    }
}
