import Foundation
import SageKit

@MainActor
public enum RecurringReminderPlan {
    public struct Summary: Equatable {
        public let identifier: String
        public let fireDate: Date
        public let title: String
        public let body: String
    }

    public enum PlanningError: Error, Equatable {
        case advanceLimitExceeded(ruleID: UUID)
        case invalidDate
    }

    public static func owns(_ identifier: String) -> Bool {
        identifier.hasPrefix("sage.recurring.v1.")
            || identifier.hasPrefix("recurring-day-")
            || identifier.hasPrefix("recurring-added-")
    }

    // Generates the next 89 days of recurring reminder summaries to schedule notifications for
    public static func summaries(
        rules: [RecurringExpenseRule],
        daysBefore: Int = 1,
        timeMinutes: Int = 540,
        hideDetails: Bool = true,
        currencyCode: String?,
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) throws -> [Summary] {
        guard now.timeIntervalSince1970.isFinite else { throw PlanningError.invalidDate }
        
        let lead = (1...7).contains(daysBefore) ? daysBefore : 1
        let time = (0..<1440).contains(timeMinutes) ? timeMinutes : 540
        
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = calendar.timeZone
        
        let today = localCalendar.startOfDay(for: now)
        
        guard let firstTargetDay = localCalendar.date(byAdding: .day, value: lead, to: today),
              let targetEnd = localCalendar.date(byAdding: .day, value: 90 + lead, to: today) else {
            throw PlanningError.invalidDate
        }

        var groups: [Date: [(date: Date, rule: RecurringExpenseRule)]] = [:]
        var seen = Set<String>()
        
        // Tie-break conflicting imported copies as well as ordinary rule ordering.
        let orderedRules = rules.sorted {
            if $0.id != $1.id { return $0.id.uuidString < $1.id.uuidString }
            if $0.name != $1.name { return $0.name < $1.name }
            return String($0.amount) < String($1.amount)
        }
        
        for rule in orderedRules {
            guard [rule.startDate, rule.endDate, rule.lastGeneratedDate, rule.recurrenceEffectiveDate]
                .compactMap({ $0 }).allSatisfy({ $0.timeIntervalSince1970.isFinite }) else {
                throw PlanningError.invalidDate
            }
            
            let schedule = RecurringExpenseSchedule(rule: rule, legacyCalendar: calendar)
            var advances = 0

            // firstPendingOccurrence has an internal conversion-boundary loop. Bound that
            // scan before invoking it, without changing the canonical schedule or its model.
            if rule.recurrenceTimeZoneIdentifier != nil, let boundary = rule.recurrenceEffectiveDate {
                var cursor = rule.lastGeneratedDate
                var candidate: Date?

                if rule.frequency == .monthly, boundary >= rule.startDate {
                    cursor = max(cursor ?? boundary, boundary)
                }
                
                if let cursor {
                    candidate = schedule.nextOccurrence(after: cursor)
                } else if rule.endDate.map({ rule.startDate <= $0 }) ?? true {
                    candidate = rule.startDate
                }
                
                while let date = candidate, date <= boundary {
                    guard advances < 100_000 else {
                        throw PlanningError.advanceLimitExceeded(ruleID: rule.id)
                    }
                    advances += 1
                    candidate = schedule.nextOccurrence(after: date)
                }
            }

            var next = schedule.firstPendingOccurrence()
            while let date = next, date < targetEnd {
                if date >= firstTargetDay {
                    let day = localCalendar.startOfDay(for: date)
                    let key = RecurringExpenseOccurrence.key(ruleID: rule.id, scheduledDate: date)
                    if seen.insert(key).inserted {
                        groups[day, default: []].append((date, rule))
                    }
                }
                guard advances < 100_000 else {
                    throw PlanningError.advanceLimitExceeded(ruleID: rule.id)
                }
                advances += 1
                next = schedule.nextOccurrence(after: date)
            }
        }

        let code = LedgerCurrency.validatedCode(currencyCode)
        
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        if let code { formatter.currencyCode = code }
        
        let identifierFormatter = DateFormatter()
        identifierFormatter.locale = Locale(identifier: "en_US_POSIX")
        identifierFormatter.calendar = localCalendar
        identifierFormatter.timeZone = localCalendar.timeZone
        identifierFormatter.dateFormat = "yyyy-MM-dd"

        var result: [Summary] = []
        for day in groups.keys.sorted() {
            guard let fireDay = localCalendar.date(byAdding: .day, value: -lead, to: day) else {
                throw PlanningError.invalidDate
            }
            var resolved: Date?
            // Foundation may skip a partial-hour DST gap when minutes are specified.
            // Matching the hour alone falls back to its first valid time on that day.
            for components in [DateComponents(hour: time / 60, minute: time % 60, second: 0),
                               DateComponents(hour: time / 60)] {
                if let candidate = localCalendar.nextDate(
                    after: fireDay.addingTimeInterval(-1), matching: components,
                    matchingPolicy: .nextTime, repeatedTimePolicy: .first
                ), localCalendar.isDate(candidate, inSameDayAs: fireDay) {
                    resolved = candidate
                    break
                }
            }
            guard let fireDate = resolved else { throw PlanningError.invalidDate }
            guard fireDate > now else { continue }
            let occurrences = groups[day, default: []].sorted {
                if $0.date != $1.date { return $0.date < $1.date }
                return $0.rule.id.uuidString < $1.rule.id.uuidString
            }
            let count = occurrences.count
            let title = count == 1
                ? String(localized: "Upcoming Recurring Expense", locale: locale)
                : String(localized: "Upcoming Recurring Expenses", locale: locale)
            let timing = lead == 1
                ? String(localized: "Scheduled tomorrow", locale: locale)
                : String(localized: "Scheduled in \(lead) days", locale: locale)
            var content = count == 1
                ? String(localized: "1 recurring expense", locale: locale)
                : String(localized: "\(count) recurring expenses", locale: locale)

            if !hideDetails, code != nil {
                var total = Decimal.zero
                var validTotal = true
                for occurrence in occurrences {
                    guard occurrence.rule.amount.isFinite,
                          var amount = Decimal(string: String(occurrence.rule.amount), locale: Locale(identifier: "en_US_POSIX")),
                          !amount.isNaN else {
                        validTotal = false
                        break
                    }
                    var sum = Decimal.zero
                    guard NSDecimalAdd(&sum, &total, &amount, .plain) == .noError, !sum.isNaN else {
                        validTotal = false
                        break
                    }
                    total = sum
                }
                if validTotal, let money = formatter.string(from: NSDecimalNumber(decimal: total)) {
                    let names = occurrences.prefix(2).map { occurrence in
                        let cleaned = String(occurrence.rule.name.unicodeScalars.filter {
                            !CharacterSet.controlCharacters.contains($0)
                                && !CharacterSet.newlines.contains($0)
                        }).trimmingCharacters(in: .whitespacesAndNewlines)
                        if cleaned.isEmpty { return String(localized: "Recurring expense", locale: locale) }
                        return cleaned.count > 40 ? String(cleaned.prefix(39)) + "…" : cleaned
                    }
                    let label: String
                    if count == 1 {
                        label = names[0]
                    } else if count == 2 {
                        label = String(localized: "\(names[0]) and \(names[1])", locale: locale)
                    } else {
                        label = String(localized: "\(names[0]), \(names[1]) and \(count - 2) more", locale: locale)
                    }
                    content = count == 1
                        ? String(localized: "\(label) · \(money)", locale: locale)
                        : String(localized: "\(label) · \(money) total", locale: locale)
                }
            }
            result.append(Summary(
                identifier: "sage.recurring.v1." + identifierFormatter.string(from: fireDate),
                fireDate: fireDate,
                title: title,
                body: String(localized: "\(content) · \(timing)", locale: locale)
            ))
        }
        return result
    }
}
