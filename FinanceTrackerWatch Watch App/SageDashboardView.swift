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

    var body: some View {
        WatchBudgetPage(snapshot: snapshot, amount: snapshot.totalSpent,
                        budget: snapshot.monthlyBudget, categories: snapshot.categories) {
            Text(snapshot.monthStart.formatted(Date.FormatStyle(calendar: snapshot.reportingCalendar,
                                                                timeZone: snapshot.reportingCalendar.timeZone).month(.wide)))
        }
    }
}

struct CategoryTabView: View {
    let category: WatchCategorySnapshot
    let snapshot: WatchSnapshot

    var body: some View {
        WatchBudgetPage(snapshot: snapshot, amount: category.totalSpent, budget: category.monthlyBudget,
                        categories: [category], isSavings: category.categoryName == "Savings") {
            HStack(spacing: 7) {
                Circle().fill(category.color.color).frame(width: 9, height: 9)
                Text(category.categoryName)
            }
        }
    }
}

private struct WatchBudgetPage<Header: View>: View {
    let snapshot: WatchSnapshot
    let amount: Double
    let budget: Double
    let categories: [WatchCategorySnapshot]
    var isSavings = false
    @ViewBuilder let header: Header
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 34.0

    private var currency: FloatingPointFormatStyle<Double>.Currency { .currency(code: snapshot.currencyCode) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 3600)) { context in
            let pace = isSavings ? nil : snapshot.monthProgress(at: context.date)
            VStack(alignment: .leading, spacing: 0) {
                header.font(.watchPageTitle)
                Spacer(minLength: 4)
                Text(isSavings ? "Saved" : "Spent")
                    .font(.footnote).foregroundStyle(.secondary)
                Text(amount, format: currency)
                    .font(.system(size: amountSize, weight: .semibold, design: .rounded))
                    .monospacedDigit().minimumScaleFactor(0.5)
                    .privacySensitive()
                if budget > 0 {
                    Text(isSavings ? "of \(budget.formatted(currency.precision(.fractionLength(0)))) target"
                                   : "of \(budget.formatted(currency.precision(.fractionLength(0))))")
                        .font(.footnote).foregroundStyle(.secondary)
                        .privacySensitive()
                    WatchBudgetBar(total: amount, budget: budget, categories: categories, pace: pace)
                        .padding(.top, 10)
                        .privacySensitive()
                }
                HStack(alignment: .firstTextBaseline) {
                    WatchBudgetRemaining(spent: amount, budget: budget,
                                         currencyCode: snapshot.currencyCode, isSavings: isSavings)
                        .font(.callout.weight(.semibold))
                    Spacer(minLength: 4)
                    progressNote(pace: pace).font(.footnote)
                }
                .padding(.top, 8)
                .privacySensitive()
                Spacer(minLength: 4)
            }
            .lineLimit(1).minimumScaleFactor(0.65)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .scenePadding(.horizontal)
        .padding(.leading, 4)
        .padding(.trailing, 10)
    }

    @ViewBuilder
    private func progressNote(pace: Double?) -> some View {
        if budget > 0 {
            let used = amount / budget
            if let pace, used <= 1, used > pace + 0.02 {
                Text("Ahead of pace").foregroundStyle(.orange)
            } else {
                Text(max(used, 0), format: .percent.precision(.fractionLength(0)))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension Font {
    static let watchPageTitle = Font.custom("MomoTrustDisplay-Regular", size: 22, relativeTo: .title3)
}

#Preview("Empty") {
    SageDashboardView().environment(SnapshotManager())
}

#Preview("Full") {
    let manager = SnapshotManager()
    manager.updateSnapshot(to: .preview)
    return SageDashboardView().environment(manager)
}
