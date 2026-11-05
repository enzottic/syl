//
//  ExpenseSpotlightIndexer.swift
//  SageKit
//

import AppIntents
import CoreSpotlight
import Foundation
import SwiftData

/// Reads SwiftData persistent history instead of hooking save sites, so CloudKit imports,
/// bulk deletes, and other processes' writes are caught. Tombstones carry no expense UUIDs,
/// so deletions are found by comparing a ledger of indexed IDs with the store.
@MainActor
public final class ExpenseSpotlightIndexer {
    public static let shared: ExpenseSpotlightIndexer? = {
        guard case let .success(container) = SageModelContainer.shared,
              let stateURL = defaultStateURL else { return nil }
        return ExpenseSpotlightIndexer(
            modelContainer: container,
            index: CoreSpotlightEntityIndex(),
            stateURL: stateURL
        )
    }()

    nonisolated static let indexVersion = ExpenseIndexState.currentVersion
    static let batchSize = 200

    private let planner: ExpenseIndexPlanner
    private let index: any SpotlightEntityIndexing
    private let stateURL: URL
    private var pending: Task<Void, Never>?
    private var saveObserver: (any NSObjectProtocol)?

    init(modelContainer: ModelContainer, index: any SpotlightEntityIndexing, stateURL: URL) {
        self.planner = ExpenseIndexPlanner(modelContainer: modelContainer)
        self.index = index
        self.stateURL = stateURL
    }

    public func start() {
        guard saveObserver == nil else { return }
        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleUpdate(after: .seconds(1)) }
        }
        scheduleUpdate()
    }

    /// Does nothing before `start()`, so previews and tests never touch the index.
    public func scheduleUpdate(after delay: Duration = .zero) {
        guard saveObserver != nil else { return }
        let previous = pending
        previous?.cancel()
        pending = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            await previous?.value
            guard !Task.isCancelled else { return }
            do {
                try await self?.update()
            } catch {
                // Indexing is best-effort; the next save or activation retries from the same token.
            }
        }
    }

    func update() async throws {
        try await apply(planner.updatePlan(from: loadState()))
    }

    public func rebuild() async throws {
        try await apply(planner.rebuildPlan())
    }

    public func reindexExpenses(withIDs ids: [UUID]) async throws {
        try await apply(planner.reindexPlan(for: ids, state: loadState()))
    }

    private func apply(_ plan: ExpenseIndexPlan) async throws {
        if plan.deletesAllExpenses {
            try await index.deleteAllExpenses()
        }
        if !plan.expenseIDsToDelete.isEmpty {
            try await index.deleteExpenses(withIDs: plan.expenseIDsToDelete)
        }
        let expenses = plan.expensesToIndex
        for start in stride(from: 0, to: expenses.count, by: Self.batchSize) {
            try await index.indexExpenses(Array(expenses[start..<min(start + Self.batchSize, expenses.count)]))
        }
        if let tags = plan.tags {
            try await index.deleteAllTags()
            try await index.indexTags(tags)
        }
        if let state = plan.state {
            try saveState(state)
        }
    }

    /// Not in the app group: each app bundle has its own Spotlight index.
    private static var defaultStateURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "SpotlightIndexState.json")
    }

    func loadState() -> ExpenseIndexState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(ExpenseIndexState.self, from: data)
    }

    private func saveState(_ state: ExpenseIndexState) throws {
        try JSONEncoder().encode(state).write(to: stateURL, options: [.atomic, .completeFileProtection])
    }
}

struct ExpenseIndexState: Codable, Equatable, Sendable {
    /// Bump to rebuild every entry once after an entity's indexed shape changes.
    static let currentVersion = 1

    var version: Int
    var token: DefaultHistoryToken?
    var expenseIDs: Set<UUID>
}

struct ExpenseIndexPlan: Sendable {
    var deletesAllExpenses = false
    var expenseIDsToDelete: [UUID] = []
    var expensesToIndex: [ExpenseEntity] = []
    /// Nil leaves the indexed tags alone.
    var tags: [ExpenseTagEntity]?
    var state: ExpenseIndexState?
}

