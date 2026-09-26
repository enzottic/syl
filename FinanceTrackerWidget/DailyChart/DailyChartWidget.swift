//
//  DailyChartWidget.swift
//  FinanceTracker
//
//  Created by Enzo on 9/6/26.
//

import SwiftUI
import WidgetKit
import SageKit

struct DailyChartEntry: TimelineEntry {
    let date: Date
    let total: Double
    let days: [SpendingMonthSummary.Point]
    let averageDays: [SpendingMonthSummary.Point]
    let historicalMonthCount: Int
    let daysInMonth: Int
    let hasExpenses: Bool
    let currencyCode: String?
    var isUnavailable = false

    static func empty(at date: Date, isUnavailable: Bool = false) -> DailyChartEntry {
        DailyChartEntry(date: date, total: 0, days: [], averageDays: [], historicalMonthCount: 0,
                        daysInMonth: Calendar.current.range(of: .day, in: .month, for: date)?.count ?? 31,
                        hasExpenses: false, currencyCode: LedgerCurrency.currentCode, isUnavailable: isUnavailable)
    }

    static var preview: DailyChartEntry {
        let calendar = Calendar.current
        let date = calendar.date(bySetting: .day, value: 18, of: .now) ?? .now
        let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count ?? 31
        let days = (1...18).map { day in
            SpendingMonthSummary.Point(day: day, total: 240 + Double(day / 3) * 155 + Double(day) * 24)
        }
        return DailyChartEntry(date: date, total: days.last?.total ?? 0, days: days,
                               averageDays: (1...daysInMonth).map { .init(day: $0, total: Double($0) * 105) },
                               historicalMonthCount: 6, daysInMonth: daysInMonth, hasExpenses: true, currencyCode: "USD")
    }
}

struct DailyChartProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyChartEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (DailyChartEntry) -> Void) {
        Task { @MainActor in completion(context.isPreview ? .preview : loadEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyChartEntry>) -> Void) {
        Task { @MainActor in
            let entry = context.isPreview ? .preview : loadEntry()
            completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(15 * 60))))
        }
    }

    @MainActor
    private func loadEntry() -> DailyChartEntry {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return .preview
        }
        let date = Date.now
        guard let store = ExpenseStore.shared else { return .empty(at: date, isUnavailable: true) }
        do {
            // Keep SwiftData models on the main actor; the timeline receives only chart values.
            let summary = SpendingMonthSummary(month: date, expenses: try store.fetchExpenses(), now: date)
            return DailyChartEntry(date: date, total: summary.total, days: summary.days,
                                   averageDays: summary.averageDays, historicalMonthCount: summary.historicalMonthCount,
                                   daysInMonth: Calendar.current.range(of: .day, in: .month, for: date)?.count ?? 31,
                                   hasExpenses: !summary.expenses.isEmpty, currencyCode: LedgerCurrency.currentCode)
        } catch {
            return .empty(at: date, isUnavailable: true)
        }
    }
}

struct DailyChartEntryView: View {
    let entry: DailyChartEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Daily Spending")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(entry.date, format: .dateTime.month(.abbreviated).year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            if entry.isUnavailable {
                ContentUnavailableView("Spending unavailable", systemImage: "exclamationmark.triangle",
                                       description: Text("Open Syl to reload your data."))
            } else if let currencyCode = entry.currencyCode {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.total, format: .currency(code: currencyCode))
                        .font(.largeTitle.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Text("Spent so far")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                DailySpendingChart(series: [.init(category: nil, points: entry.days, color: .sage)],
                                   averageDays: entry.averageDays, daysInMonth: entry.daysInMonth,
                                   currencyCode: currencyCode)
                    .frame(maxHeight: .infinity)

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Capsule().fill(.sage).frame(width: 12, height: 3).accessibilityHidden(true)
                        Text("This month")
                    }
                    if entry.historicalMonthCount > 0 {
                        HStack(spacing: 4) {
                            HStack(spacing: 2) {
                                Capsule().frame(width: 5, height: 2)
                                Capsule().frame(width: 5, height: 2)
                            }
                            .accessibilityHidden(true)
                            Text("\(entry.historicalMonthCount)-month average")
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

                if !entry.hasExpenses {
                    Text("No expenses this month. Add one in Syl.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView("Confirm your currency", systemImage: "dollarsign.circle",
                                       description: Text("Open Syl to confirm your ledger currency."))
            }
        }
        .fontDesign(.rounded)
    }
}

struct DailyChartWidget: Widget {
    let kind = "SageDailyChartWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyChartProvider()) { entry in
            DailyChartEntryView(entry: entry)
                .containerBackground(.sageBackground, for: .widget)
        }
        .configurationDisplayName("Daily Spending")
        .description("Follow this month's cumulative spending against your recent monthly average.")
        .supportedFamilies([.systemLarge])
    }
}

#Preview("Daily Spending", as: .systemLarge) {
    DailyChartWidget()
} timeline: {
    DailyChartEntry.preview
}
