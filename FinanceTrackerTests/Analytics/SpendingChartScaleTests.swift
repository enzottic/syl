import Testing
@testable import SageKit

@Suite("Spending chart scale")
struct SpendingChartScaleTests {
    @Test
    func unfilteredTotalKeepsIncomeReference() {
        let domain = SpendingChartScale.domain(
            points: [.init(day: 1, total: 100), .init(day: 2, total: 800)],
            monthlyIncome: 1_000, showsUnfilteredTotal: true
        )

        #expect(domain.lowerBound == 0)
        #expect(domain.upperBound == 1_000)
    }

    @Test
    func spendingAboveIncomeStaysVisible() {
        let domain = SpendingChartScale.domain(
            points: [.init(day: 1, total: 1_200)],
            monthlyIncome: 1_000, showsUnfilteredTotal: true
        )

        #expect(domain.upperBound > 1_200)
    }

    @Test
    func filteredOrIsolatedLineUsesPlottedSpending() {
        let points = [SpendingMonthSummary.Point(day: 1, total: 50)]
        let domain = SpendingChartScale.domain(
            points: points, monthlyIncome: 5_000, showsUnfilteredTotal: false
        )

        #expect(domain.upperBound > 50)
        #expect(domain.upperBound < 100)
    }

    @Test
    func visibleAverageAndRefundDipFitWithinDomain() {
        let domain = SpendingChartScale.domain(
            points: [.init(day: 1, total: -25), .init(day: 2, total: 10),
                     .init(day: 3, total: 40)],
            monthlyIncome: 5_000, showsUnfilteredTotal: false
        )

        #expect(domain.lowerBound < -25)
        #expect(domain.upperBound > 40)
    }

    @Test
    func emptyFilteredChartHasPositiveRange() {
        let domain = SpendingChartScale.domain(
            points: [], monthlyIncome: 5_000, showsUnfilteredTotal: false
        )

        #expect(domain == 0...1)
    }
}
