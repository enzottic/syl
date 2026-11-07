import Foundation
import SwiftData
import Testing
import UIKit
@testable import SageKit

@Suite("Recurring expense repair conflicts")
struct RecurringExpenseRepairConflictTests {
    private let scheduled = Date(timeIntervalSince1970: 1_786_368_000)
    private let ruleID = UUID()
    private var key: String { RecurringExpenseOccurrence.key(ruleID: ruleID, scheduledDate: scheduled) }

    @Test(arguments: [false, true]) @MainActor
    func editedHigherUUIDCopyContentMovesOntoLowestUUID(reversed: Bool) throws {
        let container = try SageModelContainer.make(for: .test)
        let context = container.mainContext
        let tag = ExpenseTag(name: "Bills", uiColor: .blue, emoji: "B")
        let account = ExpenseAccount(id: UUID(), name: "Card", type: .creditCard)
        context.insert(tag)
        context.insert(account)

        let survivor = generatedCopy(index: 1)
        let edited = generatedCopy(index: 2)
        edited.name = "Rent (corrected)"
        edited.amount = 950
        edited.category = .wants
        edited.date = scheduled.addingTimeInterval(2 * 86_400)
        edited.note = "Landlord raised it"
        edited.tags = [tag]
        edited.account = account
        let editedAt = scheduled.addingTimeInterval(3_600)
        edited.markUserEdited(at: editedAt)
        for expense in reversed ? [edited, survivor] : [survivor, edited] {
            context.insert(expense)
        }
        try context.save()

        let first = try RecurringExpenseRepairService(modelContext: context).repair()
        try context.save()
        let second = try RecurringExpenseRepairService(modelContext: context).repair()

        #expect(first.removedCount == 1 && first.mergedCount == 1 && first.conflictCount == 0)
        #expect(second == RecurringExpenseRepairResult())
        let remaining = try ModelContext(container).fetch(FetchDescriptor<Expense>())
        let expense = try #require(remaining.first)
        #expect(remaining.count == 1)
        #expect(expense.id == survivor.id)
        #expect(expense.name == "Rent (corrected)" && expense.amount == 950 && expense.category == .wants)
        #expect(expense.date == scheduled.addingTimeInterval(2 * 86_400) && expense.note == "Landlord raised it")
        #expect(expense.tags?.map(\.id) == [tag.id] && expense.account?.id == account.id)
        #expect(expense.userEditedAt == editedAt)
        #expect(expense.recurringExpenseId == ruleID && expense.recurringOccurrenceKey == key)
        #expect(expense.recurringScheduledDate == scheduled)
    }

    @Test(arguments: [false, true]) @MainActor
    func newerEditWinsWhenBothCopiesWereEdited(newerOnSurvivor: Bool) throws {
        let container = try SageModelContainer.make(for: .test)
        let context = container.mainContext
        let survivor = generatedCopy(index: 1)
        let other = generatedCopy(index: 2)
        let (newer, older) = newerOnSurvivor ? (survivor, other) : (other, survivor)
        newer.amount = 975
        newer.markUserEdited(at: scheduled.addingTimeInterval(7_200))
        older.amount = 925
        older.markUserEdited(at: scheduled.addingTimeInterval(3_600))
        context.insert(survivor)
        context.insert(other)

        let result = try RecurringExpenseRepairService(modelContext: context).repair()

        #expect(result.mergedCount == (newerOnSurvivor ? 0 : 1))
        #expect(result.conflictCount == 1)
        let expense = try #require(context.fetch(FetchDescriptor<Expense>()).first)
        #expect(expense.id == survivor.id && expense.amount == 975)
    }

    @Test @MainActor
    func equalEditTimesKeepTheSurvivorsContent() throws {
        let container = try SageModelContainer.make(for: .test)
        let context = container.mainContext
        let survivor = generatedCopy(index: 1)
        let other = generatedCopy(index: 2)
        let editedAt = scheduled.addingTimeInterval(3_600)
        survivor.note = "Survivor"
        survivor.markUserEdited(at: editedAt)
        other.note = "Other"
        other.markUserEdited(at: editedAt)
        context.insert(other)
        context.insert(survivor)

        let result = try RecurringExpenseRepairService(modelContext: context).repair()

        #expect(result.mergedCount == 0 && result.conflictCount == 1)
        #expect(try context.fetch(FetchDescriptor<Expense>()).map(\.note) == ["Survivor"])
    }

    @Test @MainActor
    func identicalEditedCopiesCollapseWithoutAConflict() throws {
        let container = try SageModelContainer.make(for: .test)
        let context = container.mainContext
        let copies = [generatedCopy(index: 1), generatedCopy(index: 2)]
        for (offset, copy) in copies.enumerated() {
            copy.amount = 960
            copy.markUserEdited(at: scheduled.addingTimeInterval(Double(offset) * 60))
            context.insert(copy)
        }

        let result = try RecurringExpenseRepairService(modelContext: context).repair()

        #expect(result.removedCount == 1 && result.mergedCount == 0 && result.conflictCount == 0)
    }

    @Test @MainActor
    func mergedEditSurvivesReopeningTheStore() throws {
        UIColorValueTransformer.register()
        let directory = FileManager.default.temporaryDirectory.appending(path: "SageRepair-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Repair.sqlite")
        let schema = Schema(versionedSchema: SageSchemaV10.self)
        func open() throws -> ModelContainer {
            try ModelContainer(for: schema, migrationPlan: SageSchemaMigrationPlan.self, configurations: [
                ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            ])
        }
        let survivorID = generatedCopy(index: 1).id

        try autoreleasepool {
            let container = try open()
            let context = container.mainContext
            let edited = generatedCopy(index: 2)
            edited.amount = 990
            edited.markUserEdited(at: scheduled.addingTimeInterval(60))
            context.insert(generatedCopy(index: 1))
            context.insert(edited)
            try context.save()
            _ = try RecurringExpenseRepairService(modelContext: context).repair()
            try context.save()
        }

        let container = try open()
        let reopened = container.mainContext
        let expenses = try reopened.fetch(FetchDescriptor<Expense>())
        #expect(expenses.map(\.id) == [survivorID] && expenses.first?.amount == 990)
        #expect(try RecurringExpenseRepairService(modelContext: reopened).repair() == RecurringExpenseRepairResult())
    }

    private func generatedCopy(index: Int) -> Expense {
        let expense = Expense(name: "Rent", amount: 900, category: .needs, date: scheduled,
                              recurringExpenseId: ruleID, recurringOccurrenceKey: key)
        expense.id = UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)")!
        return expense
    }
}
