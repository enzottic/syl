import Foundation
import WidgetKit
import SageKit

struct RecentExpensesProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentExpensesEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (RecentExpensesEntry) -> Void) {
        Task { completion(context.isPreview ? .preview : await loadEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentExpensesEntry>) -> Void) {
        Task {
            let entry = await loadEntry()
            completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(15 * 60))))
        }
    }

    @MainActor
    private func loadEntry() -> RecentExpensesEntry {
        let date = Date.now
        guard let store = ExpenseStore.shared else {
            return RecentExpensesEntry(date: date, expenses: [], isUnavailable: true)
        }
        do {
            let expenses = try store.fetchRecentExpenses(limit: 5).map {
                ExpenseSnapshot(id: $0.id, name: $0.name, amount: $0.amount, category: $0.category, date: $0.date)
            }
            return RecentExpensesEntry(date: date, expenses: expenses)
        } catch {
            return RecentExpensesEntry(date: date, expenses: [], isUnavailable: true)
        }
    }
}
