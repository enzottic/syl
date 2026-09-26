import Foundation
import Testing
@testable import SageKit

@Suite("Recurring reminder plan")
@MainActor
struct RecurringReminderPlanTests {
    private let locale = Locale(identifier: "en_US")

    private func calendar(_ zone: String = "GMT", identifier: Calendar.Identifier = .gregorian) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func rule(
        _ name: String = "Netflix",
        amount: Double = 15.99,
        start: String = "2026-08-11T12:00:00Z",
        frequency: RecurrenceFrequency = .daily,
        zone: String? = "GMT"
    ) -> RecurringExpenseRule {
        let startDate = date(start)
        return RecurringExpenseRule(
            name: name, amount: amount, note: "Private note", category: .needs,
            frequency: frequency, startDate: startDate, endDate: startDate,
            recurrenceTimeZoneIdentifier: zone
        )
    }

    private func plan(
        _ rules: [RecurringExpenseRule],
        lead: Int = 1,
        timeMinutes: Int = 540,
        hidden: Bool = true,
        currency: String? = "USD",
        now: String = "2026-08-10T08:00:00Z",
        deviceCalendar: Calendar? = nil
    ) throws -> [RecurringReminderPlan.Summary] {
        try RecurringReminderPlan.summaries(
            rules: rules, daysBefore: lead, timeMinutes: timeMinutes, hideDetails: hidden, currencyCode: currency,
            now: date(now), calendar: deviceCalendar ?? calendar(), locale: locale
        )
    }

    @Test(arguments: [(0, "00:00"), (540, "09:00"), (1125, "18:45"), (1439, "23:59")])
    func groupsWholeLocalDayAndDeduplicatesOccurrenceKeys(timeMinutes: Int, time: String) throws {
        let early = rule(start: "2026-08-11T00:01:00Z")
        let late = rule("Internet", amount: 60, start: "2026-08-11T23:59:00Z")
        let duplicate = rule(start: "2026-08-11T00:01:00Z")
        duplicate.id = early.id
        let now = "2026-08-09T23:59:00Z"
        let summaries = try plan([late, early, duplicate, early], timeMinutes: timeMinutes, hidden: false, now: now)
        #expect(summaries.count == 1)
        let summary = try #require(summaries.first)
        #expect(summary.fireDate == date("2026-08-10T\(time):00Z"))
        #expect(summary.identifier == "sage.recurring.v1.2026-08-10")
        #expect(summary.title == "Upcoming Recurring Expenses")
        #expect(summary.body == "Netflix and Internet · $75.99 total · Scheduled tomorrow")
        #expect(try plan([early, duplicate, late], timeMinutes: timeMinutes, hidden: false, now: now) == summaries)
        let defaultTime = try #require(plan([early, late], hidden: false, now: now).first)
        #expect(summary.identifier == defaultTime.identifier)
        #expect(summary.title == defaultTime.title)
        #expect(summary.body == defaultTime.body)
    }

    @Test(arguments: [0, 540, 1125, 1439], [-1, 0, 1])
    func skipsFireDatesAtOrBeforeNow(timeMinutes: Int, offsetMinutes: Int) throws {
        let fireDate = date("2026-08-10T00:00:00Z").addingTimeInterval(Double(timeMinutes) * 60)
        let summaries = try RecurringReminderPlan.summaries(
            rules: [rule()], timeMinutes: timeMinutes, currencyCode: "USD",
            now: fireDate.addingTimeInterval(Double(offsetMinutes) * 60), calendar: calendar(), locale: locale
        )
        #expect(summaries.map(\.fireDate) == (offsetMinutes < 0 ? [fireDate] : []))
    }

    @Test(arguments: [Int.min, -1, 1440, Int.max])
    func invalidTimesFallBackToNineAM(timeMinutes: Int) throws {
        let rules = [rule()]
        let expected = try plan(rules)
        #expect(expected.first?.fireDate == date("2026-08-10T09:00:00Z"))
        #expect(try plan(rules, timeMinutes: timeMinutes) == expected)
    }

