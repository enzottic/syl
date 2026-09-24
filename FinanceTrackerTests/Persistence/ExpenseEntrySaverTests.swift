import Foundation
import SwiftData
import Testing
import UIKit
@testable import SageKit

@Suite("Expense entry saver")
@MainActor
struct ExpenseEntrySaverTests {
    private enum SaveFailure: Error { case expected }

    @Test(arguments: [12.34, -12.34])
    func savesBasicExpenseOrRefundWithExactTextAndNoRecurrence(amount: Double) throws {
        let container = try SageModelContainer.make(for: .test)
        var draft = validDraft()
        draft.amount = amount
        let id = try ExpenseEntrySaver(modelContainer: container).save(draft, currencyCode: "USD")

        let reader = ModelContext(container)
        let expenses = try reader.fetch(FetchDescriptor<Expense>())
        let expense = try #require(expenses.first)
        #expect(expenses.count == 1)
        #expect(expense.id == id)
        #expect(expense.name == draft.name)
        #expect(expense.amount == amount)
        #expect(expense.category == draft.category)
        #expect(expense.date == draft.date)
        #expect(expense.note == draft.note)
        #expect(expense.tags?.isEmpty == true)
        #expect(expense.recurringExpenseId == nil)
        #expect(expense.recurringOccurrenceKey == nil)
        #expect(expense.recurringScheduledDate == nil)
        #expect(try reader.fetchCount(FetchDescriptor<RecurringExpenseRule>()) == 0)
    }

    @Test
    func resolvesTagsByIDAndDoesNotCommitPendingAppEdits() throws {
        let container = try SageModelContainer.make(for: .test)
        let appContext = container.mainContext
        appContext.autosaveEnabled = false
        let tag = ExpenseTag.dining
        let secondTag = ExpenseTag.shopping
        let existing = Expense(name: "Original", amount: 8, tags: [tag])
        appContext.insert(existing)
        appContext.insert(secondTag)
        try appContext.save()
        existing.name = "Pending expense edit"
        tag.name = "Pending tag edit"
        var draft = validDraft()
        draft.tags = [tag, secondTag, tag]

        let id = try ExpenseEntrySaver(modelContainer: container).save(draft, currencyCode: "USD")

        let reader = ModelContext(container)
        let expenses = try reader.fetch(FetchDescriptor<Expense>())
        let saved = try #require(expenses.first { $0.id == id })
        #expect(Set((saved.tags ?? []).map(\.id)) == [tag.id, secondTag.id])
        #expect(saved.tags?.count == 2)
        #expect(expenses.first { $0.id == existing.id }?.name == "Original")
        let savedTag = try #require(reader.fetch(FetchDescriptor<ExpenseTag>()).first { $0.id == tag.id })
        #expect(savedTag.name == "Dining")
        #expect(Set((savedTag.taggedExpenses ?? []).map(\.id)) == [existing.id, id])
        #expect(try reader.fetchCount(FetchDescriptor<ExpenseTag>()) == 2)
        #expect(existing.name == "Pending expense edit")
        #expect(tag.name == "Pending tag edit")
        #expect(appContext.hasChanges)
    }

