import Foundation
import Testing
@testable import SageKit

@Suite("Watch snapshot")
struct WatchSnapshotTests {
    @Test
    func olderPayloadWithoutRecentDaysStillDecodes() throws {
        let original = WatchSnapshot.preview
        let data = try JSONEncoder().encode(original)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "recentDailySpending")
        let restored = try JSONDecoder().decode(WatchSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.recentDailySpending == nil)
        #expect(restored.recentDays.count == 7)
        #expect(restored.recentDays.last?.date == original.generatedAt)
        let points = original.spendingPoints
        #expect(abs(restored.recentDays.reduce(0) { $0 + $1.amount } - (original.totalSpent - points[3].cumulativeSpent)) < 0.001)
    }

    @Test
    func datedDailySeriesPreservesRefundsAcrossMonthBoundary() throws {
        let original = WatchSnapshot.preview
        let beforeMonth = original.monthStart.addingTimeInterval(-86_400)
        let days = [WatchDailySpending(date: beforeMonth, amount: -25),
                    WatchDailySpending(date: original.monthStart, amount: 40)]
        let snapshot = WatchSnapshot(
            generatedAt: original.generatedAt, monthStart: original.monthStart, monthEnd: original.monthEnd,
            timeZoneIdentifier: original.timeZoneIdentifier, currencyCode: original.currencyCode,
            totalSpent: original.totalSpent, monthlyBudget: original.monthlyBudget, categories: original.categories,
            daysInMonth: original.daysInMonth, spendingPoints: original.spendingPoints, recentDailySpending: days
        )
        let restored = try JSONDecoder().decode(WatchSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(restored.recentDays.map(\.amount) == [-25, 40])
        #expect(restored.recentDays.first?.date == beforeMonth)
    }

    @Test
    func staleAtDayOldAndMonthRollover() {
        let snapshot = WatchSnapshot.preview
        #expect(!snapshot.isStale(at: snapshot.generatedAt))
        #expect(!snapshot.isStale(at: snapshot.generatedAt.addingTimeInterval(86_399)))
        #expect(snapshot.isStale(at: snapshot.generatedAt.addingTimeInterval(86_400)))
        #expect(snapshot.isStale(at: snapshot.monthEnd))
        #expect(snapshot.reportingCalendar.timeZone.secondsFromGMT() == 0)
    }
}
