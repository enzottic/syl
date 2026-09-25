import Foundation

/// The daily chart uses income as context only when showing the unfiltered total.
public enum SpendingChartScale {
    public static func domain(points: [SpendingMonthSummary.Point], monthlyIncome: Double,
                              showsUnfilteredTotal: Bool) -> ClosedRange<Double> {
        var lowest = 0.0
        var highest = 0.0
        for point in points where point.total.isFinite {
            lowest = min(lowest, point.total)
            highest = max(highest, point.total)
        }

        // Leave room for the line and point marks at each extreme, including refunds.
        let lowerBound = min(0, lowest * 1.05)
        let incomeReference = showsUnfilteredTotal ? monthlyIncome : 0
        let upperBound = max(1, incomeReference, highest * 1.05)
        return lowerBound...upperBound
    }
}