    @Test(arguments: RecurrenceFrequency.allCases.map(\.rawValue))
    func recurrenceSavesRuleAndFirstOccurrenceTogether(frequencyName: String) throws {
        let frequency = try #require(RecurrenceFrequency(rawValue: frequencyName))
        let container = try SageModelContainer.make(for: .test)
        let tag = ExpenseTag.subscriptions
        container.mainContext.insert(tag)
        try container.mainContext.save()
        var draft = validDraft()
        draft.tags = [tag]
        draft.isRecurring = true
        draft.recurrenceFrequency = frequency
        var commits = 0

        let id = try ExpenseEntrySaver(modelContainer: container).save(draft, currencyCode: "USD") { context in
            commits += 1
            #expect(context !== container.mainContext)
            #expect(!context.autosaveEnabled)
            #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<RecurringExpenseRule>()) == 1)
            try context.save()
        }

        let reader = ModelContext(container)
        let expense = try #require(reader.fetch(FetchDescriptor<Expense>()).first)
        let rule = try #require(reader.fetch(FetchDescriptor<RecurringExpenseRule>()).first)
        #expect(commits == 1)
        #expect(expense.id == id)
        #expect(rule.name == draft.name)
        #expect(rule.amount == draft.amount)
        #expect(rule.note == draft.note)
        #expect(rule.category == draft.category)
        #expect(rule.tags?.map(\.id) == [tag.id])
        #expect(expense.tags?.map(\.id) == [tag.id])
        #expect(rule.frequency == frequency)
        #expect(rule.startDate == draft.date)
        #expect(rule.lastGeneratedDate == draft.date)
        #expect(rule.recurrenceTimeZoneIdentifier == TimeZone.current.identifier)
        #expect(rule.endDate == nil)
        #expect(expense.recurringExpenseId == rule.id)
        let key = RecurringExpenseOccurrence.key(ruleID: rule.id, scheduledDate: draft.date)
        #expect(expense.recurringOccurrenceKey == key)
        #expect(expense.recurringScheduledDate == RecurringExpenseOccurrence.scheduledDate(forKey: key, ruleID: rule.id))

        expense.date = draft.date.addingTimeInterval(86_400)
        try reader.save()
        let verification = ModelContext(container)
        let moved = try #require(verification.fetch(FetchDescriptor<Expense>()).first)
        #expect(moved.recurringOccurrenceKey == key)
        #expect(moved.recurringScheduledDate == RecurringExpenseOccurrence.scheduledDate(forKey: key, ruleID: rule.id))
        // The saved cursor and occurrence identity keep maintenance from duplicating the first entry.
        try RecurringExpenseService(modelContext: verification).generateAllExpenses(through: draft.date)
        #expect(try verification.fetchCount(FetchDescriptor<Expense>()) == 1)
    }

    @Test
    func duplicationCreatesFreshExpenseWithoutSourceRecurrenceOrAccount() throws {
        let container = try SageModelContainer.make(for: .test)
        let account = ExpenseAccount(id: UUID(), name: "Bank", type: .bankAccount)
        let source = Expense(
            name: "Subscription", amount: 20, note: "Original note",
            recurringExpenseId: UUID(), account: account
        )
        container.mainContext.insert(source)
        try container.mainContext.save()
        let draft = ExpenseEntryDraft(expense: source)
        let id = try ExpenseEntrySaver(modelContainer: container).save(draft, currencyCode: "USD")
        let reader = ModelContext(container)
        let expenses = try reader.fetch(FetchDescriptor<Expense>())
        let duplicate = try #require(expenses.first { $0.id == id })
        #expect(expenses.count == 2)
        #expect(id != source.id)
        #expect(duplicate.note == source.note)
        #expect(duplicate.recurringExpenseId == nil)
        #expect(duplicate.recurringOccurrenceKey == nil)
        #expect(duplicate.recurringScheduledDate == nil)
        #expect(duplicate.account == nil)
        #expect(try reader.fetchCount(FetchDescriptor<RecurringExpenseRule>()) == 0)
    }