/// A fresh context per pass, so no pass works from objects cached by an earlier one.
actor ExpenseIndexPlanner {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func updatePlan(from saved: ExpenseIndexState?) throws -> ExpenseIndexPlan {
        guard var state = saved, state.version == ExpenseIndexState.currentVersion else {
            return try rebuildPlan()
        }

        let context = ModelContext(modelContainer)
        let transactions: [DefaultHistoryTransaction]
        do {
            transactions = try context.fetchHistory(Self.history(after: state.token))
        } catch {
            return try rebuildPlan()
        }
        guard let latestToken = transactions.last?.token else { return ExpenseIndexPlan() }

        var plan = ExpenseIndexPlan()
        let changes = HistoryScan(transactions)
        if changes.tagsChanged {
            plan.tags = try context.fetch(FetchDescriptor<ExpenseTag>()).map(\.entity)
        }

        if changes.expensesDeleted {
            let current = try Set(context.fetch(Self.allExpenseIDs).map(\.id))
            plan.expenseIDsToDelete = Array(state.expenseIDs.subtracting(current))
            state.expenseIDs.formIntersection(current)
        }

        var expenses = try fetchExpenses(withPersistentIDs: changes.changedExpenses, in: context)
        if !changes.renamedTags.isEmpty {
            expenses += try fetchExpenses(taggedWith: changes.renamedTags, in: context)
        }
        plan.expensesToIndex = Self.uniqueEntities(expenses)
        state.expenseIDs.formUnion(plan.expensesToIndex.map(\.id))

        state.token = latestToken
        plan.state = state
        return plan
    }

    func rebuildPlan() throws -> ExpenseIndexPlan {
        let context = ModelContext(modelContainer)
        // Read the token before the data, so changes made during the rebuild are replayed.
        var latest = HistoryDescriptor<DefaultHistoryTransaction>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        latest.fetchLimit = 1
        let token = try? context.fetchHistory(latest).first?.token

        let expenses = Self.uniqueEntities(try context.fetch(FetchDescriptor<Expense>()))
        return ExpenseIndexPlan(
            deletesAllExpenses: true,
            expensesToIndex: expenses,
            tags: try context.fetch(FetchDescriptor<ExpenseTag>()).map(\.entity),
            state: ExpenseIndexState(
                version: ExpenseIndexState.currentVersion,
                token: token,
                expenseIDs: Set(expenses.map(\.id))
            )
        )
    }

    func reindexPlan(for ids: [UUID], state saved: ExpenseIndexState?) throws -> ExpenseIndexPlan {
        let context = ModelContext(modelContainer)
        let expenses = Self.uniqueEntities(try context.fetch(FetchDescriptor<Expense>(
            predicate: #Predicate { ids.contains($0.id) }
        )))
        let missing = Set(ids).subtracting(expenses.map(\.id))
        var plan = ExpenseIndexPlan(expenseIDsToDelete: Array(missing), expensesToIndex: expenses)
        if var state = saved {
            state.expenseIDs.subtract(missing)
            state.expenseIDs.formUnion(expenses.map(\.id))
            plan.state = state
        }
        return plan
    }

    private func fetchExpenses(
        withPersistentIDs ids: Set<PersistentIdentifier>,
        in context: ModelContext
    ) throws -> [Expense] {
        guard !ids.isEmpty else { return [] }
        return try context.fetch(FetchDescriptor<Expense>(
            predicate: #Predicate { ids.contains($0.persistentModelID) }
        ))
    }

    private func fetchExpenses(
        taggedWith tagIDs: Set<PersistentIdentifier>,
        in context: ModelContext
    ) throws -> [Expense] {
        let tags = try context.fetch(FetchDescriptor<ExpenseTag>(
            predicate: #Predicate { tagIDs.contains($0.persistentModelID) }
        ))
        return tags.flatMap { ($0.taggedExpenses ?? []) + ($0.expenses ?? []) }
    }

    private static func uniqueEntities(_ expenses: [Expense]) -> [ExpenseEntity] {
        var seen = Set<UUID>()
        return expenses.filter { seen.insert($0.id).inserted }.map(\.entity)
    }

    private static func history(after token: DefaultHistoryToken?) -> HistoryDescriptor<DefaultHistoryTransaction> {
        guard let token else {
            return HistoryDescriptor(sortBy: [SortDescriptor(\.timestamp)])
        }
        return HistoryDescriptor(
            predicate: #Predicate { $0.token > token },
            sortBy: [SortDescriptor(\.timestamp)]
        )
    }

    private static var allExpenseIDs: FetchDescriptor<Expense> {
        var descriptor = FetchDescriptor<Expense>()
        descriptor.propertiesToFetch = [\.id]
        return descriptor
    }
}

struct HistoryScan {
    private(set) var changedExpenses = Set<PersistentIdentifier>()
    private(set) var expensesDeleted = false
    private(set) var tagsChanged = false
    private(set) var renamedTags = Set<PersistentIdentifier>()

    static let expenseEntity = Schema.entityName(for: Expense.self)
    static let tagEntity = Schema.entityName(for: ExpenseTag.self)
    private static let displayedTagAttributes: Set<AnyKeyPath> = [
        \ExpenseTag.name, \ExpenseTag.emoji, \ExpenseTag.symbolName,
    ]

    init(_ transactions: [DefaultHistoryTransaction]) {
        for change in transactions.flatMap(\.changes) {
            let id = change.changedPersistentIdentifier
            switch (id.entityName, change) {
            case (Self.expenseEntity, .insert), (Self.expenseEntity, .update):
                changedExpenses.insert(id)
            case (Self.expenseEntity, .delete):
                expensesDeleted = true
                changedExpenses.remove(id)
            case (Self.tagEntity, .insert), (Self.tagEntity, .delete):
                tagsChanged = true
            case let (Self.tagEntity, .update(update)):
                // Tagging an expense also updates the tag's inverse relationship, which isn't indexed.
                guard let tagUpdate = update as? any HistoryUpdate<ExpenseTag>,
                      tagUpdate.updatedAttributes.contains(where: { Self.displayedTagAttributes.contains($0) })
                else { continue }
                tagsChanged = true
                renamedTags.insert(id)
            default:
                continue
            }
        }
    }
}

@MainActor
protocol SpotlightEntityIndexing {
    func indexExpenses(_ expenses: [ExpenseEntity]) async throws
    func deleteExpenses(withIDs ids: [UUID]) async throws
    func deleteAllExpenses() async throws
    func indexTags(_ tags: [ExpenseTagEntity]) async throws
    func deleteAllTags() async throws
}

@MainActor
struct CoreSpotlightEntityIndex: SpotlightEntityIndexing {
    private let index = CSSearchableIndex(name: "SageEntities", protectionClass: .complete)

    func indexExpenses(_ expenses: [ExpenseEntity]) async throws {
        try await index.indexAppEntities(expenses)
    }

    func deleteExpenses(withIDs ids: [UUID]) async throws {
        try await index.deleteAppEntities(identifiedBy: ids, ofType: ExpenseEntity.self)
    }

    func deleteAllExpenses() async throws {
        try await index.deleteAppEntities(ofType: ExpenseEntity.self)
    }

    func indexTags(_ tags: [ExpenseTagEntity]) async throws {
        try await index.indexAppEntities(tags)
    }

    func deleteAllTags() async throws {
        try await index.deleteAppEntities(ofType: ExpenseTagEntity.self)
    }
}
