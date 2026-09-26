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
    public static let shared: ExpenseStore? = {
        guard case let .success(container) = SageModelContainer.shared else { return nil }
        return ExpenseStore(modelContainer: container)
    }()
    
    let modelContainer: ModelContainer
    var context: ModelContext
    /// Where income and allocations are read from; tests pass an isolated store.
    let preferences: UserDefaults

    public convenience init(modelContainer: ModelContainer) {
        self.init(modelContainer: modelContainer, preferences: SagePreferences.defaults)
    }

    init(modelContainer: ModelContainer, preferences: UserDefaults) {
        self.modelContainer = modelContainer
        self.context = modelContainer.mainContext
        self.preferences = preferences
    }

    // MARK: - Create

    public func addExpense(_ expense: Expense) {
        context.insert(expense)
    }

    func addExpenseAndSave(
        _ expense: Expense,
        tagID: UUID?,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> ExpenseEntity {
        // Shortcut writes must not save or roll back pending edits in the app's context.
        let writeContext = ModelContext(modelContainer)
        writeContext.autosaveEnabled = false
        do {
            if let tagID {
                let descriptor = FetchDescriptor<ExpenseTag>(
                    predicate: #Predicate { $0.id == tagID }
                )
                if let tag = try writeContext.fetch(descriptor).first {
                    expense.tags = [tag]
                }
            }
            writeContext.insert(expense)
            try save(writeContext)
            return expense.entity
        } catch {
            writeContext.rollback()
            throw error
        }
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

    // MARK: - Save

    public func save() throws {
        try context.save()
    }
}
