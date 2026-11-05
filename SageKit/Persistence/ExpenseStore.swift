//
//  ExpenseStore.swift
//  FinanceTracker
//
//  Created by Enzo on 10/5/25.
//

import Foundation
import SwiftData

@MainActor @Observable
final public class ExpenseStore {
    /// Reuse the process-local container, with a fresh context for each widget timeline.
    public static var shared: ExpenseStore? {
        guard case let .success(container) = SageModelContainer.shared else { return nil }
        return ExpenseStore(
            modelContainer: container,
            preferences: SagePreferences.defaults,
            context: ModelContext(container)
        )
    }

    let modelContainer: ModelContainer
    var context: ModelContext
    /// Where income and allocations are read from; tests pass an isolated store.
    let preferences: UserDefaults

    public convenience init(modelContainer: ModelContainer) {
        self.init(modelContainer: modelContainer, preferences: SagePreferences.defaults)
    }

    init(modelContainer: ModelContainer, preferences: UserDefaults, context: ModelContext? = nil) {
        self.modelContainer = modelContainer
        self.context = context ?? modelContainer.mainContext
        self.preferences = preferences
    }

    // MARK: - Create

    public func addExpense(_ expense: Expense) {
        context.insert(expense)
    }

    func addExpenseAndSave(
        _ expense: Expense,
        tagIDs: [UUID],
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> ExpenseEntity {
        try isolatedWrite(save: save) { writeContext in
            expense.tags = try Self.tags(withIDs: tagIDs, in: writeContext)
            writeContext.insert(expense)
            return expense.entity
        }
    }

    // MARK: - Update

    /// Changes one expense in an isolated context and returns its updated entity.
    /// `change` receives the expense and the write context, for looking up related models.
    func updateExpenseAndSave(
        id: UUID,
        save: (ModelContext) throws -> Void = { try $0.save() },
        change: (Expense, ModelContext) throws -> Void
    ) throws -> ExpenseEntity {
        try isolatedWrite(save: save) { writeContext in
            let expense = try Self.expense(withID: id, in: writeContext)
            try change(expense, writeContext)
            return expense.entity
        }
    }

    /// Resolves tag IDs to tags in `context`, skipping duplicates and missing tags.
    /// The relationship these are assigned to is unordered, so order isn't kept.
    static func tags(withIDs ids: [UUID], in context: ModelContext) throws -> [ExpenseTag] {
        guard !ids.isEmpty else { return [] }
        let tags = try context.fetch(FetchDescriptor<ExpenseTag>(
            predicate: #Predicate { ids.contains($0.id) }
        ))
        var seen = Set<UUID>()
        return ids.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return tags.first { $0.id == id }
        }
    }

    // MARK: - Isolated writes

    public enum WriteError: LocalizedError, Equatable {
        case expenseNotFound

        public var errorDescription: String? {
            switch self {
            case .expenseNotFound: "That expense no longer exists in Syl."
            }
        }
    }

    /// Runs a write in its own context. Siri and Shortcuts writes must not save or roll back
    /// pending edits in the app's context. The save closure is a test seam.
    private func isolatedWrite<Result>(
        save: (ModelContext) throws -> Void,
        _ body: (ModelContext) throws -> Result
    ) throws -> Result {
        let writeContext = ModelContext(modelContainer)
        writeContext.autosaveEnabled = false
        do {
            let result = try body(writeContext)
            try save(writeContext)
            return result
        } catch {
            writeContext.rollback()
            throw error
        }
    }

