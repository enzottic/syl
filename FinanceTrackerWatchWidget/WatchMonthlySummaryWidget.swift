import SwiftUI
import WidgetKit

struct WatchMonthlySummaryEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchSnapshot?
}

struct WatchMonthlySummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchMonthlySummaryEntry {
        WatchMonthlySummaryEntry(date: WatchSnapshot.preview.generatedAt, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchMonthlySummaryEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : WatchMonthlySummaryEntry(date: .now, snapshot: WatchSnapshotCache.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchMonthlySummaryEntry>) -> Void) {
        let now = Date.now
        let snapshot = WatchSnapshotCache.load()
        var entries = [WatchMonthlySummaryEntry(date: now, snapshot: snapshot)]
        // Change the stale label at the boundary even if no phone transfer arrives.
        if let snapshot {
            let staleDate = min(snapshot.monthEnd, snapshot.generatedAt.addingTimeInterval(86_400))
            if staleDate > now { entries.append(WatchMonthlySummaryEntry(date: staleDate, snapshot: snapshot)) }
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
    }
}

struct WatchMonthlySummaryWidgetView: View {
    let entry: WatchMonthlySummaryEntry
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let snapshot = entry.snapshot {
                Text(snapshot.monthLabel).font(.caption2).foregroundStyle(.secondary)
                Text(snapshot.totalSpent, format: .currency(code: snapshot.currencyCode))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                if snapshot.monthlyBudget > 0 {
                    if renderingMode == .fullColor {
                        WatchBudgetBar(total: snapshot.totalSpent, budget: snapshot.monthlyBudget, categories: snapshot.categories)
                    } else {
                        ProgressView(value: min(max(snapshot.totalSpent / snapshot.monthlyBudget, 0), 1))
                            .widgetAccentable()
                            .accessibilityHidden(true)
                    }
                }
                if snapshot.isStale(at: entry.date) {
                    Text("Open Syl on iPhone to refresh").font(.caption2)
                }
            } else {
                Text("Monthly spending").font(.headline)
                Text("Open Syl on iPhone to sync").font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .privacySensitive()
        .containerBackground(.black, for: .widget)
        .widgetURL(URL(string: "syl-watch://monthly-summary"))
    }
}

@main
struct WatchMonthlySummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchSnapshotCache.widgetKind, provider: WatchMonthlySummaryProvider()) { entry in
            WatchMonthlySummaryWidgetView(entry: entry)
        }
        .configurationDisplayName("Monthly spending")
        .description("Your spending and budget progress this month.")
        .supportedFamilies([.accessoryRectangular])
    }
}

#Preview(as: .accessoryRectangular) {
    WatchMonthlySummaryWidget()
} timeline: {
    WatchMonthlySummaryEntry(date: WatchSnapshot.preview.generatedAt, snapshot: .preview)
    WatchMonthlySummaryEntry(date: .now, snapshot: nil)
    WatchMonthlySummaryEntry(date: WatchSnapshot.preview.monthEnd, snapshot: .preview)
}
