import Foundation
import WidgetKit
import SageKit

struct CategorySpotlightProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CategorySpotlightEntry { .preview(category: .needs) }

    func snapshot(for configuration: CategorySpotlightAppIntent, in context: Context) async -> CategorySpotlightEntry {
        context.isPreview ? .preview(category: configuration.category) : await loadEntry(category: configuration.category)
    }

    func timeline(for configuration: CategorySpotlightAppIntent, in context: Context) async -> Timeline<CategorySpotlightEntry> {
        let entry = await loadEntry(category: configuration.category)
        return Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(15 * 60)))
    }

    @MainActor
    private func loadEntry(category: ExpenseCategory) -> CategorySpotlightEntry {
        let date = Date.now
        guard let store = ExpenseStore.shared else {
            return CategorySpotlightEntry(date: date, category: category, spent: 0, budget: 0, isUnavailable: true)
        }
        do {
            return CategorySpotlightEntry(date: date, category: category,
                                          spent: try store.monthlyTotal(category: category, month: date),
                                          budget: store.budget(for: category))
        } catch {
            return CategorySpotlightEntry(date: date, category: category, spent: 0, budget: 0, isUnavailable: true)
        }
    }
}
