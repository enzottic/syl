//
//  ExpenseEntity.swift
//  FinanceTracker
//

import Foundation
import AppIntents
import CoreSpotlight
import SwiftData

public struct ExpenseEntity: IndexedEntity {
    // MARK: Static

    public static let defaultQuery = ExpenseEntityQuery()

    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Expense"

    /// Spending is personal financial information, so Siri and Shortcuts must authenticate
    /// before presenting an expense. The system enforces this requirement from iOS 27.3.
    public static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    // MARK: Properties

    // These titles are the vocabulary Siri uses to match requests to expense properties.
    // Descriptions, per-property authentication, and internal visibility require the whole
    // entity to be iOS 27.3+, which waits on raising the deployment target.
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
        guard !tags.isEmpty else { return "\(amount.currencyString) · \(category)" }
        let tagsText = tags.map { "\($0.emoji) \($0.name)" }.joined(separator: ", ")
        return "\(amount.currencyString) · \(category) · \(tagsText)"
    }

    /// Spotlight attributes beyond the display representation, so semantic search and Siri
    /// can match an expense by its note, tags, category, and when it happened.
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

        /// The system uses this only when an expense is missing from the Spotlight index.
        public func allEntities() async throws -> [ExpenseEntity] {
            try expenseStore.fetchExpenses().map(\.entity)
        }

        /// Matches names, notes, and tag names, newest first, like in-app search.
        public func entities(matching string: String) async throws -> [ExpenseEntity] {
            let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return [] }
            let descriptor = ExpenseFetchDescriptors.search(query, visibleLimit: Self.matchLimit)
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

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
extension ExpenseEntity.ExpenseEntityQuery: IndexedEntityQuery {
    // The system calls these when it needs Syl to rebuild index entries, such as after
    // Spotlight loses its index. Syl tracks its own changes, so both rebuild from the store.
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
