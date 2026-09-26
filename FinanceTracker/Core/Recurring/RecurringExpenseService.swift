//
//  RecurringExpenseService.swift
//  FinanceTracker
//

import Foundation
import SageKit
import SwiftData

nonisolated struct RecurringExpenseMaintenanceResult: Equatable, Sendable {
    let generatedCount: Int
    let skippedCount: Int
    let repair: RecurringExpenseRepairResult

    init(
        generatedCount: Int = 0,
        skippedCount: Int = 0,
        repair: RecurringExpenseRepairResult = RecurringExpenseRepairResult()
    ) {
        self.generatedCount = generatedCount
        self.skippedCount = skippedCount
        self.repair = repair
    }
}

@MainActor
final class RecurringExpenseService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Repairs duplicates and generates missing expenses for all rules through the given date.
    /// An occurrence key, and not only the rule cursor, makes repeated calls safe.
    @discardableResult
    func generateAllExpenses(through date: Date, calendar: Calendar = .current) throws -> RecurringExpenseMaintenanceResult {
        do {
            let expenses = try modelContext.fetch(RecurringExpenseRepairService.recurringIdentityExpensesDescriptor())
            let repair = RecurringExpenseRepairService(modelContext: modelContext).repair(expenses: expenses)
            let rules = try modelContext.fetch(FetchDescriptor<RecurringExpenseRule>())
            var existingKeys = Set(expenses.compactMap(\.recurringOccurrenceKey))
            var generatedCount = 0
            var skippedCount = 0

            for rule in rules {
                let result = generateExpenses(
                    for: rule,
                    through: date,
                    calendar: calendar,
                    existingKeys: &existingKeys
                )
                generatedCount += result.generatedCount
                skippedCount += result.skippedCount
            }

            if modelContext.hasChanges {
                try modelContext.save()
            }
            return RecurringExpenseMaintenanceResult(
                generatedCount: generatedCount,
                skippedCount: skippedCount,
                repair: repair
            )
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func generateExpenses(
        for rule: RecurringExpenseRule,
        through date: Date,
        calendar: Calendar,
        existingKeys: inout Set<String>
    ) -> (generatedCount: Int, skippedCount: Int) {
        let schedule = RecurringExpenseSchedule(rule: rule, legacyCalendar: calendar)
        let effectiveEnd = rule.endDate.map { min($0, date) } ?? date
        var nextDate = schedule.firstPendingOccurrence()
        var generatedCount = 0
        var skippedCount = 0

        while let generationDate = nextDate, generationDate <= effectiveEnd {
            let occurrenceKey = RecurringExpenseOccurrence.key(
                ruleID: rule.id,
                scheduledDate: generationDate
            )

            if existingKeys.contains(occurrenceKey) {
                skippedCount += 1
            } else {
                let expense = Expense(
                    name: rule.name,
                    amount: rule.amount,
                    category: rule.category,
                    date: generationDate,
                    tags: rule.tags ?? [],
                    note: rule.note,
                    recurringExpenseId: rule.id,
                    recurringOccurrenceKey: occurrenceKey,
                    account: rule.account
                )
                modelContext.insert(expense)
                existingKeys.insert(occurrenceKey)
                generatedCount += 1
            }

            rule.lastGeneratedDate = generationDate
            nextDate = schedule.nextOccurrence(after: generationDate)
        }

        return (generatedCount, skippedCount)
    }
}
