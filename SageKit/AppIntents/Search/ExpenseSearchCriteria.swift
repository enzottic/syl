//
//  ExpenseSearchCriteria.swift
//  SageKit
//

import AppIntents
import Foundation
import SwiftData

/// How a search orders its results.
public enum ExpenseSearchOrder: String, AppEnum, Sendable {
    case newest, oldest, largest, smallest

    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Order"
    public static var caseDisplayRepresentations: [ExpenseSearchOrder: DisplayRepresentation] = [
        .newest: "Newest First",
        .oldest: "Oldest First",
        .largest: "Largest First",
        .smallest: "Smallest First",
    ]
}

/// The filters behind Siri's expense search, kept free of Siri AI types so the matching
/// logic builds with every SDK and can be tested on any simulator.
public struct ExpenseSearchCriteria: Equatable, Sendable {
    public static let defaultLimit = 25
    public static let maximumLimit = 100

    /// The first day to include, from its start.
    public var startDate: Date?
    /// The last day to include, through its end.
    public var endDate: Date?
    /// Matched against the name, note, and tag names, ignoring case and diacritics.
    public var text: String?
    public var category: ExpenseCategory?
    /// An expense matches when any of its tags matches any of these names.
    public var tagNames: [String]
    public var minimumAmount: Double?
    public var maximumAmount: Double?
    public var order: ExpenseSearchOrder
    public var limit: Int

    public init(
        startDate: Date? = nil,
        endDate: Date? = nil,
        text: String? = nil,
        category: ExpenseCategory? = nil,
        tagNames: [String] = [],
        minimumAmount: Double? = nil,
        maximumAmount: Double? = nil,
        order: ExpenseSearchOrder = .newest,
        limit: Int? = nil
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.text = text
        self.category = category
        self.tagNames = tagNames
        self.minimumAmount = minimumAmount
        self.maximumAmount = maximumAmount
        self.order = order
        self.limit = min(max(limit ?? Self.defaultLimit, 1), Self.maximumLimit)
    }

    /// The half-open range of whole days to fetch, or nil for all time. A reversed range
    /// is swapped, since a person saying "from March to January" still means those months.
    func dateInterval(calendar: Calendar = .current) -> (start: Date?, end: Date?) {
        var start = startDate
        var end = endDate
        if let s = start, let e = end, s > e { swap(&start, &end) }
        let lower = start.map { calendar.startOfDay(for: $0) }
        let upper = end.flatMap { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) }
        return (lower, upper)
    }

    func matches(_ expense: Expense) -> Bool {
        if let category, expense.category != category { return false }
        let (low, high) = Self.amountBounds(minimumAmount, maximumAmount)
        if let low, expense.amount < low { return false }
        if let high, expense.amount > high { return false }
        let tags = expense.tags ?? []
        let wantedTags = tagNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !wantedTags.isEmpty,
           !tags.contains(where: { tag in wantedTags.contains { tag.name.localizedStandardContains($0) } }) {
            return false
        }
        if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            let found = expense.name.localizedStandardContains(text)
                || expense.note.localizedStandardContains(text)
                || tags.contains { $0.name.localizedStandardContains(text) }
            if !found { return false }
        }
        return true
    }

    private static func amountBounds(_ minimum: Double?, _ maximum: Double?) -> (Double?, Double?) {
        if let minimum, let maximum, minimum > maximum { return (maximum, minimum) }
        return (minimum, maximum)
    }

    func sorted(_ expenses: [Expense]) -> [Expense] {
        switch order {
        case .newest: expenses.sorted { $0.date > $1.date }
        case .oldest: expenses.sorted { $0.date < $1.date }
        case .largest: expenses.sorted { ($0.amount, $0.date) > ($1.amount, $1.date) }
        case .smallest: expenses.sorted { ($0.amount, $1.date) < ($1.amount, $0.date) }
        }
    }
}

/// A search's matches: the expenses to show, plus the count and total of every match.
public struct ExpenseSearchResult {
    public let expenses: [Expense]
    public let matchCount: Int
    public let total: Double

    /// What Siri says about the result.
    public func dialog(currencyCode: String) -> String {
        guard matchCount > 0 else { return "No expenses match that." }
        let totalText = total.currencyString(code: currencyCode)
        let noun = matchCount == 1 ? "expense" : "expenses"
        if expenses.count < matchCount {
            return "Found \(matchCount) \(noun) totaling \(totalText). Here are \(expenses.count) of them."
        }
        return "Found \(matchCount) \(noun) totaling \(totalText)."
    }
}

extension ExpenseStore {
    /// Expenses matching `criteria`, ordered and limited, with the count and total of all matches.
    public func searchExpenses(_ criteria: ExpenseSearchCriteria, calendar: Calendar = .current) throws -> ExpenseSearchResult {
        let (start, end) = criteria.dateInterval(calendar: calendar)
        let descriptor: FetchDescriptor<Expense> = switch (start, end) {
        case let (start?, end?): ExpenseFetchDescriptors.range(start: start, end: end)
        case let (start?, nil): FetchDescriptor(predicate: #Predicate { $0.date >= start })
        case let (nil, end?): FetchDescriptor(predicate: #Predicate { $0.date < end })
        case (nil, nil): FetchDescriptor()
        }
        let matches = try context.fetch(descriptor).filter(criteria.matches)
        return ExpenseSearchResult(
            expenses: Array(criteria.sorted(matches).prefix(criteria.limit)),
            matchCount: matches.count,
            total: matches.reduce(0) { $0 + $1.amount }
        )
    }
}
