//
//  ExpenseTagEntity.swift
//  FinanceTracker
//

import Foundation
import AppIntents
import SwiftData

public struct ExpenseTagEntity: AppEntity {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Tag"
    public static var defaultQuery = ExpenseTagEntityQuery()

    public let id: UUID
    let name: String
    let emoji: String
    let symbolName: String?

    public var displayRepresentation: DisplayRepresentation {
        // Titles are plain strings, so an icon-marked tag carries its symbol in the image slot
        // and drops the emoji from the title rather than showing both marks.
        if let symbolName {
            return DisplayRepresentation(title: "\(name)", image: .init(systemName: symbolName))
        }
        return DisplayRepresentation(title: "\(emoji) \(name)")
    }
}

public extension ExpenseTag {
    var entity: ExpenseTagEntity {
        ExpenseTagEntity(id: self.id, name: self.name, emoji: self.emoji, symbolName: self.symbolName)
    }
}

@MainActor
public struct ExpenseTagEntityQuery: EntityQuery {
    @Dependency
    var expenseStore: ExpenseStore

    public func entities(for identifiers: [UUID]) async throws -> [ExpenseTagEntity] {
        let all = try expenseStore.context.fetch(FetchDescriptor<ExpenseTag>())
        return all
            .filter { identifiers.contains($0.id) }
            .map(\.entity)
    }

    public func suggestedEntities() async throws -> [ExpenseTagEntity] {
        let all = try expenseStore.context.fetch(FetchDescriptor<ExpenseTag>(sortBy: [SortDescriptor(\.name)]))
        return all.map(\.entity)
    }
    
    public nonisolated init() { }
}
