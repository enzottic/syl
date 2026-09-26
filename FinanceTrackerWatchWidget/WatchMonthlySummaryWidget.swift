import SwiftUI
import WidgetKit

struct MonthlySummaryEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchSnapshot?
}

struct MonthlySummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> MonthlySummaryEntry {
        MonthlySummaryEntry(date: WatchSnapshot.preview.generatedAt, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (MonthlySummaryEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : MonthlySummaryEntry(date: .now, snapshot: WatchSnapshotCache.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MonthlySummaryEntry>) -> Void) {
        let now = Date.now
        let snapshot = WatchSnapshotCache.load()
        var entries = [MonthlySummaryEntry(date: now, snapshot: snapshot)]
        // Change the stale label at the boundary even if no phone transfer arrives.
        if let snapshot {
            let staleDate = min(snapshot.monthEnd, snapshot.generatedAt.addingTimeInterval(86_400))
            if staleDate > now { entries.append(MonthlySummaryEntry(date: staleDate, snapshot: snapshot)) }
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
    }
}

struct MonthlySummaryWidgetView: View {
    let entry: MonthlySummaryEntry
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
struct MonthlySummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchSnapshotCache.widgetKind, provider: MonthlySummaryProvider()) { entry in
            MonthlySummaryWidgetView(entry: entry)
        }
        .configurationDisplayName("Monthly spending")
        .description("Your spending and budget progress this month.")
        .supportedFamilies([.accessoryRectangular])
    }
}

#Preview(as: .accessoryRectangular) {
    MonthlySummaryWidget()
} timeline: {
    MonthlySummaryEntry(date: WatchSnapshot.preview.generatedAt, snapshot: .preview)
    MonthlySummaryEntry(date: .now, snapshot: nil)
    MonthlySummaryEntry(date: WatchSnapshot.preview.monthEnd, snapshot: .preview)
}
