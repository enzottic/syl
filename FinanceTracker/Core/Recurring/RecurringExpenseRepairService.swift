import Foundation
import SageKit
import SwiftData

nonisolated struct RecurringExpenseRepairResult: Equatable, Sendable {
    let backfilledCount: Int
    let removedCount: Int
    let mergedCount: Int
    let conflictCount: Int

    init(backfilledCount: Int = 0, removedCount: Int = 0, mergedCount: Int = 0, conflictCount: Int = 0) {
        self.backfilledCount = backfilledCount
        self.removedCount = removedCount
        self.mergedCount = mergedCount
        self.conflictCount = conflictCount
    }
}

@MainActor
final class RecurringExpenseRepairService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Keeps one expense per occurrence key, carrying over the most recent user edit.
    /// The caller owns the save so repair and generation can use one transaction.
    func repair() throws -> RecurringExpenseRepairResult {
        let expenses = try modelContext.fetch(Self.recurringIdentityExpensesDescriptor())
        return repair(expenses: expenses)
    }

    static func recurringIdentityExpensesDescriptor() -> FetchDescriptor<Expense> {
        // Retain key-only records for the generation check, even when their rule ID was lost.
        FetchDescriptor<Expense>(predicate: #Predicate {
            $0.recurringExpenseId != nil || $0.recurringOccurrenceKey != nil
        })
    }

    /// Reuses the caller's recurring fetch when repair and generation run together.
    func repair(expenses: [Expense]) -> RecurringExpenseRepairResult {
        var groups: [String: [Expense]] = [:]
        var backfilledCount = 0

        for expense in expenses {
            guard let ruleID = expense.recurringExpenseId else { continue }

            // Older clients can sync records without the scheduled-date field after migration.
            expense.backfillRecurringScheduledDate()

            let key = expense.recurringOccurrenceKey
                ?? RecurringExpenseOccurrence.key(ruleID: ruleID, scheduledDate: expense.recurringScheduledDate ?? expense.date)

            if expense.recurringOccurrenceKey == nil {
                expense.recurringOccurrenceKey = key
                backfilledCount += 1
            }

            groups[key, default: []].append(expense)
        }

        var removedCount = 0
        var mergedCount = 0
        var conflictCount = 0

        for group in groups.values where group.count > 1 {
            // Every device keeps the same record, so concurrent repairs never delete different copies.
            let sorted = group.sorted { $0.id.uuidString < $1.id.uuidString }
            let survivor = sorted[0]
            let source = Self.mostRecentlyEdited(in: sorted)

            let editedVersions = Set(sorted.filter { $0.userEditedAt != nil }.map(ExpenseContent.init))
            if editedVersions.count > 1 {
                conflictCount += 1
            }

            if source !== survivor, !ExpenseContent(survivor).matches(source) {
                survivor.adoptContent(of: source)
                mergedCount += 1
            }

            for duplicate in sorted.dropFirst() {
                modelContext.delete(duplicate)
                removedCount += 1
            }
        }

        return RecurringExpenseRepairResult(
            backfilledCount: backfilledCount,
            removedCount: removedCount,
            mergedCount: mergedCount,
            conflictCount: conflictCount
        )
    }

    /// `sorted` must be in survivor order, so ties resolve to the survivor.
    private static func mostRecentlyEdited(in sorted: [Expense]) -> Expense {
        sorted.reduce(sorted[0]) { best, candidate in
            (candidate.userEditedAt ?? .distantPast) > (best.userEditedAt ?? .distantPast) ? candidate : best
        }
    }
}

private struct ExpenseContent: Hashable {
    let name: String
    let amount: Double
    let category: ExpenseCategory
    let date: Date
    let note: String
    let tagIDs: Set<UUID>
    let accountID: UUID?

    init(_ expense: Expense) {
        name = expense.name
        amount = expense.amount
        category = expense.category
        date = expense.date
        note = expense.note
        tagIDs = Set((expense.tags ?? []).map(\.id))
        accountID = expense.account?.id
    }

    func matches(_ expense: Expense) -> Bool {
        self == ExpenseContent(expense)
    }
}

private extension Expense {
    /// Occurrence identity stays with the survivor; only user-editable fields move.
    func adoptContent(of other: Expense) {
        name = other.name
        amount = other.amount
        category = other.category
        date = other.date
        note = other.note
        tags = other.tags
        account = other.account
        userEditedAt = other.userEditedAt
    }
}
