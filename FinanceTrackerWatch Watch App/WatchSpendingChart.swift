import Charts
import SwiftUI

struct WatchSpendingChart: View {
    let snapshot: WatchSnapshot

    var body: some View {
        let days = snapshot.recentDays
        let dayLabels = days.map { String(snapshot.reportingCalendar.component(.day, from: $0.date)) }
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 4) {
                Text(days.count == 7 ? "Last 7 days" : "Recent days")
                    .font(.caption).fontWeight(.semibold)
                Text("\(days.reduce(0) { $0 + $1.amount }.formatted(.currency(code: snapshot.currencyCode))) total")
                    .font(.callout).fontWeight(.semibold)
                    .monospacedDigit().minimumScaleFactor(0.65).lineLimit(1)
                    .privacySensitive()
                if let first = days.first, let last = days.last {
                    Text("\(dateLabel(first.date)) - \(dateLabel(last.date))")
                        .font(.caption2).foregroundStyle(.secondary)
                    Chart {
                        RuleMark(y: .value("Zero", 0))
                            .foregroundStyle(.secondary.opacity(0.5))
                        ForEach(days) { day in
                            BarMark(
                                x: .value("Day", String(snapshot.reportingCalendar.component(.day, from: day.date))),
                                y: .value("Net spending", day.amount)
                            )
                                .foregroundStyle(day.amount < 0 ? Color.secondary : Color.primary)
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
                                }
                            }
                        }
                    }
                    .chartYAxis(.hidden)
                    .environment(\.calendar, snapshot.reportingCalendar)
                    .environment(\.timeZone, snapshot.reportingCalendar.timeZone)
                    .frame(maxHeight: .infinity)
                    Text("\(snapshot.reportingCalendar.isDate(last.date, inSameDayAs: context.date) ? "Today" : dateLabel(last.date)): \(last.amount.formatted(.currency(code: snapshot.currencyCode)))")
                        .font(.caption2)
                } else {
                    Text("Open Syl on iPhone to update daily spending.").font(.caption)
                }
                WatchSnapshotFreshness(snapshot: snapshot)
            }
            .lineLimit(1).minimumScaleFactor(0.65)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .scenePadding(.horizontal)
        .padding(.trailing, 8)
    }

    private func dateLabel(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(calendar: snapshot.reportingCalendar, timeZone: snapshot.reportingCalendar.timeZone)
            .month(.abbreviated).day())
    }
}

#Preview { WatchSpendingChart(snapshot: .preview) }
