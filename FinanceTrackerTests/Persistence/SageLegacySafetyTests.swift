import SwiftData
import Testing
import UIKit
@testable import SageKit

@Suite("Legacy store safety", .serialized)
@MainActor
struct SageLegacySafetyTests {
    @Test
    func removedTagsStayRemovedAfterReopenAndLateLegacyRecordsAreConsumed() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("Sage.sqlite")
            try autoreleasepool {
                let container = try legacyContainer(at: url)
                try seedLegacy(container)
            }
            try autoreleasepool {
                let container = try currentContainer(at: url)
                try SageModelContainer.backfillMultiTags(container)
                let context = ModelContext(container)
                let expense = try #require(context.fetch(FetchDescriptor<Expense>()).first)
                let rule = try #require(context.fetch(FetchDescriptor<RecurringExpenseRule>()).first)
                #expect(expense.tags?.first?.name == "Bills")
                #expect(rule.tags?.first?.name == "Bills")
                #expect(expense.tag == nil)
                #expect(rule.tag == nil)
                expense.tags = []
                rule.tags = []
                try context.save()
            }
            try autoreleasepool {
                let container = try currentContainer(at: url)
                try SageModelContainer.backfillMultiTags(container)
                let context = ModelContext(container)
                #expect(try context.fetch(FetchDescriptor<Expense>()).allSatisfy { ($0.tags ?? []).isEmpty && $0.tag == nil })
                #expect(try context.fetch(FetchDescriptor<RecurringExpenseRule>()).allSatisfy { ($0.tags ?? []).isEmpty && $0.tag == nil })
                let tag = try #require(context.fetch(FetchDescriptor<ExpenseTag>()).first)
                #expect((tag.expenses ?? []).isEmpty)
                #expect((tag.recurringRules ?? []).isEmpty)
                let lateExpense = Expense(name: "Late", amount: 25)
                lateExpense.tag = tag
                let lateRule = RecurringExpenseRule(name: "Late", amount: 25, note: "", category: .needs, frequency: .monthly, startDate: .now)
                lateRule.tag = tag
                context.insert(lateExpense)
                context.insert(lateRule)
                try context.save()
            }
            try autoreleasepool {
                let container = try currentContainer(at: url)
                try SageModelContainer.backfillMultiTags(container)
                let context = ModelContext(container)
                for expense in try context.fetch(FetchDescriptor<Expense>()) {
                    #expect(expense.tag == nil)
                    #expect((expense.tags ?? []).count == (expense.name == "Late" ? 1 : 0))
                    expense.tags = []
                }
                for rule in try context.fetch(FetchDescriptor<RecurringExpenseRule>()) {
                    #expect(rule.tag == nil)
                    #expect((rule.tags ?? []).count == (rule.name == "Late" ? 1 : 0))
                    rule.tags = []
                }
                try context.save()
            }
            try autoreleasepool {
                let container = try currentContainer(at: url)
                try SageModelContainer.backfillMultiTags(container)
                let context = ModelContext(container)
                #expect(try context.fetch(FetchDescriptor<Expense>()).allSatisfy { ($0.tags ?? []).isEmpty && $0.tag == nil })
                #expect(try context.fetch(FetchDescriptor<RecurringExpenseRule>()).allSatisfy { ($0.tags ?? []).isEmpty && $0.tag == nil })
                #expect(try context.fetchCount(FetchDescriptor<ExpenseTag>()) == 1)
            }
        }
    }

    @Test
    func explicitCurrentTagsWinAndConsumeStaleLegacyTag() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("Sage.sqlite")
            try autoreleasepool {
                let container = try currentContainer(at: url)
                let context = ModelContext(container)
                let legacy = ExpenseTag(name: "Legacy", uiColor: .red, emoji: "L")
                let current = ExpenseTag(name: "Current", uiColor: .blue, emoji: "C")
                let expense = Expense(name: "Modern", amount: 42, tags: [current])
                let rule = RecurringExpenseRule(name: "Modern", amount: 42, note: "", category: .needs, tags: [current], frequency: .monthly, startDate: .now)
                expense.tag = legacy
                rule.tag = legacy
                context.insert(expense)
                context.insert(rule)
                try context.save()
            }
            try autoreleasepool {
                let container = try currentContainer(at: url)
                try SageModelContainer.backfillMultiTags(container)
                let context = ModelContext(container)
                let expense = try #require(context.fetch(FetchDescriptor<Expense>()).first)
                let rule = try #require(context.fetch(FetchDescriptor<RecurringExpenseRule>()).first)
                #expect(expense.tags?.map(\.name) == ["Current"])
                #expect(rule.tags?.map(\.name) == ["Current"])
                #expect(expense.tag == nil)
                #expect(rule.tag == nil)
                #expect(try context.fetchCount(FetchDescriptor<ExpenseTag>()) == 2)
                expense.tags = []
                rule.tags = []
                try context.save()
            }
            let container = try currentContainer(at: url)
            try SageModelContainer.backfillMultiTags(container)
            #expect(try container.mainContext.fetch(FetchDescriptor<Expense>()).allSatisfy { ($0.tags ?? []).isEmpty })
            #expect(try container.mainContext.fetch(FetchDescriptor<RecurringExpenseRule>()).allSatisfy { ($0.tags ?? []).isEmpty })
        }
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        UIColorValueTransformer.register()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SageLegacySafety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private func legacyContainer(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SageSchemaV2.self)
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
    }

    private func currentContainer(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SageSchemaV9.self)
        return try ModelContainer(for: schema, migrationPlan: SageSchemaMigrationPlan.self, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
    }

    private func seedLegacy(_ container: ModelContainer) throws {
        let context = container.mainContext
        let tag = SageSchemaV2.ExpenseTag(name: "Bills", uiColor: .blue, emoji: "B")
        let account = SageSchemaV2.ExpenseAccount(id: UUID(), name: "Bank", type: .bankAccount)
        let rule = SageSchemaV2.RecurringExpenseRule(name: "Rent", amount: 900, note: "Legacy rule", category: .needs, tag: tag, frequency: .monthly, startDate: Date(timeIntervalSince1970: 1_700_000_000))
        rule.account = account
        let expense = SageSchemaV2.Expense(name: "Rent", amount: 900, category: .needs, tag: tag, note: "Legacy expense", recurringExpenseId: rule.id, account: account)
        context.insert(tag)
        context.insert(account)
        context.insert(rule)
        context.insert(expense)
        try context.save()
    }
}
