import Foundation
import Testing
@testable import SageKit

@Suite("Upcoming expense days")
struct UpcomingExpenseDaysTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func date(month: Int = 9, day: Int, hour: Int = 0, minute: Int = 0) throws -> Date {
        try #require(calendar.date(from: DateComponents(
            year: 2026, month: month, day: day, hour: hour, minute: minute
        )))
    }

    @Test
    func laterTodayIsZeroDaysAway() throws {
        let now = try date(day: 7, hour: 8)
        let due = try date(day: 7, hour: 23)
        #expect(UpcomingExpenseDays.count(until: due, from: now, calendar: calendar) == 0)
    }

    @Test
    func crossingMidnightCountsAsTomorrow() throws {
        let now = try date(day: 7, hour: 23, minute: 55)
        let due = try date(day: 8)
        #expect(due.timeIntervalSince(now) == 5 * 60)
        #expect(UpcomingExpenseDays.count(until: due, from: now, calendar: calendar) == 1)
    }

    @Test(arguments: [2, 3, 4, 7])
    func countsCalendarDaysAtUpcomingThresholds(days: Int) throws {
        let now = try date(day: 7, hour: 23)
        let due = try date(day: 7 + days)
        #expect(UpcomingExpenseDays.count(until: due, from: now, calendar: calendar) == days)
    }

    @Test(arguments: [1, 6, 7])
    func pastDatesAreClampedToZero(day: Int) throws {
        let now = try date(day: 7, hour: 12)
        let due = try date(day: day)
        #expect(UpcomingExpenseDays.count(until: due, from: now, calendar: calendar) == 0)
    }

    @Test(arguments: [(3, 8, 23), (11, 1, 25)])
    func daylightSavingDaysCountAsOneDay(month: Int, day: Int, hours: Int) throws {
        let now = try date(month: month, day: day)
        let due = try date(month: month, day: day + 1)
        #expect(due.timeIntervalSince(now) == Double(hours * 3600))
        #expect(UpcomingExpenseDays.count(until: due, from: now, calendar: calendar) == 1)
    }

    @Test
    func usesTheSuppliedCalendarTimeZone() throws {
        let now = try date(day: 7, hour: 23, minute: 55)
        let due = try date(day: 8)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!

        #expect(UpcomingExpenseDays.count(until: due, from: now, calendar: calendar) == 1)
        #expect(UpcomingExpenseDays.count(until: due, from: now, calendar: utc) == 0)
    }
}
