import Foundation
import SageKit

/// A Sunday-first month of recorded spending and future recurring occurrences.
public nonisolated struct SpendingCalendarMonth {
    public struct UpcomingExpense: Identifiable {
        public let id: String
        public let name: String
        public let amount: Double
        public let category: ExpenseCategory
        public let date: Date
    }

    public struct Day: Identifiable {
        public let date: Date
        public let expenses: [Expense]
        public let upcomingExpenses: [UpcomingExpense]
        public var upcomingAmount: Double { upcomingExpenses.reduce(0) { $0 + $1.amount } }
        public var amount: Double { expenses.reduce(0) { $0 + $1.amount } + upcomingAmount }
        public var id: Date { date }
    }

    public let leadingEmptyDays: Int
    public let days: [Day]

    public init(month: Date, expenses: [Expense], recurringRules: [RecurringExpenseRule] = [], now: Date = .now, existingRecurringExpenses: [Expense] = [], calendar: Calendar = .current) {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let dayRange = calendar.range(of: .day, in: .month, for: month) else {
            leadingEmptyDays = 0
            days = []
            return
        }

        // Weekday components are Sunday = 1, regardless of the locale's first weekday.
        leadingEmptyDays = calendar.component(.weekday, from: interval.start) - 1
        var recorded: [Date: [Expense]] = [:]
        for expense in expenses where expense.date >= interval.start && expense.date < interval.end {
            recorded[calendar.startOfDay(for: expense.date), default: []].append(expense)
        }

        // Prefer persisted occurrence identities: editing a generated expense's date
        // must not make its original scheduled occurrence appear a second time.
        let existingKeys = Set((expenses + existingRecurringExpenses).compactMap { expense -> String? in
            if let key = expense.recurringOccurrenceKey { return key }
            guard let ruleID = expense.recurringExpenseId else { return nil }
            return RecurringExpenseOccurrence.safeKey(ruleID: ruleID, scheduledDate: expense.recurringScheduledDate ?? expense.date)
        })
        var upcoming: [Date: [UpcomingExpense]] = [:]
        let today = calendar.startOfDay(for: now)
        if interval.end > today {
            for rule in recurringRules {
                let schedule = RecurringExpenseSchedule(rule: rule, legacyCalendar: calendar)
                var next = schedule.firstPendingOccurrence()
                while let occurrence = next, occurrence < interval.end {
                    let day = calendar.startOfDay(for: occurrence)
                    if day > today, occurrence >= interval.start,
                       let key = RecurringExpenseOccurrence.safeKey(ruleID: rule.id, scheduledDate: occurrence),
                       !existingKeys.contains(key) {
                        upcoming[day, default: []].append(UpcomingExpense(
                            id: key, name: rule.name, amount: rule.amount, category: rule.category, date: occurrence
                        ))
                    }
                    next = schedule.nextOccurrence(after: occurrence)
                }
            }
        }

        days = dayRange.compactMap { day in
            guard let date = calendar.date(byAdding: .day, value: day - dayRange.lowerBound, to: interval.start) else {
                return nil
            }
            let day = calendar.startOfDay(for: date)
            return Day(
                date: date,
                expenses: recorded[day, default: []].sorted { $0.date < $1.date },
                upcomingExpenses: upcoming[day, default: []].sorted { $0.date < $1.date }
            )
        }
    }
}
