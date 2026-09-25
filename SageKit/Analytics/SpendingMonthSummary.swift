import Foundation

/// Recorded monthly spending and a calendar-day baseline from recent complete months.
/// Pass the same filtered expense history used elsewhere in Stats.
public struct SpendingMonthSummary {
    public struct Point: Identifiable {
        public let day: Int
        public let total: Double
        public var id: Int { day }

        public init(day: Int, total: Double) {
            self.day = day
            self.total = total
        }
    }

    public let expenses: [Expense]
    public let total: Double
    public let previousTotal: Double
    public let days: [Point]
    public let categoryDays: [ExpenseCategory: [Point]]
    public let averageDays: [Point]
    public let historicalMonthCount: Int

    public init(month: Date, expenses: [Expense], firstRecordedDate: Date? = nil,
                now: Date = Date(), calendar: Calendar = .current) {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let dayRange = calendar.range(of: .day, in: .month, for: month),
              interval.start <= now else {
            self.expenses = []
            total = 0
            previousTotal = 0
            days = []
            categoryDays = [:]
            averageDays = []
            historicalMonthCount = 0
            return
        }

        let recorded = expenses.filter { $0.date <= now }
        let selected = recorded.filter { $0.date >= interval.start && $0.date < interval.end }
        self.expenses = selected
        total = selected.reduce(0) { $0 + $1.amount }
        let isCurrent = now < interval.end
        let visibleDays = isCurrent ? calendar.component(.day, from: now) : dayRange.count
        days = Self.cumulative(selected, dayCount: visibleDays, calendar: calendar)
        categoryDays = Dictionary(uniqueKeysWithValues: ExpenseCategory.allCases.map { category in
            (category, Self.cumulative(selected.filter { $0.category == category },
                                       dayCount: visibleDays, calendar: calendar))
        })

        if let previousStart = calendar.date(byAdding: .month, value: -1, to: interval.start),
           let previousRange = calendar.range(of: .day, in: .month, for: previousStart) {
            var cutoff = interval.start
            if isCurrent, calendar.component(.day, from: now) <= previousRange.count {
                // Adding calendar days preserves local wall time across daylight-saving changes.
                let components = calendar.dateComponents([.day, .hour, .minute, .second, .nanosecond], from: now)
                var previousComponents = calendar.dateComponents([.era, .year, .month], from: previousStart)
                previousComponents.day = components.day
                previousComponents.hour = components.hour
                previousComponents.minute = components.minute
                previousComponents.second = components.second
                previousComponents.nanosecond = components.nanosecond
                cutoff = calendar.date(from: previousComponents) ?? interval.start
            }
            previousTotal = recorded.filter {
                $0.date >= previousStart && $0.date < interval.start && $0.date <= cutoff
            }.reduce(0) { $0 + $1.amount }
        } else {
            previousTotal = 0
        }

        // Months before the first record are unknown, not zero-spend months.
        let firstMonth = (firstRecordedDate ?? recorded.map(\.date).min()).flatMap {
            calendar.dateInterval(of: .month, for: $0)?.start
        }
        var history: [[Point]] = []
        if let firstMonth {
            for offset in 1...6 {
                guard let start = calendar.date(byAdding: .month, value: -offset, to: interval.start),
                      start >= firstMonth,
                      let historicalInterval = calendar.dateInterval(of: .month, for: start) else { continue }
                let monthExpenses = recorded.filter {
                    $0.date >= historicalInterval.start && $0.date < historicalInterval.end
                }
                // Extra days after a shorter month retain that month's final total.
                history.append(Self.cumulative(monthExpenses, dayCount: dayRange.count, calendar: calendar))
            }
        }
        historicalMonthCount = history.count
        averageDays = history.isEmpty ? [] : dayRange.map { day in
            Point(day: day, total: history.reduce(0) { $0 + $1[day - 1].total } / Double(history.count))
        }
    }

    private static func cumulative(_ expenses: [Expense], dayCount: Int, calendar: Calendar) -> [Point] {
        var daily: [Int: Double] = [:]
        for expense in expenses {
            daily[calendar.component(.day, from: expense.date), default: 0] += expense.amount
        }
        var running = 0.0
        return (1...dayCount).map { day in
            running += daily[day, default: 0]
            return Point(day: day, total: running)
        }
    }
}