    @Test
    func validationFailuresNeverReachCommitOrWriteModels() throws {
        let container = try SageModelContainer.make(for: .test)
        let saver = ExpenseEntrySaver(modelContainer: container)
        var cases: [(ExpenseEntryDraft, String, ExpenseEntryDraft.ValidationError)] = []
        var draft = validDraft()
        draft.name = " \n\t "
        cases.append((draft, "USD", .missingName))
        for amount: Double? in [nil, 0, .nan, .infinity, -.infinity, 1.001, 1_000_000_001] {
            draft = validDraft()
            draft.amount = amount
            cases.append((draft, "USD", .invalidAmount(currencyCode: "USD", requiresPositive: false)))
        }
        draft = validDraft()
        draft.isRecurring = true
        draft.amount = -5
        cases.append((draft, "USD", .invalidAmount(currencyCode: "USD", requiresPositive: true)))
        draft = validDraft()
        cases.append((draft, "invalid", .invalidAmount(currencyCode: "invalid", requiresPositive: false)))
        draft.date = Date(timeIntervalSince1970: .infinity)
        cases.append((draft, "USD", .invalidDate))
        draft.isRecurring = true
        draft.date = Date(timeIntervalSince1970: 1e20)
        cases.append((draft, "USD", .invalidDate))

        for (invalid, currency, expected) in cases {
            #expect(throws: expected) {
                try saver.save(invalid, currencyCode: currency) { _ in
                    Issue.record("Validation must fail before commit")
                }
            }
        }
        let reader = ModelContext(container)
        #expect(try reader.fetchCount(FetchDescriptor<Expense>()) == 0)
        #expect(try reader.fetchCount(FetchDescriptor<RecurringExpenseRule>()) == 0)
        #expect(try reader.fetchCount(FetchDescriptor<ExpenseTag>()) == 0)
        #expect(!container.mainContext.hasChanges)
    }

    @Test(arguments: [false, true])
    func unavailableOrAmbiguousTagFailsWithoutWrites(ambiguous: Bool) throws {
        let container = try SageModelContainer.make(for: .test)
        let tag = ExpenseTag.dining
        if ambiguous {
            container.mainContext.insert(tag)
            container.mainContext.insert(ExpenseTag(id: tag.id, name: "Copy", uiColor: .systemBlue, emoji: ""))
            try container.mainContext.save()
        }
        var draft = validDraft()
        draft.isRecurring = true
        draft.tags = [tag]
        let expected: ExpenseEntrySaver.SaveError = ambiguous ? .ambiguousTag(tag.id) : .missingTag(tag.id)
        #expect(throws: expected) {
            try ExpenseEntrySaver(modelContainer: container).save(draft, currencyCode: "USD")
        }
        let reader = ModelContext(container)
        #expect(try reader.fetchCount(FetchDescriptor<Expense>()) == 0)
        #expect(try reader.fetchCount(FetchDescriptor<RecurringExpenseRule>()) == 0)
        #expect(try reader.fetchCount(FetchDescriptor<ExpenseTag>()) == (ambiguous ? 2 : 0))
    }

    @Test
    func failedCommitRollsBackRuleExpenseAndTagLinksAndAllowsRetry() throws {
        let container = try SageModelContainer.make(for: .test)
        let appContext = container.mainContext
        appContext.autosaveEnabled = false
        let tag = ExpenseTag.dining
        let existing = Expense(name: "Original", amount: 8, tags: [tag])
        appContext.insert(existing)
        try appContext.save()
        existing.name = "Pending edit"
        var draft = validDraft()
        draft.tags = [tag]
        draft.isRecurring = true
        let saver = ExpenseEntrySaver(modelContainer: container)
        var failedContext: ModelContext?

        #expect(throws: SaveFailure.expected) {
            try saver.save(draft, currencyCode: "USD") { context in
                failedContext = context
                #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 2)
                #expect(try context.fetchCount(FetchDescriptor<RecurringExpenseRule>()) == 1)
                throw SaveFailure.expected
            }
        }
        let failed = try #require(failedContext)
        #expect(!failed.hasChanges)
        try failed.save()
        let reader = ModelContext(container)
        #expect(try reader.fetch(FetchDescriptor<Expense>()).map(\.name) == ["Original"])
        #expect(try reader.fetchCount(FetchDescriptor<RecurringExpenseRule>()) == 0)
        let persistedTag = try #require(reader.fetch(FetchDescriptor<ExpenseTag>()).first)
        #expect(persistedTag.taggedExpenses?.map(\.id) == [existing.id])
        #expect((persistedTag.taggedRecurringRules ?? []).isEmpty)
        #expect(existing.name == "Pending edit")
        #expect(appContext.hasChanges)

        try saver.save(draft, currencyCode: "USD")
        let retryReader = ModelContext(container)
        #expect(try retryReader.fetchCount(FetchDescriptor<Expense>()) == 2)
        #expect(try retryReader.fetchCount(FetchDescriptor<RecurringExpenseRule>()) == 1)
    }

    private func validDraft() -> ExpenseEntryDraft {
        var draft = ExpenseEntryDraft(now: Date(timeIntervalSince1970: 1_800_000_000.1234))
        draft.name = "  Lunch  "
        draft.amount = 12.34
        draft.category = .wants
        draft.note = "  Receipt\nSecond line  "
        return draft
    }
}
