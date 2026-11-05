//
//  ExpenseEntity.swift
//  FinanceTracker
//

import Foundation
import AppIntents
import CoreSpotlight
import CoreTransferable
import SwiftData

public struct ExpenseEntity: IndexedEntity {
    public static let defaultQuery = ExpenseEntityQuery()

    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Expense"

    /// Enforced by the system from iOS 27.3.
    public static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    // Property descriptions need the whole entity to be iOS 27.3+, so they wait on the deployment target.
    public let id: UUID
    @Property(title: "Name") var name: String
    @Property(title: "Amount") var amount: Double
    @Property(title: "Category") var category: ExpenseCategory
    @Property(title: "Date") var date: Date
    @Property(title: "Tags") var tags: [ExpenseTagEntity]
    @Property(title: "Note") var note: String
    @Property(title: "Recurring") var isRecurring: Bool

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(subtitle)"
        )
    }

    private var subtitle: String {
        let parts = [amount.currencyString, date.formatted(date: .abbreviated, time: .omitted), category.rawValue]
            + (tags.isEmpty ? [] : [tags.map(\.plainLabel).joined(separator: ", ")])
        return parts.joined(separator: " · ")
    }

    public var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.contentDescription = [subtitle, note]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        attributes.keywords = tags.map(\.name) + [category.rawValue]
        attributes.contentCreationDate = date
        return attributes
    }

    public init(
        id: UUID,
        name: String,
        amount: Double,
        category: ExpenseCategory,
        date: Date,
        tags: [ExpenseTag],
        note: String = "",
        isRecurring: Bool = false
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.category = category
        self.date = date
        self.tags = tags.map(\.entity)
        self.note = note
        self.isRecurring = isRecurring
    }

    @MainActor
    public struct ExpenseEntityQuery: EnumerableEntityQuery, EntityStringQuery {

        @Dependency
        var expenseStore: ExpenseStore

        public func allEntities() async throws -> [ExpenseEntity] {
            try expenseStore.fetchExpenses().map(\.entity)
        }

        public func entities(matching string: String) async throws -> [ExpenseEntity] {
            let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return [] }
            let descriptor = ExpenseFetchDescriptors.search(query, visibleLimit: Self.matchLimit)
            try expenseStore.requireAvailable()
            return try expenseStore.context.fetch(descriptor)
                .prefix(Self.matchLimit)
                .map(\.entity)
        }

        public func entities(for identifiers: [ExpenseEntity.ID]) async throws -> [ExpenseEntity] {
            try expenseStore.fetchExpenses(with: identifiers).map(\.entity)
        }

        public func suggestedEntities() async throws -> [ExpenseEntity] {
            try expenseStore.fetchRecentExpenses(limit: 5).map(\.entity)
        }

        static let matchLimit = 50

        public nonisolated init () { }
    }
}

extension ExpenseEntity.ExpenseEntityQuery: IndexedEntityQuery {
    public func reindexEntities(
        for identifiers: [ExpenseEntity.ID],
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        try await ExpenseSpotlightIndexer.shared?.reindexExpenses(withIDs: identifiers)
    }

    public func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await ExpenseSpotlightIndexer.shared?.rebuild()
    }
}

extension ExpenseEntity: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.shareText)
    }

    var shareText: String {
        var parts = [name, amount.currencyString, category.rawValue, date.formatted(date: .abbreviated, time: .omitted)]
        if !tags.isEmpty {
            parts.append(tags.map(\.plainLabel).joined(separator: ", "))
        }
        let line = parts.joined(separator: " · ")
        return note.isEmpty ? line : "\(line)\n\(note)"
    }
}

extension Expense {
    var entity: ExpenseEntity {
        ExpenseEntity(
            id: self.id,
            name: self.name,
            amount: self.amount,
            category: self.category,
            date: self.date,
            tags: self.tags ?? [],
            note: self.note,
            isRecurring: self.recurringExpenseId != nil
        )
    }
}
