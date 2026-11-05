//
//  ExpenseTagEntity.swift
//  FinanceTracker
//

import Foundation
import AppIntents
import CoreSpotlight
import SwiftData

public struct ExpenseTagEntity: IndexedEntity {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Tag"
    public static var defaultQuery = ExpenseTagEntityQuery()

    /// Enforced by the system from iOS 27.3.
    public static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    public let id: UUID
    @Property(title: "Name") var name: String
    @Property(title: "Emoji") var emoji: String
    let symbolName: String?

    public var displayRepresentation: DisplayRepresentation {
        // Titles are plain strings, so an icon-marked tag carries its symbol in the image slot
        // and drops the emoji from the title rather than showing both marks.
        if let symbolName {
            return DisplayRepresentation(title: "\(name)", image: .init(systemName: symbolName))
        }
        return DisplayRepresentation(title: "\(emoji) \(name)")
    }

    var glyph: TagGlyph {
        symbolName.map(TagGlyph.symbol) ?? .emoji(emoji)
    }

    /// The tag as plain text. A symbol can't be written into text, so a symbol tag is just its name.
    var plainLabel: String {
        symbolName == nil ? "\(emoji) \(name)" : name
    }

    init(id: UUID, name: String, emoji: String, symbolName: String?) {
        // Plain stored properties first: assigning a @Property goes through `self`.
        self.id = id
        self.symbolName = symbolName
        self.name = name
        self.emoji = emoji
    }
}

public extension ExpenseTag {
    var entity: ExpenseTagEntity {
        ExpenseTagEntity(id: self.id, name: self.name, emoji: self.emoji, symbolName: self.glyph.symbolValue)
    }
}

@MainActor
public struct ExpenseTagEntityQuery: EntityStringQuery {
    @Dependency
    var expenseStore: ExpenseStore

    public func entities(for identifiers: [UUID]) async throws -> [ExpenseTagEntity] {
        let descriptor = FetchDescriptor<ExpenseTag>(
            predicate: #Predicate { identifiers.contains($0.id) }
        )
        try expenseStore.requireAvailable()
        return try expenseStore.context.fetch(descriptor).map(\.entity)
    }

    public func entities(matching string: String) async throws -> [ExpenseTagEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let descriptor = FetchDescriptor<ExpenseTag>(
            predicate: #Predicate { $0.name.localizedStandardContains(query) || $0.emoji == query },
            sortBy: [SortDescriptor(\.name)]
        )
        try expenseStore.requireAvailable()
        return try expenseStore.context.fetch(descriptor).map(\.entity)
    }

    public func suggestedEntities() async throws -> [ExpenseTagEntity] {
        try expenseStore.requireAvailable()
        let all = try expenseStore.context.fetch(FetchDescriptor<ExpenseTag>(sortBy: [SortDescriptor(\.name)]))
        return all.map(\.entity)
    }

    public nonisolated init() { }
}
