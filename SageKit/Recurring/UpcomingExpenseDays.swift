import Foundation

/// Days until an expense in the display calendar, independent of its scheduled time.
public enum UpcomingExpenseDays {
    public static func count(until date: Date, from now: Date = .now, calendar: Calendar = .current) -> Int {
        max(0, calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0)
    }
}
