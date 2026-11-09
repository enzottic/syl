import Foundation
import SwiftData
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
            completion(Timeline(entries: [entry], policy: WidgetRefreshPolicy.standard(after: entry.date)))
        }
    }

    @MainActor
    private func loadEntry() -> RecentExpensesEntry {
        let date = Date.now
        guard let store = ExpenseStore.shared else {
            return RecentExpensesEntry(date: date, expenses: [], isUnavailable: true)
        }
        do {
            let colorSource = ExpenseColorSource.load()
            let expenses = try store.fetchRecentExpenses(limit: 3).map { expense in
                let tag = expense.tags?.first { !$0.isDeleted }
                return ExpenseSnapshot(id: expense.id, name: expense.name, amount: expense.amount,
                                       category: expense.category, date: expense.date,
                                       glyph: tag?.glyph, tagColor: colorSource == .tag ? tag?.color : nil)
            }
            let today = Calendar.current.dateInterval(of: .day, for: date)
            let todayTotal = try today.map { try store.fetchExpenses(from: $0.start, to: $0.end).total } ?? 0
            return RecentExpensesEntry(date: date, expenses: expenses, todayTotal: todayTotal)
        } catch {
            return RecentExpensesEntry(date: date, expenses: [], isUnavailable: true)
        }
    }
}
