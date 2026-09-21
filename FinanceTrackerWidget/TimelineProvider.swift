//
//  TimelineProvider.swift
//  FinanceTracker
//
//  Created by Enzo on 10/7/25.
//
import Foundation
import WidgetKit
import SageKit

// MARK: - Recent Expenses

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

// MARK: - Category Spotlight

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

// MARK: - Monthly Summary

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