    private static func expense(withID id: UUID, in context: ModelContext) throws -> Expense {
        let matches = try context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.id == id }))
        guard let expense = matches.first else { throw WriteError.expenseNotFound }
        return expense
    }

    // MARK: - Category inference

    /// The category Syl would expect for a new expense: the newest expense with the same name,
    /// otherwise the category most used with `tagID`. Nil when there's nothing to go on.
    public func inferredCategory(forName name: String, tagID: UUID?) throws -> ExpenseCategory? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            var descriptor = FetchDescriptor<Expense>(
                predicate: #Predicate { $0.name.localizedStandardContains(trimmed) },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            descriptor.fetchLimit = 50
            if let match = try context.fetch(descriptor).first(where: {
                $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
                return match.category
            }
        }

        guard let tagID,
              let tag = try context.fetch(FetchDescriptor<ExpenseTag>(predicate: #Predicate { $0.id == tagID })).first
        else { return nil }
        let counts = Dictionary(grouping: tag.taggedExpenses ?? [], by: \.category).mapValues(\.count)
        // Ties go to the earlier category in Needs, Wants, Savings order, so the result is stable.
        return ExpenseCategory.allCases
            .filter { counts[$0] != nil }
            .max { counts[$0]! < counts[$1]! }
    }

    // MARK: - Read

    /// Returns all expenses for a given month, if provided. If not, fetches all expenses
    public func fetchExpenses(for month: Date? = nil) throws -> [Expense] {
        let descriptor: FetchDescriptor<Expense>
        if let month {
            descriptor = ExpenseFetchDescriptors.month(month)
        } else {
            descriptor = FetchDescriptor<Expense>(sortBy: [SortDescriptor(\Expense.date, order: .reverse)])
        }
        
        return try context.fetch(descriptor)
    }

    /// Returns all expenses that match the identifiers
    public func fetchExpenses(with ids: [UUID]) throws -> [Expense] {
        let descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate { ids.contains($0.id) }
        )
        return try context.fetch(descriptor)
    }

    public func fetchRecentExpenses(limit: Int = 10) throws -> [Expense] {
        var descriptor = FetchDescriptor<Expense>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        
        return try context.fetch(descriptor)
    }

    public func fetchExpenses(from startDate: Date, to endDate: Date) -> [Expense] {
        let fetchDescriptor = ExpenseFetchDescriptors.range(start: startDate, end: endDate)
        return (try? context.fetch(fetchDescriptor)) ?? []
    }

    public func monthlyTotal(for month: Date = .now) throws -> Double {
        try fetchExpenses(for: month).total
    }

    public func monthlyTotal(category: ExpenseCategory, month: Date = .now) throws -> Double {
        try fetchExpenses(for: month).filter { $0.category == category }.total
    }

    // MARK: - Budget

    public func budget(for category: ExpenseCategory) -> Double {
        let income = Double(preferences.integer(forKey: "totalMonthlyIncome"))
        switch category {
        case .needs:
            return income * (preferences.object(forKey: "needsPercent") as? Double ?? 0.5)
        case .wants:
            return income * (preferences.object(forKey: "wantsPercent") as? Double ?? 0.3)
        case .savings:
            return income * (preferences.object(forKey: "savingsPercent") as? Double ?? 0.2)
        }
    }

    public func totalBudget() -> Double {
        ExpenseCategory.allCases.map { budget(for: $0) }.reduce(0, +)
    }

    /// How the month's spending compares with a category's budget (or savings target),
    /// or with the total budget when `category` is nil.
    public func budgetStatus(for category: ExpenseCategory?, month: Date = .now) throws -> BudgetStatus {
        guard let category else {
            return BudgetStatus(spent: try monthlyTotal(for: month), budget: totalBudget())
        }
        return BudgetStatus(
            spent: try monthlyTotal(category: category, month: month),
            budget: budget(for: category),
            goal: category.budgetGoal
        )
    }

    public var totalMonthlyIncome: Int {
        preferences.integer(forKey: "totalMonthlyIncome")
    }

    // MARK: - Widget snapshot

    public struct MonthlySnapshot {
        public let totalSpent: Double
        public let wantsSpent: Double
        public let needsSpent: Double
        public let savingsSpent: Double
        public let totalIncome: Int
        public let needsBudget: Double
        public let wantsBudget: Double
        public let savingsBudget: Double
        public let recentExpenses: [ExpenseSnapshot]
    }

    public func monthlySnapshot(for month: Date = .now) throws -> MonthlySnapshot {
        let expenses = try fetchExpenses(for: month)
        let recentExpenses = expenses.prefix(5).map {
            ExpenseSnapshot(id: $0.id, name: $0.name, amount: $0.amount, category: $0.category, date: $0.date)
        }
        return MonthlySnapshot(
            totalSpent: expenses.total,
            wantsSpent: expenses.wantsUsed,
            needsSpent: expenses.needsUsed,
            savingsSpent: expenses.savingsUsed,
            totalIncome: totalMonthlyIncome,
            needsBudget: budget(for: .needs),
            wantsBudget: budget(for: .wants),
            savingsBudget: budget(for: .savings),
            recentExpenses: recentExpenses
        )
    }

    // MARK: - Delete

    public func deleteExpense(_ expense: Expense) {
        context.delete(expense)
    }

    /// Deletes one expense in an isolated context. A recurring expense's rule is kept, so
    /// future occurrences still arrive; deleting the rule is a separate, in-app decision.
    func deleteExpenseAndSave(id: UUID, save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        try isolatedWrite(save: save) { writeContext in
            writeContext.delete(try Self.expense(withID: id, in: writeContext))
        }
    }

    // MARK: - Save

    public func save() throws {
        try context.save()
    }
}
