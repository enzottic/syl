import SwiftUI
import Charts

public struct SpendingChartSeries: Identifiable {
    public let category: ExpenseCategory?
    public let points: [SpendingMonthSummary.Point]
    public let color: Color
    /// Hidden lines stay in the chart at zero opacity so hiding and showing them fades in place.
    public let isVisible: Bool
    public var id: String { category?.rawValue ?? "Total" }

    public init(category: ExpenseCategory?, points: [SpendingMonthSummary.Point], color: Color,
                isVisible: Bool = true) {
        self.category = category
        self.points = points
        self.color = color
        self.isVisible = isVisible
    }
}

/// Renders snapshot values without querying storage or owning app interaction state.
/// Supply one series per category/total, unique ascending days, and a valid month length.
///
/// Swift Charts has no fade transition: marks that are removed or inserted animate to and from
/// the plot's origin (the top-left corner). So every mark here stays alive for the chart's
/// lifetime, and content that comes and goes animates its opacity instead of its presence.
public struct DailySpendingChart: View {
    /// A monthly spending limit drawn as a dashed reference line behind the spending lines.
    /// Pass every budget that can be shown and toggle `isVisible`, so switching between them
    /// cross-fades rather than inserting and removing lines.
    public struct Budget: Identifiable {
        public let id: String
        public let amount: Double
        public let color: Color
        public let isVisible: Bool

        public init(id: String, amount: Double, color: Color, isVisible: Bool) {
            self.id = id
            self.amount = amount
            self.color = color
            self.isVisible = isVisible
        }
    }

    private let series: [SpendingChartSeries]
    private let averageDays: [SpendingMonthSummary.Point]
    private let daysInMonth: Int
    private let selectedDay: Int?
    private let currencyCode: String?
    private let budgets: [Budget]

    /// The last non-empty average, kept so a disappearing average fades out where it was.
    @State private var retainedAverageDays: [SpendingMonthSummary.Point]

    public init(series: [SpendingChartSeries], averageDays: [SpendingMonthSummary.Point] = [],
                daysInMonth: Int, currencyCode: String?, selectedDay: Int? = nil, budgets: [Budget] = []) {
        self.series = series
        self.averageDays = averageDays
        self.daysInMonth = daysInMonth
        self.selectedDay = selectedDay
        self.currencyCode = currencyCode
        self.budgets = budgets
        _retainedAverageDays = State(initialValue: averageDays)
    }

    public var body: some View {
        let showsAverage = !averageDays.isEmpty
        Chart {
            ForEach(budgets) { budget in
                RuleMark(y: .value("Budget", budget.amount))
                    .foregroundStyle(budget.color.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .opacity(budget.isVisible ? 1 : 0)
                    .annotation(position: .top, alignment: .leading, spacing: 2,
                                overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))) {
                        Text("Budget \(currencyLabel(budget.amount, rounded: true))")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .opacity(budget.isVisible ? 1 : 0)
                    }
                    .accessibilityLabel("Budget")
                    .accessibilityValue(currencyLabel(budget.amount))
                    .accessibilityHidden(!budget.isVisible)
            }
            ForEach(stableLinePoints(showsAverage ? averageDays : retainedAverageDays), id: \.id) { item in
                let point = item.point
                LineMark(x: .value("Day", point.day), y: .value("Spent", point.total), series: .value("Series", "Average"))
                    .foregroundStyle(Color.secondary.opacity(0.65))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .opacity(showsAverage ? 1 : 0)
                    .accessibilityHidden(!showsAverage || item.id >= averageDays.count)
            }
            ForEach(series) { line in
                spendingLine(line)
            }
            if let selectedDay {
                RuleMark(x: .value("Day", selectedDay))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartXScale(domain: 1...daysInMonth)
        .chartXAxis {
            AxisMarks(values: [1, 5, 10, 15, 20, 25, daysInMonth]) { _ in AxisValueLabel() }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(currencyLabel(amount, rounded: true)).font(.caption2)
                    }
                }
            }
        }
        .accessibilityLabel("Cumulative spending by day of the month")
        .onChange(of: averageDays.map(\.total)) {
            if !averageDays.isEmpty { retainedAverageDays = averageDays }
        }
    }

    @ChartContentBuilder
    private func spendingLine(_ line: SpendingChartSeries) -> some ChartContent {
        let points = stableLinePoints(line.points)
        let isVisible = line.isVisible && !line.points.isEmpty
        ForEach(points, id: \.id) { item in
            let point = item.point
            LineMark(x: .value("Day", point.day), y: .value("Spent", point.total), series: .value("Series", line.id))
                .foregroundStyle(line.color)
                .lineStyle(StrokeStyle(lineWidth: line.category == nil ? 3 : 2))
                .opacity(isVisible ? 1 : 0)
                .accessibilityLabel("\(line.id), day \(point.day)")
                .accessibilityValue(currencyLabel(point.total))
                .accessibilityHidden(!isVisible || item.id >= line.points.count)
        }
        // Always present (never conditional), for the same reason as the line marks.
        let tip = line.points.first(where: { $0.day == selectedDay }) ?? points[points.count - 1].point
        PointMark(x: .value("Day", tip.day), y: .value("Spent", tip.total))
            .foregroundStyle(line.color)
            .symbolSize(selectedDay == nil ? 25 : 65)
            .opacity(isVisible ? 1 : 0)
            .accessibilityHidden(true)
    }

    private func stableLinePoints(_ points: [SpendingMonthSummary.Point]) -> [(id: Int, point: SpendingMonthSummary.Point)] {
        // Keep all 31 marks alive across months; unused marks collapse onto the endpoint.
        // With no data yet, rest them on the baseline so a line that appears later rises from zero.
        guard let last = points.last else {
            return (0..<31).map { (id: $0, point: .init(day: 1, total: 0)) }
        }
        return (0..<31).map { index in
            (id: index, point: index < points.count ? points[index] : last)
        }
    }

    private func currencyLabel(_ amount: Double, rounded: Bool = false) -> String {
        guard let currencyCode else {
            let number = rounded ? amount.formatted(.number.precision(.fractionLength(0))) : amount.formatted()
            return "\(number) (currency not confirmed)"
        }
        let format = FloatingPointFormatStyle<Double>.Currency(code: currencyCode)
        return amount.formatted(rounded ? format.precision(.fractionLength(0)) : format)
    }
}

#Preview {
    DailySpendingChart(
        series: [SpendingChartSeries(category: nil, points: [
            .init(day: 1, total: 100), .init(day: 5, total: 180),
            .init(day: 10, total: 350), .init(day: 15, total: 420),
        ], color: .primary)],
        daysInMonth: 30, currencyCode: "USD",
        budgets: [.init(id: "Wants", amount: 600, color: .orange, isVisible: true)]
    )
    .chartYScale(domain: 0...1_000)
    .frame(height: 200)
    .padding()
}