    @Test(arguments: [1, 7])
    func leadUsesCalendarDays(lead: Int) throws {
        let target = rule(start: "2026-08-17T23:00:00Z")
        let summary = try #require(plan([target], lead: lead).first)
        #expect(summary.fireDate == date(lead == 1 ? "2026-08-16T09:00:00Z" : "2026-08-10T09:00:00Z"))
        #expect(summary.body == (lead == 1
            ? "1 recurring expense · Scheduled tomorrow"
            : "1 recurring expense · Scheduled in 7 days"))
    }

    @Test
    func defaultsAndInvalidLeadsArePrivateAndOneDay() throws {
        let rules = [rule()]
        let expected = try plan(rules)
        #expect(try RecurringReminderPlan.summaries(
            rules: rules, currencyCode: "USD", now: date("2026-08-10T08:00:00Z"),
            calendar: calendar(), locale: locale
        ) == expected)
        #expect(try plan(rules, lead: 0) == expected)
        #expect(try plan(rules, lead: 8) == expected)
        #expect(expected.first?.title == "Upcoming Recurring Expense")
        #expect(expected.first?.body == "1 recurring expense · Scheduled tomorrow")
    }

    @Test
    func fixedMonthEndAndInclusiveEndDate() throws {
        let monthly = rule(start: "2026-01-31T12:00:00Z", frequency: .monthly)
        monthly.lastGeneratedDate = monthly.startDate
        monthly.endDate = date("2026-03-31T12:00:00Z")
        let summaries = try plan([monthly], now: "2026-02-01T08:00:00Z")
        #expect(summaries.map(\.fireDate) == [date("2026-02-27T09:00:00Z"), date("2026-03-30T09:00:00Z")])
        monthly.endDate = date("2026-03-31T11:59:59Z")
        #expect(try plan([monthly], now: "2026-02-01T08:00:00Z").count == 1)
    }

    @Test(arguments: ["spring", "fall"])
    func daylightSavingKeepsNineAMAndCalendarLead(season: String) throws {
        let spring = season == "spring"
        let recurring = rule(
            start: spring ? "2026-03-07T07:30:00Z" : "2026-10-31T05:30:00Z",
            zone: "America/New_York"
        )
        recurring.lastGeneratedDate = recurring.startDate
        recurring.endDate = date(spring ? "2026-03-09T06:30:00Z" : "2026-11-02T06:30:00Z")
        let summaries = try plan(
            [recurring], now: spring ? "2026-03-07T13:00:00Z" : "2026-10-31T12:00:00Z",
            deviceCalendar: calendar("America/New_York")
        )
        #expect(summaries.map(\.fireDate) == (spring
            ? [date("2026-03-07T14:00:00Z"), date("2026-03-08T13:00:00Z")]
            : [date("2026-10-31T13:00:00Z"), date("2026-11-01T14:00:00Z")]))
    }

    @Test(arguments: [
        ("America/New_York", 150, "2026-03-09T16:00:00Z", "2026-03-10T16:00:00Z",
         "2026-03-08T05:00:00Z", "2026-03-08T07:00:00Z", "2026-03-09T06:30:00Z"),
        ("America/New_York", 90, "2026-11-02T17:00:00Z", "2026-11-03T17:00:00Z",
         "2026-11-01T04:00:00Z", "2026-11-01T05:30:00Z", "2026-11-02T06:30:00Z"),
        ("Australia/Lord_Howe", 135, "2026-10-05T01:00:00Z", "2026-10-06T01:00:00Z",
         "2026-10-03T13:30:00Z", "2026-10-03T15:30:00Z", "2026-10-04T15:15:00Z"),
    ])
    func customDSTTimeUsesNextValidOrFirstRepeatedTimeAndReturnsToChosenTime(
        zone: String, timeMinutes: Int, start: String, end: String,
        now: String, transitionFire: String, nextFire: String
    ) throws {
        let recurring = rule(start: start, zone: zone)
        recurring.endDate = date(end)
        let summaries = try plan([recurring], timeMinutes: timeMinutes, now: now, deviceCalendar: calendar(zone))
        #expect(summaries.map(\.fireDate) == [date(transitionFire), date(nextFire)])

        // Once the first occurrence has elapsed, a repeated hour must not offer a second reminder.
        let afterFirst = try RecurringReminderPlan.summaries(
            rules: [recurring], timeMinutes: timeMinutes, currencyCode: "USD",
            now: date(transitionFire).addingTimeInterval(60), calendar: calendar(zone), locale: locale
        )
        #expect(afterFirst.map(\.fireDate) == [date(nextFire)])
    }

    @Test
    func fixedZoneOccurrencesGroupByDeviceDayNotRuleDay() throws {
        let tokyo = rule("Tokyo", start: "2026-08-12T00:00:00Z", zone: "Asia/Tokyo")
        tokyo.lastGeneratedDate = tokyo.startDate
        tokyo.endDate = date("2026-08-13T00:00:00Z")
        let local = rule("Local", start: "2026-08-12T17:00:00Z", zone: "America/Los_Angeles")
        let summaries = try plan(
            [tokyo, local], now: "2026-08-11T15:00:00Z",
            deviceCalendar: calendar("America/Los_Angeles")
        )
        #expect(summaries.count == 1)
        #expect(summaries.first?.fireDate == date("2026-08-11T16:00:00Z"))
        #expect(summaries.first?.body == "2 recurring expenses · Scheduled tomorrow")
    }

    @Test
    func legacyRecurrenceUsesSuppliedNonGregorianCalendar() throws {
        let supplied = calendar(identifier: .hebrew)
        let legacy = rule(start: "2026-01-15T12:00:00Z", frequency: .monthly, zone: nil)
        legacy.lastGeneratedDate = legacy.startDate
        legacy.endDate = nil
        let next = try #require(RecurringExpenseSchedule(rule: legacy, legacyCalendar: supplied).firstPendingOccurrence())
        legacy.endDate = next
        let summary = try #require(plan([legacy], now: "2026-01-15T08:00:00Z", deviceCalendar: supplied).first)
        let local = calendar()
        let expectedDay = try #require(local.date(byAdding: .day, value: -1, to: next))
        #expect(summary.fireDate == local.date(bySettingHour: 9, minute: 0, second: 0, of: expectedDay))
        #expect(summary.identifier.hasPrefix("sage.recurring.v1.2026-"))
    }

    @Test
    func honorsCreationCursorAndConversionBoundaryWithoutMutatingRule() throws {
        let recurring = rule()
        recurring.lastGeneratedDate = recurring.startDate
        recurring.recurrenceEffectiveDate = date("2026-08-12T12:00:00Z")
        recurring.endDate = date("2026-08-13T12:00:00Z")
        let originalID = recurring.id
        let summaries = try plan([recurring], hidden: false)
        #expect(summaries.map(\.fireDate) == [date("2026-08-12T09:00:00Z")])
        #expect(recurring.id == originalID)
        #expect(recurring.name == "Netflix")
        #expect(recurring.amount == 15.99)
        #expect(recurring.note == "Private note")
        #expect(recurring.category == .needs)
        #expect(recurring.frequency == .daily)
        #expect(recurring.startDate == date("2026-08-11T12:00:00Z"))
        #expect(recurring.lastGeneratedDate == recurring.startDate)
        #expect(recurring.endDate == date("2026-08-13T12:00:00Z"))
        #expect(recurring.recurrenceEffectiveDate == date("2026-08-12T12:00:00Z"))
        #expect(recurring.recurrenceTimeZoneIdentifier == "GMT")
        #expect(try plan([recurring], hidden: false) == summaries)
    }

    @Test
    func monthlyConversionSkipsTheCompletedBoundaryMonth() throws {
        let monthly = rule(start: "2026-01-31T12:00:00Z", frequency: .monthly)
        monthly.lastGeneratedDate = monthly.startDate
        monthly.recurrenceEffectiveDate = date("2026-03-28T12:00:00Z")
        monthly.endDate = date("2026-04-30T12:00:00Z")
        let summaries = try plan([monthly], now: "2026-03-01T08:00:00Z")
        #expect(summaries.map(\.fireDate) == [date("2026-04-29T09:00:00Z")])
        #expect(monthly.lastGeneratedDate == monthly.startDate)
    }

    @Test
    func identifiersBelongToFireDayRegardlessOfLeadOrLocale() throws {
        let daily = rule()
        daily.endDate = date("2026-08-20T12:00:00Z")
        let one = try #require(plan([daily]).first)
        let seven = try #require(plan([daily], lead: 7).first)
        #expect(one.identifier == seven.identifier)
        #expect(RecurringReminderPlan.owns(one.identifier))
        #expect(RecurringReminderPlan.owns("recurring-day-2026-08-10"))
        #expect(RecurringReminderPlan.owns("recurring-added-any-rule"))
        #expect(!RecurringReminderPlan.owns("sage.recurring.v2.2026-08-10"))
        #expect(!RecurringReminderPlan.owns("unrelated"))
        let otherLocale = try RecurringReminderPlan.summaries(
            rules: [daily], currencyCode: "USD", now: date("2026-08-10T08:00:00Z"),
            calendar: calendar(identifier: .buddhist), locale: Locale(identifier: "ar_SA")
        )
        #expect(otherLocale.first?.identifier == one.identifier)
    }

    @Test
    func detailedCountsUseStableUUIDOrderAndDecimalTotals() throws {
        let rules = [rule("Netflix", amount: 0.1), rule("Internet", amount: 0.2), rule("Rent", amount: 10), rule("Gym", amount: 20)]
        for (index, rule) in rules.enumerated() {
            rule.id = UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)")!
        }
        #expect(try plan([rules[0]], hidden: false).first?.body == "Netflix · $0.10 · Scheduled tomorrow")
        #expect(try plan(Array(rules.reversed()), hidden: false).first?.body
            == "Netflix, Internet and 2 more · $30.30 total · Scheduled tomorrow")
        for rule in rules {
            rule.startDate = date("2026-08-13T12:00:00Z")
            rule.endDate = rule.startDate
        }
        #expect(try plan(rules, lead: 3).first?.body == "4 recurring expenses · Scheduled in 3 days")
    }

    @Test(arguments: [nil, "", "not-a-currency", "usd", " USD ", "XXX", "XTS"] as [String?])
    func missingOrInvalidCurrencyNeverExposesDetails(code: String?) throws {
        let summary = try #require(plan([rule()], hidden: false, currency: code).first)
        #expect(summary.body == "1 recurring expense · Scheduled tomorrow")
    }

    @Test(arguments: [Double.nan, Double.infinity, -Double.infinity, Double.greatestFiniteMagnitude])
    func unsafeAmountsFallBackToPrivateBody(amount: Double) throws {
        let summary = try #require(plan([rule(amount: amount)], hidden: false).first)
        #expect(summary.body == "1 recurring expense · Scheduled tomorrow")
    }

    @Test
    func detailsSanitizeAndLimitNamesAndUseLocaleCurrency() throws {
        let dirty = rule("Net\nflix\r\t\u{0000}\u{202E}")
        #expect(try plan([dirty], hidden: false).first?.body == "Netflix · $15.99 · Scheduled tomorrow")
        let long = rule(String(repeating: "é", count: 60))
        let summary = try #require(plan([long], hidden: false).first)
        #expect(summary.body == String(repeating: "é", count: 39) + "… · $15.99 · Scheduled tomorrow")
        #expect(try plan([rule("\n\t")], hidden: false).first?.body == "Recurring expense · $15.99 · Scheduled tomorrow")
        let french = Locale(identifier: "fr_FR")
        let localized = try RecurringReminderPlan.summaries(
            rules: [rule()], hideDetails: false, currencyCode: "EUR",
            now: date("2026-08-10T08:00:00Z"), calendar: calendar(), locale: french
        )
        let formatter = NumberFormatter()
        formatter.locale = french
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        let money = try #require(formatter.string(from: NSDecimalNumber(string: "15.99")))
        #expect(localized.first?.body.contains(money) == true)
    }

    @Test(arguments: [1, 7])
    func ninetyCalendarDayHorizonDoesNotApplyNotificationCapacity(lead: Int) throws {
        let daily = rule(start: "2026-08-01T23:59:00Z")
        daily.endDate = nil
        let summaries = try plan([daily], lead: lead)
        #expect(summaries.count == 90)
        #expect(summaries.first?.fireDate == date("2026-08-10T09:00:00Z"))
        #expect(summaries.last?.fireDate == date("2026-11-07T09:00:00Z"))
        #expect(try plan([daily], lead: lead, now: "2026-08-10T10:00:00Z").count == 89)
    }

    @Test
    func malformedDatesThrowAnExplicitPlanningError() throws {
        let invalid = rule()
        invalid.startDate = Date(timeIntervalSince1970: .nan)
        #expect(throws: RecurringReminderPlan.PlanningError.invalidDate) {
            try plan([invalid])
        }
    }

    @Test(arguments: [false, true])
    func ancientRulesThrowInsteadOfSilentlyTruncating(hasConversionBoundary: Bool) throws {
        let ancient = rule(start: "1700-01-01T12:00:00Z")
        ancient.endDate = nil
        if hasConversionBoundary { ancient.recurrenceEffectiveDate = date("2026-08-01T12:00:00Z") }
        #expect(throws: RecurringReminderPlan.PlanningError.advanceLimitExceeded(ruleID: ancient.id)) {
            try plan([ancient])
        }
        #expect(ancient.lastGeneratedDate == nil)
    }
}
