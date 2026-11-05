//
//  UpcomingRecurringExpenses.swift
//  SageKit
//

import Foundation
import SwiftData

/// One future occurrence of a recurring expense.
public struct UpcomingRecurringExpense: Equatable, Sendable {
    public let ruleID: UUID
    public let name: String
    public let amount: Double
    public let category: ExpenseCategory
    public let date: Date
}

extension ExpenseStore {
    /// Every occurrence due from the start of today through `days` days from `now`, soonest
    /// first, following each rule's own schedule. Capped at `limit` occurrences overall.
    public func upcomingRecurringExpenses(
        within days: Int,
        from now: Date = .now,
        calendar: Calendar = .current,
        limit: Int = 50
    ) throws -> [UpcomingRecurringExpense] {
        let today = calendar.startOfDay(for: now)
        guard days >= 0, let end = calendar.date(byAdding: .day, value: days, to: now) else { return [] }

        var occurrences: [UpcomingRecurringExpense] = []
        for rule in try context.fetch(FetchDescriptor<RecurringExpenseRule>()) {
            let schedule = RecurringExpenseSchedule(rule: rule, legacyCalendar: calendar)
            var next = rule.nextOccurrence(after: now, calendar: calendar)
            // Bounded by `limit`, so a daily rule over a long window can't run away.
            var steps = 0
            while let date = next, date <= end, steps < limit {
                if date >= today {
                    occurrences.append(UpcomingRecurringExpense(
                        ruleID: rule.id, name: rule.name, amount: rule.amount,
                        category: rule.category, date: date
                    ))
                }
                next = schedule.nextOccurrence(after: date)
                steps += 1
            }
        }
        return Array(occurrences.sorted { ($0.date, $0.name) < ($1.date, $1.name) }.prefix(limit))
    }
}
