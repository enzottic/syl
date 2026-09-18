import Foundation
import Testing
@testable import SageKit

@Suite("Relative expense dates")
struct RelativeDateTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Denver")!
        return calendar
    }

    private func date(_ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
    }

    @Test func changesFromTodayToYesterdayAtMidnight() {
        let expense = date(7, hour: 12)
        #expect(expense.relative(to: date(7, hour: 23, minute: 59), calendar: calendar) == "Today")
        #expect(expense.relative(to: date(8), calendar: calendar) == "Yesterday")
    }

    @Test func refreshAfterSeveralDaysUsesCalendarDaysAcrossDaylightSaving() {
        let expense = date(7, hour: 23)
        let now = date(9)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE"
        #expect(expense.relative(to: now, calendar: calendar) == formatter.string(from: expense))
        #expect(date(8, hour: 23).relative(to: now, calendar: calendar) == "Yesterday")
    }
}
