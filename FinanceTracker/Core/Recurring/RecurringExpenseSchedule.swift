import Foundation
import SageKit

public extension RecurrenceFrequency {
    /// Legacy stepping. Fixed schedules use `RecurringExpenseSchedule` instead.
    nonisolated func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .daily:    return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly:   return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .biweekly: return calendar.date(byAdding: .weekOfYear, value: 2, to: date)
        case .monthly:  return calendar.date(byAdding: .month, value: 1, to: date)
        @unknown default: return nil
        }
    }
}

public extension RecurringExpenseRule {
    /// The next date this rule will generate an expense, or nil once it has passed `endDate`.
    ///
    /// A rule that has generated before steps one interval from its last generation; one that
    /// hasn't yet advances from `startDate` to the first occurrence on or after `date`. Shared
    /// by the dashboard's upcoming list and the Settings rule list so both show the same date.
    nonisolated func nextOccurrence(after date: Date = .now, calendar: Calendar = .current) -> Date? {
        let schedule = RecurringExpenseSchedule(rule: self, legacyCalendar: calendar)
        var next = schedule.firstPendingOccurrence()
        if lastGeneratedDate == nil {
            while let occurrence = next, occurrence < date {
                next = schedule.nextOccurrence(after: occurrence)
            }
        }
        return next
    }
}

/// One schedule for generation and upcoming dates. Display calendars do not
/// override a fixed rule's Gregorian calendar and persisted time zone.
public nonisolated struct RecurringExpenseSchedule {
    private let rule: RecurringExpenseRule
    private let calendar: Calendar
    private let isFixed: Bool

    public init(rule: RecurringExpenseRule, legacyCalendar: Calendar = .current) {
        self.rule = rule
        isFixed = rule.recurrenceTimeZoneIdentifier != nil
        if let identifier = rule.recurrenceTimeZoneIdentifier {
            var calendar = Calendar(identifier: .gregorian)
            // Invalid imported identifiers must not fall back to a device-dependent zone.
            calendar.timeZone = TimeZone(identifier: identifier) ?? TimeZone(secondsFromGMT: 0)!
            self.calendar = calendar
        } else {
            calendar = legacyCalendar
        }
    }

    public func firstPendingOccurrence() -> Date? {
        var cursor = rule.lastGeneratedDate
        if isFixed, let boundary = rule.recurrenceEffectiveDate,
           rule.frequency == .monthly, boundary >= rule.startDate {
            // Conversion never creates a second occurrence in the boundary's month.
            cursor = max(cursor ?? boundary, boundary)
        }
        var next: Date?
        if let cursor {
            next = nextOccurrence(after: cursor)
        } else {
            next = bounded(rule.startDate)
        }
        if isFixed, let boundary = rule.recurrenceEffectiveDate {
            while let occurrence = next, occurrence <= boundary {
                next = nextOccurrence(after: occurrence)
            }
        }
        return next
    }

    public func nextOccurrence(after date: Date) -> Date? {
        guard isFixed else {
            guard let next = rule.frequency.nextOccurrence(after: date, calendar: calendar), next > date else { return nil }
            return bounded(next)
        }

        let targetDay: Date?
        switch rule.frequency {
        case .monthly:
            guard let month = calendar.dateInterval(of: .month, for: date)?.start,
                  let nextMonth = calendar.date(byAdding: .month, value: 1, to: month),
                  let days = calendar.range(of: .day, in: .month, for: nextMonth) else { return nil }
            let day = min(calendar.component(.day, from: rule.startDate), days.count)
            targetDay = calendar.date(byAdding: .day, value: day - 1, to: nextMonth)
        case .daily, .weekly, .biweekly:
            let days = rule.frequency == .daily ? 1 : (rule.frequency == .weekly ? 7 : 14)
            targetDay = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: date))
        @unknown default:
            return nil
        }
        guard let targetDay else { return nil }
        let time = calendar.dateComponents([.hour, .minute, .second], from: rule.startDate)
        // Preserve smaller components only on the intended day (New York 02:30 -> 03:30).
        // Otherwise use the next valid time (Lord Howe 02:15 -> 02:30), never another day.
        // Foundation can skip partial-hour gaps under both policies when minutes are
        // specified; matching just the hour finds its first valid time on that day.
        // Overlaps use the first time under every attempt.
        var resolvedTime: Date?
        for (components, policy) in [
            (time, Calendar.MatchingPolicy.nextTimePreservingSmallerComponents),
            (time, .nextTime),
            (DateComponents(hour: time.hour), .nextTime)
        ] {
            if let candidate = calendar.nextDate(
                after: calendar.startOfDay(for: targetDay).addingTimeInterval(-1),
                matching: components,
                matchingPolicy: policy,
                repeatedTimePolicy: .first
            ), calendar.isDate(candidate, inSameDayAs: targetDay) {
                resolvedTime = candidate
                break
            }
        }
        guard let wholeSecond = resolvedTime else { return nil }
        let timestamp = rule.startDate.timeIntervalSince1970
        let next = wholeSecond.addingTimeInterval(timestamp - floor(timestamp))
        guard next > date else { return nil }
        return bounded(next)
    }

    private func bounded(_ date: Date) -> Date? {
        guard rule.endDate.map({ date <= $0 }) ?? true else { return nil }
        return date
    }
}

public nonisolated enum RecurringScheduleEditError: LocalizedError {
    case endBeforeStart

    public var errorDescription: String? {
        "End date must be on or after the start date."
    }
}

public extension RecurringExpenseRule {
    /// Apply only after confirmation; the caller owns saving/rollback with other edits.
    /// Keeps expense identities and values. Skips catch-up through the latest of now,
    /// the old cursor, prior boundary and recorded occurrence identities. Monthly rules
    /// resume in the following month; other frequencies follow the new start's cadence.
    /// A future start beyond the boundary is the first occurrence. An end before the
    /// next occurrence leaves the rule inactive. Editing opts legacy rules into a fixed zone.
    nonisolated func editSchedule(startDate: Date, frequency: RecurrenceFrequency, endDate: Date?,
                      in timeZone: TimeZone, after date: Date, existingExpenses: [Expense]) throws {
        guard endDate.map({ $0 >= startDate }) ?? true else {
            throw RecurringScheduleEditError.endBeforeStart
        }
        enableFixedSchedule(in: timeZone, after: date, existingExpenses: existingExpenses)
        self.startDate = startDate
        self.frequency = frequency
        self.endDate = endDate
        // The old cursor belongs to the old cadence; its high-water mark is now in
        // recurrenceEffectiveDate. Start the new cadence from its own anchor.
        lastGeneratedDate = nil
    }

    /// Call only after explicit confirmation. Does not rewrite expenses, keys or the cursor.
    nonisolated func enableFixedSchedule(in timeZone: TimeZone, after date: Date, existingExpenses: [Expense]) {
        var boundary = max(date, lastGeneratedDate ?? date)
        boundary = max(boundary, recurrenceEffectiveDate ?? boundary)
        let prefix = "v1:\(id.uuidString.lowercased()):"
        for expense in existingExpenses where expense.recurringExpenseId == id {
            let scheduledDate: Date
            if let key = expense.recurringOccurrenceKey {
                guard key.hasPrefix(prefix), let milliseconds = Int64(key.dropFirst(prefix.count)) else { continue }
                scheduledDate = Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
            } else {
                scheduledDate = expense.recurringScheduledDate ?? expense.date
            }
            boundary = max(boundary, scheduledDate)
        }
        recurrenceEffectiveDate = boundary
        recurrenceTimeZoneIdentifier = timeZone.identifier
    }
}
