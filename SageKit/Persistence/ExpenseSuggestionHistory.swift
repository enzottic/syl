import Foundation
import SwiftData

/// Searches persisted names in date order without materializing the entire ledger.
@MainActor
public enum ExpenseSuggestionHistory {
    private static let pageSize = 32

    public static func recentDistinctMatches(
        for name: String,
        limit: Int,
        in context: ModelContext
    ) throws -> [Expense] {
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, limit > 0 else { return [] }

        var matches: [Expense] = []
        var seenNames = Set<String>()
        var offset = 0
        while matches.count < limit {
            let page = try context.fetch(descriptor(for: query, offset: offset))
            for expense in page where expense.name.localizedCaseInsensitiveContains(query) {
                if seenNames.insert(expense.name.lowercased()).inserted {
                    matches.append(expense)
                    if matches.count == limit { break }
                }
            }
            guard page.count == pageSize else { break }
            offset += page.count
        }
        return matches
    }

    /// Returns the newest tagged expense with the same name, including hidden tags.
    /// The caller decides whether the tag is eligible for a suggestion.
    public static func newestTaggedMatch(for name: String, in context: ModelContext) throws -> (name: String, tagName: String?)? {
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }

        var offset = 0
        while true {
            let page = try context.fetch(descriptor(for: query, offset: offset))
            if let expense = page.first(where: {
                $0.name.lowercased() == query.lowercased() && $0.tags?.first != nil
            }) {
                return (name: expense.name, tagName: expense.tags?.first?.name)
            }
            guard page.count == pageSize else { return nil }
            offset += page.count
        }
    }

    private static func descriptor(for query: String, offset: Int) -> FetchDescriptor<Expense> {
        var descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate { $0.name.localizedStandardContains(query) },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = pageSize
        descriptor.fetchOffset = offset
        return descriptor
    }
}
