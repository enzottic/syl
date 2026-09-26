import Foundation
import WidgetKit
import SageKit

struct MonthlySummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> MonthlySummaryEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (MonthlySummaryEntry) -> Void) {
        Task { completion(context.isPreview ? .preview : await loadEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MonthlySummaryEntry>) -> Void) {
        Task {
            let entry = await loadEntry()
            completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(15 * 60))))
        }
    }

    @MainActor
    private func loadEntry() -> MonthlySummaryEntry {
        let date = Date.now
        if let store = ExpenseStore.shared, let snapshot = try? store.monthlySnapshot(for: date) {
            return MonthlySummaryEntry(
                date: date, totalSpent: snapshot.totalSpent, totalIncome: snapshot.totalIncome,
                wantsSpent: snapshot.wantsSpent, wantsBudget: snapshot.wantsBudget,
                needsSpent: snapshot.needsSpent, needsBudget: snapshot.needsBudget,
                savingsSpent: snapshot.savingsSpent, savingsBudget: snapshot.savingsBudget,
                recentExpenses: snapshot.recentExpenses
            )
        }
        return MonthlySummaryEntry(date: date, totalSpent: 0, totalIncome: 0,
                                   wantsSpent: 0, wantsBudget: 0, needsSpent: 0, needsBudget: 0,
                                   savingsSpent: 0, savingsBudget: 0, recentExpenses: [], isUnavailable: true)
    }
}
