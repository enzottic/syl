import Charts
import SwiftUI

struct WatchSpendingChart: View {
    let snapshot: WatchSnapshot
    @ScaledMetric(relativeTo: .title) private var amountSize = 28.0

    var body: some View {
        let days = snapshot.recentDays
        let dayLabels = days.map(dayLabel)
        let total = days.reduce(0) { $0 + $1.amount }
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let todayLabel = days.last.flatMap {
                snapshot.reportingCalendar.isDate($0.date, inSameDayAs: context.date) ? dayLabel($0) : nil
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(days.count == 7 ? "Last 7 days" : "Recent days")
                    .font(.watchPageTitle)
                Text(total, format: .currency(code: snapshot.currencyCode))
                    .font(.system(size: amountSize, weight: .semibold, design: .rounded))
                    .monospacedDigit().minimumScaleFactor(0.5)
                    .padding(.top, 4)
                    .privacySensitive()
                if let first = days.first, let last = days.last {
                    Text("\(dateLabel(first.date)) – \(dateLabel(last.date))")
                        .font(.caption2).foregroundStyle(.secondary)
                    Chart {
                        RuleMark(y: .value("Average", total / Double(days.count)))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .accessibilityHidden(true)
                        ForEach(days) { day in
                            BarMark(x: .value("Day", dayLabel(day)), y: .value("Net spending", day.amount))
                                .foregroundStyle(barColor(day, isToday: dayLabel(day) == todayLabel))
                                .cornerRadius(2)
                                .accessibilityLabel(dateLabel(day.date))
                                .accessibilityValue(day.amount.formatted(.currency(code: snapshot.currencyCode)))
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: true))
                    .chartXScale(domain: dayLabels)
                    .chartXAxis {
                        AxisMarks(values: dayLabels) { value in
                            AxisValueLabel {
                                if let label = value.as(String.self) {
                                    Text(label).font(.caption2)
                                        .foregroundStyle(label == todayLabel ? Color.accentColor : .secondary)
                                }
                            }
                        }
                    }
                    .chartYAxis(.hidden)
                    .frame(maxHeight: .infinity)
                    .padding(.top, 6)
                    .privacySensitive()
                    HStack(alignment: .firstTextBaseline) {
                        Text(todayLabel == nil ? dateLabel(last.date) : "Today")
                        + Text(" ") + Text(last.amount, format: .currency(code: snapshot.currencyCode)).fontWeight(.semibold)
                        Spacer(minLength: 4)
                        Text("avg \((total / Double(days.count)).formatted(.currency(code: snapshot.currencyCode).precision(.fractionLength(0))))")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption2)
                    .padding(.top, 4)
                    .privacySensitive()
                } else {
                    Text("Open Syl on iPhone to update daily spending.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .lineLimit(3)
                        .frame(maxHeight: .infinity)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.65)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .scenePadding(.horizontal)
        .padding(.leading, 4)
        .padding(.trailing, 10)
    }

    private func barColor(_ day: WatchDailySpending, isToday: Bool) -> Color {
        if isToday { return .accentColor }
        return day.amount < 0 ? Color.secondary.opacity(0.4) : Color.primary.opacity(0.55)
    }

    private func dayLabel(_ day: WatchDailySpending) -> String {
        String(snapshot.reportingCalendar.component(.day, from: day.date))
    }

    private func dateLabel(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(calendar: snapshot.reportingCalendar, timeZone: snapshot.reportingCalendar.timeZone)
            .month(.abbreviated).day())
    }
}

#Preview { WatchSpendingChart(snapshot: .preview) }
