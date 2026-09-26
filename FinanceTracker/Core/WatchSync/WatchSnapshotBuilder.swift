import SwiftUI
import SwiftData
import SageKit

/// Builds the current month's summary that the iPhone sends to the Watch.
enum WatchSnapshotBuilder {
    /// Returns nil when the calendar can't describe the current month.
    static func makeSnapshot(
        container: ModelContainer,
        categoryColors colors: CategoryColors,
        currencyCode: String,
        monthlyBudget: Double,
        generatedAt: Date = .now,
        calendar: Calendar = .current
    ) throws -> WatchSnapshot? {
        guard let month = calendar.dateInterval(of: .month, for: generatedAt),
              let daysInMonth = calendar.range(of: .day, in: .month, for: generatedAt),
              let weekStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: generatedAt)) else {
            return nil
        }
        
        let store = ExpenseStore(modelContainer: container)
        
        let expenses = try container.mainContext.fetch(
            ExpenseFetchDescriptors.range(start: min(month.start, weekStart), end: month.end)
        )
        
        let summary = SpendingMonthSummary(month: month.start, expenses: expenses, now: generatedAt, calendar: calendar)
        let dailyTotals = Dictionary(grouping: expenses.filter { $0.date <= generatedAt }) {
            calendar.startOfDay(for: $0.date)
        }.mapValues { $0.reduce(0) { $0 + $1.amount } }
        let recentDays = (0..<7).compactMap { offset -> WatchDailySpending? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            return WatchDailySpending(date: date, amount: dailyTotals[date] ?? 0)
        }
        
        // Resolve adaptive colors for the Watch, independently of the iPhone's appearance.
        var environment = EnvironmentValues()
        environment.colorScheme = .dark
        let categories = ExpenseCategory.allCases.map { category in
            let points = (summary.categoryDays[category] ?? []).map {
                WatchSpendingPoint(
                    day: $0.day,
                    cumulativeSpent: $0.total
                )
            }
            
            return WatchCategorySnapshot(
                categoryName: category.rawValue,
                totalSpent: points.last?.cumulativeSpent ?? 0,
                monthlyBudget: store.budget(for: category),
                color: SnapshotColor(
                    colors.color(for: category),
                    environment: environment
                ),
                spendingPoints: points
            )
        }

        return WatchSnapshot(
            generatedAt: generatedAt,
            monthStart: month.start,
            monthEnd: month.end,
            timeZoneIdentifier: calendar.timeZone.identifier,
            currencyCode: currencyCode,
            totalSpent: summary.total,
            monthlyBudget: monthlyBudget,
            categories: categories,
            daysInMonth: daysInMonth.count,
            spendingPoints: summary.days.map {
                WatchSpendingPoint(day: $0.day, cumulativeSpent: $0.total)
            },
            recentDailySpending: recentDays
        )
    }
}
