import SwiftUI

struct SageDashboardView: View {
    @Environment(SnapshotManager.self) private var snapshotManager
    @State private var selection = "overview"

    var body: some View {
        if let snapshot = snapshotManager.snapshot {
            TabView(selection: $selection) {
                SylOverviewTab(snapshot: snapshot)
                    .containerBackground(Color.accentColor.gradient, for: .tabView)
                    .tag("overview")
                ForEach(snapshot.categories) { category in
                    CategoryTabView(category: category, snapshot: snapshot)
                        .containerBackground(category.color.color.gradient, for: .tabView)
                        .tag(category.id)
                }
                WatchSpendingChart(snapshot: snapshot)
                    .tag("trends")
            }
            .tabViewStyle(.verticalPage)
            .onOpenURL { _ in selection = "overview" }
            #if DEBUG
            .onAppear {
                #if targetEnvironment(simulator)
                if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-watch-page"),
                   ProcessInfo.processInfo.arguments.indices.contains(index + 1) {
                    selection = ProcessInfo.processInfo.arguments[index + 1]
                }
                #endif
            }
            #endif
        } else {
            ContentUnavailableView("Not synced yet", systemImage: "iphone.and.arrow.right.outward",
                                   description: Text("Open Syl on your iPhone to send your spending summary."))
        }
    }
}

struct SylOverviewTab: View {
    let snapshot: WatchSnapshot
    @ScaledMetric(relativeTo: .body) private var textScale = 1.0

    var body: some View {
        GeometryReader { geometry in
            let layout = WatchSummaryLayout(size: geometry.size, textScale: textScale)
            VStack(alignment: .leading, spacing: layout.spacing) {
                Text(snapshot.monthLabel)
                    .foregroundStyle(.secondary)
                Text(snapshot.totalSpent, format: .currency(code: snapshot.currencyCode))
                    .font(layout.amountFont)
                    .monospacedDigit().minimumScaleFactor(0.65).lineLimit(1)
                    .frame(maxHeight: .infinity, alignment: .leading)
                    .privacySensitive()
                if snapshot.monthlyBudget > 0 {
                    Text("Spent of \(snapshot.monthlyBudget.formatted(.currency(code: snapshot.currencyCode)))")
                        .foregroundStyle(.secondary)
                        .privacySensitive()
                    WatchBudgetBar(total: snapshot.totalSpent, budget: snapshot.monthlyBudget, categories: snapshot.categories)
                        .privacySensitive()
                } else {
                    Text("Total spent").foregroundStyle(.secondary)
                }
                
                WatchBudgetRemaining(spent: snapshot.totalSpent, budget: snapshot.monthlyBudget, currencyCode: snapshot.currencyCode)
                    .fontWeight(.semibold)
                    .privacySensitive()
                
                WatchSnapshotFreshness(snapshot: snapshot)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(layout.supportingFont)
            .lineLimit(1).minimumScaleFactor(0.65)
            .padding(.vertical, layout.spacing)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .scenePadding(.horizontal)
        .padding(.trailing, 8)
    }
}

struct CategoryTabView: View {
    let category: WatchCategorySnapshot
    let snapshot: WatchSnapshot
    private var isSavings: Bool { category.categoryName == "Savings" }
    @ScaledMetric(relativeTo: .body) private var textScale = 1.0

    var body: some View {
        GeometryReader { geometry in
            let layout = WatchSummaryLayout(size: geometry.size, textScale: textScale)
            VStack(alignment: .leading, spacing: layout.spacing) {
                HStack(spacing: 6) {
                    Circle().fill(category.color.color).frame(width: 7, height: 7)
                    Text(category.categoryName).fontWeight(.semibold)
                }
                Text(category.totalSpent, format: .currency(code: snapshot.currencyCode))
                    .font(layout.amountFont)
                    .monospacedDigit().minimumScaleFactor(0.65).lineLimit(1)
                    .frame(maxHeight: .infinity, alignment: .leading)
                    .privacySensitive()
                if category.monthlyBudget > 0 {
                    Text("\(isSavings ? "Saved of" : "Spent of") \(category.monthlyBudget.formatted(.currency(code: snapshot.currencyCode)))")
                        .foregroundStyle(.secondary)
                        .privacySensitive()
                    WatchBudgetBar(total: category.totalSpent, budget: category.monthlyBudget, categories: [category])
                        .privacySensitive()
                } else {
                    Text(isSavings ? "set aside" : "spent").foregroundStyle(.secondary)
                }
                WatchBudgetRemaining(spent: category.totalSpent, budget: category.monthlyBudget,
                                     currencyCode: snapshot.currencyCode, isSavings: isSavings)
                    .fontWeight(.semibold)
                    .privacySensitive()
                WatchSnapshotFreshness(snapshot: snapshot)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(layout.supportingFont)
            .lineLimit(1).minimumScaleFactor(0.65)
            .padding(.vertical, layout.spacing)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .scenePadding(.horizontal)
        .padding(.trailing, 8)
    }
}

private struct WatchSummaryLayout {
    let size: CGSize
    let textScale: Double

    var spacing: CGFloat { min(12, max(4, size.height * 0.035)) }
    var amountFont: Font {
        .system(size: min(52, max(32, size.width * 0.25)) * textScale, weight: .semibold, design: .rounded)
    }
    var supportingFont: Font {
        .system(size: min(16, max(13, size.width * 0.08)) * textScale)
    }
}

struct WatchSnapshotFreshness: View {
    let snapshot: WatchSnapshot

    var body: some View {
        TimelineView(.periodic(from: .now, by: 3600)) { context in
            if snapshot.isStale(at: context.date) {
                Text("Open iPhone app to refresh")
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.65)
            }
        }
    }
}

#Preview("Empty") {
    SageDashboardView().environment(SnapshotManager())
}

#Preview("Full") {
    let manager = SnapshotManager()
    manager.updateSnapshot(to: .preview)
    return SageDashboardView().environment(manager)
}
