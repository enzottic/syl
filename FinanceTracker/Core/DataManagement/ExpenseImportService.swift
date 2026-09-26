import Foundation
import SageKit
import SwiftData
import UIKit

public nonisolated enum ExpenseImportSource: Equatable, Sendable {
    case backup(ExpenseBackup)
    case csv([ExportableExpense])

    public var count: Int {
        switch self { case .backup(let backup): backup.expenses.count; case .csv(let rows): rows.count }
    }
    public var isCSV: Bool { if case .csv = self { true } else { false } }
    public var requiresCurrencyConsent: Bool {
        if case .csv(let rows) = self { rows.contains { $0.currencyCode == nil } } else { false }
    }
    public var ruleCount: Int {
        if case .backup(let backup) = self { backup.recurringRules.count } else { 0 }
    }
}

public nonisolated struct ExpenseImportResult: Equatable, Sendable {
    public let inserted: Int
    public let skipped: Int
    public let newTags: Int
    public var insertedRules: Int = 0
    public var skippedRules: Int = 0
    public var totalInserted: Int { inserted + insertedRules }
}

public nonisolated struct ExpenseImportPlan: Equatable {
    public let source: ExpenseImportSource
    public let currency: String
    public let creatingTagNames: [String]
    public let result: ExpenseImportResult
    fileprivate let added: Set<Int>
    fileprivate let matches: [Int: ExpenseImportIdentity]
    fileprivate let tagMatches: [String: PersistentIdentifier]
    fileprivate let tagIDs: [String: UUID]
    fileprivate let newTags: [String: String]
    fileprivate let addedRules: Set<Int>
    fileprivate let ruleMatches: [Int: PersistentIdentifier]
}

private nonisolated struct ExpenseImportIdentity: Equatable {
    let persistentID: PersistentIdentifier
    let id: UUID
    let rule: UUID?
    let storedKey: String?
    let effectiveKey: String?
}

public nonisolated enum ExpenseImportError: LocalizedError, Equatable {
    case conflict
    case ambiguousTag(String)
    case changed
    case alreadyImporting
    case currencyChanged
    case conflictingRules

    public var errorDescription: String? {
        switch self {
        case .conflict: "Conflicting expense identities were found. No expenses were saved. Resolve the existing copies before importing."
        case .ambiguousTag(let name): "More than one saved tag matches '\(name)'. Resolve those tags before importing; Syl will not choose one arbitrarily."
        case .changed: "Saved data changed while preparing this import. Review the updated summary before importing again."
        case .alreadyImporting: "Another import is in progress. Wait for it to finish."
        case .currencyChanged: "The ledger currency changed. Review the file again. No amounts were converted."
        case .conflictingRules: "Multiple saved recurring rules share an imported ID. Resolve those copies before importing. Nothing was saved."
        }
    }
}

@MainActor
public struct ExpenseImportService {
    private let modelContainer: ModelContainer
    private static var activeContainers = Set<ObjectIdentifier>()

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    /// A read-only review of persisted identities, not a similarity comparison.
    public func plan(_ source: ExpenseImportSource, ledgerCurrencyCode: String, creatingTagNames: [String] = []) throws -> ExpenseImportPlan {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        return try plan(source, currency: ledgerCurrencyCode, creatingTagNames: creatingTagNames, context: context)
    }

    private func plan(_ source: ExpenseImportSource, currency: String, creatingTagNames: [String], context: ModelContext) throws -> ExpenseImportPlan {
        var added = Set<Int>()
        var matches: [Int: ExpenseImportIdentity] = [:]
        var tagMatches: [String: PersistentIdentifier] = [:]
        var tagIDs: [String: UUID] = [:]
        var newTags: [String: String] = [:]
        var addedRules = Set<Int>()
        var ruleMatches: [Int: PersistentIdentifier] = [:]
        let tags = try context.fetch(FetchDescriptor<ExpenseTag>())
        switch source {
        case .backup(let backup):
            try ExpenseBackupCodec.validate(backup)
            guard backup.currency == currency else { throw ExpenseImportError.currencyChanged }
            let locals = try context.fetch(FetchDescriptor<Expense>()).map { expense in
                ExpenseImportIdentity(persistentID: expense.persistentModelID, id: expense.id,
                                      rule: expense.recurringExpenseId, storedKey: expense.recurringOccurrenceKey,
                                      effectiveKey: expense.recurringOccurrenceKey ?? expense.recurringExpenseId.flatMap {
                    RecurringExpenseOccurrence.safeKey(ruleID: $0, scheduledDate: expense.recurringScheduledDate ?? expense.date)
                })
            }
            let byID = Dictionary(grouping: locals, by: \.id)
            let byKey = Dictionary(grouping: locals.filter { $0.effectiveKey != nil }, by: { $0.effectiveKey! })
            for (index, record) in backup.expenses.enumerated() {
                let idMatches = byID[UUID(uuidString: record.id)!] ?? []
                let keyMatches = record.effectiveOccurrenceKey.flatMap { byKey[$0] } ?? []
                guard idMatches.count <= 1, keyMatches.count <= 1 else { throw ExpenseImportError.conflict }
                if let idMatch = idMatches.first, let keyMatch = keyMatches.first,
                   idMatch.persistentID != keyMatch.persistentID { throw ExpenseImportError.conflict }
                if let match = idMatches.first ?? keyMatches.first {
                    // Also check the matched record's other identity group, not only the incoming keys.
                    guard byID[match.id]?.count == 1,
                          match.effectiveKey.flatMap({ byKey[$0]?.count }) ?? 1 == 1 else { throw ExpenseImportError.conflict }
                    let rule = record.recurringExpenseID.flatMap(UUID.init(uuidString:))
                    guard match.rule == rule else { throw ExpenseImportError.conflict }
                    if let stored = match.storedKey {
                        guard let rule, RecurringExpenseOccurrence.isValidKey(stored, ruleID: rule) else { throw ExpenseImportError.conflict }
                    }
                    if let incoming = record.recurringOccurrenceKey, let stored = match.storedKey, incoming != stored {
                        throw ExpenseImportError.conflict
                    }
                    matches[index] = match
                } else {
                    added.insert(index)
                }
            }
            let byRuleID = Dictionary(grouping: try context.fetch(FetchDescriptor<RecurringExpenseRule>()), by: \.id)
            for (index, rule) in backup.recurringRules.enumerated() {
                let group = byRuleID[UUID(uuidString: rule.id)!] ?? []
                guard group.count <= 1 else { throw ExpenseImportError.conflictingRules }
                if let local = group.first { ruleMatches[index] = local.persistentModelID }
                else { addedRules.insert(index) }
            }
            let byTagID = Dictionary(grouping: tags, by: \.id)
            let referenced = Set((added.flatMap { backup.expenses[$0].tagIDs }
                + addedRules.flatMap { backup.recurringRules[$0].tagIDs }).map { $0.lowercased() })
            for tag in backup.tags where referenced.contains(tag.id.lowercased()) {
                let key = tag.id.lowercased()
                let group = byTagID[UUID(uuidString: key)!] ?? []
                guard group.count <= 1 else { throw ExpenseImportError.ambiguousTag(tag.name) }
                if let local = group.first {
                    tagMatches[key] = local.persistentModelID
                    tagIDs[key] = local.id
                }
                else { newTags[key] = tag.name }
            }
        case .csv(let rows):
            try ExpenseCSVCodec.validateCurrency(rows, ledgerCurrencyCode: currency, allowLegacy: true)
            added = Set(rows.indices)
            let byName = Dictionary(grouping: tags, by: \.name)
            for name in Set(rows.flatMap(\.tagNames)) {
                let group = byName[name] ?? []
                guard group.count <= 1 else { throw ExpenseImportError.ambiguousTag(name) }
                if let tag = group.first {
                    tagMatches[name] = tag.persistentModelID
                    tagIDs[name] = tag.id
                }
                else if creatingTagNames.contains(name) { newTags[name] = name }
            }
        }
        return ExpenseImportPlan(source: source, currency: currency, creatingTagNames: creatingTagNames,
                                 result: .init(inserted: added.count, skipped: matches.count, newTags: newTags.count,
                                               insertedRules: addedRules.count, skippedRules: ruleMatches.count),
                                 added: added, matches: matches, tagMatches: tagMatches, tagIDs: tagIDs, newTags: newTags,
                                 addedRules: addedRules, ruleMatches: ruleMatches)
    }

    public func execute(
        _ reviewed: ExpenseImportPlan,
        allowLegacy: Bool = false,
        currencyGate: () throws -> String,
        progress: (Int) -> Void = { _ in },
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) async throws -> ExpenseImportResult {
        let containerID = ObjectIdentifier(modelContainer)
        guard Self.activeContainers.insert(containerID).inserted else { throw ExpenseImportError.alreadyImporting }
        defer { Self.activeContainers.remove(containerID) }
        if reviewed.source.requiresCurrencyConsent && !allowLegacy { throw ExpenseCSVError.legacyCurrencyConfirmationRequired }
        guard try currencyGate() == reviewed.currency else { throw ExpenseImportError.currencyChanged }
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        do {
            let current = try plan(reviewed.source, currency: reviewed.currency, creatingTagNames: reviewed.creatingTagNames, context: context)
            guard current.added == reviewed.added,
                  current.matches.mapValues(\.persistentID) == reviewed.matches.mapValues(\.persistentID),
                   current.tagMatches == reviewed.tagMatches, current.tagIDs == reviewed.tagIDs,
                   current.addedRules == reviewed.addedRules, current.ruleMatches == reviewed.ruleMatches,
                  current.newTags == reviewed.newTags else { throw ExpenseImportError.changed }
            try Task.checkCancellation()
            guard current.result.totalInserted > 0 else { return current.result }
            var resolvedTags: [String: ExpenseTag] = [:]
            for (key, id) in current.tagMatches {
                guard let tag = context.model(for: id) as? ExpenseTag else { throw ExpenseImportError.changed }
                resolvedTags[key] = tag
            }
            let backupTags: [String: ExpenseBackup.Tag]
            if case .backup(let backup) = current.source {
                backupTags = Dictionary(uniqueKeysWithValues: backup.tags.map { ($0.id.lowercased(), $0) })
            } else { backupTags = [:] }
            for (key, name) in current.newTags {
                let tag = ExpenseTag(name: name, uiColor: .systemGray, emoji: "", symbolName: "tag")
                if !current.source.isCSV { tag.id = UUID(uuidString: key)! }
                if let appearance = backupTags[key]?.appearance {
                    tag.uiColor = appearance.uiColor
                    tag.emoji = appearance.emoji
                    tag.symbolName = appearance.symbolName
                }
                context.insert(tag)
                resolvedTags[key] = tag
            }
            var insertedIDs = Set<PersistentIdentifier>()
            var insertedRuleIDs = Set<PersistentIdentifier>()
            if case .backup(let backup) = current.source {
                for (completed, index) in current.addedRules.sorted().enumerated() {
                    let row = backup.recurringRules[index]
                    let rule = RecurringExpenseRule(
                        name: row.name, amount: Double(row.amount)!, note: row.note, category: ExpenseCategory(rawValue: row.category)!,
                        tags: row.tagIDs.compactMap { resolvedTags[$0.lowercased()] }, frequency: RecurrenceFrequency(rawValue: row.frequency)!,
                        startDate: Date(timeIntervalSinceReferenceDate: row.startDateSecondsSince2001),
                        endDate: row.endDateSecondsSince2001.map { Date(timeIntervalSinceReferenceDate: $0) },
                        lastGeneratedDate: row.lastGeneratedDateSecondsSince2001.map { Date(timeIntervalSinceReferenceDate: $0) },
                        recurrenceTimeZoneIdentifier: row.recurrenceTimeZoneIdentifier
                    )
                    rule.id = UUID(uuidString: row.id)!
                    rule.recurrenceEffectiveDate = row.recurrenceEffectiveDateSecondsSince2001.map { Date(timeIntervalSinceReferenceDate: $0) }
                    context.insert(rule)
                    insertedRuleIDs.insert(rule.persistentModelID)
                    progress(completed + 1)
                    if completed.isMultiple(of: 25) { await Task.yield() }
                    try Task.checkCancellation()
                }
            }
            for (completed, index) in current.added.sorted().enumerated() {
                let expense: Expense
                switch current.source {
                case .backup(let backup):
                    let row = backup.expenses[index]
                    expense = Expense(name: row.name, amount: Double(row.amount)!, category: ExpenseCategory(rawValue: row.category)!,
                                      date: row.date, tags: row.tagIDs.compactMap { resolvedTags[$0.lowercased()] }, note: row.note,
                                      recurringExpenseId: row.recurringExpenseID.flatMap(UUID.init(uuidString:)),
                                      recurringOccurrenceKey: row.recurringOccurrenceKey)
                    expense.id = UUID(uuidString: row.id)!
                case .csv(let rows):
                    let row = rows[index]
                    expense = Expense(name: row.name, amount: row.amount, category: ExpenseCategory(rawValue: row.category)!,
                                      date: row.date, tags: Set(row.tagNames).sorted().compactMap { resolvedTags[$0] }, note: row.note)
                }
                context.insert(expense)
                insertedIDs.insert(expense.persistentModelID)
                progress(current.addedRules.count + completed + 1)
                if completed.isMultiple(of: 25) { await Task.yield() }
                try Task.checkCancellation()
            }
            // Fresh reader sees interleaved saves, unlike the staging context's registered objects.
            guard try currencyGate() == current.currency else { throw ExpenseImportError.currencyChanged }
            let reader = ModelContext(modelContainer)
            reader.autosaveEnabled = false
            let final = try plan(current.source, currency: current.currency, creatingTagNames: current.creatingTagNames, context: reader)
            guard final == current else { throw ExpenseImportError.changed }
            for (key, id) in current.tagMatches {
                guard let latest = reader.model(for: id) as? ExpenseTag, let staged = resolvedTags[key] else {
                    throw ExpenseImportError.changed
                }
                // SwiftData can save stale tag properties when its inverse changes. Preserve
                // the latest persisted metadata and relationships, plus this batch's new links.
                let additions = (staged.taggedExpenses ?? []).filter { insertedIDs.contains($0.persistentModelID) }
                let ruleAdditions = (staged.taggedRecurringRules ?? []).filter { insertedRuleIDs.contains($0.persistentModelID) }
                staged.name = latest.name
                staged.uiColor = latest.uiColor
                staged.emoji = latest.emoji
                staged.symbolName = latest.symbolName
                staged.budget = latest.budget
                staged.expenses = latest.expenses?.compactMap { context.model(for: $0.persistentModelID) as? Expense }
                staged.taggedExpenses = (latest.taggedExpenses ?? []).compactMap { context.model(for: $0.persistentModelID) as? Expense } + additions
                staged.recurringRules = latest.recurringRules?.compactMap { context.model(for: $0.persistentModelID) as? RecurringExpenseRule }
                staged.taggedRecurringRules = (latest.taggedRecurringRules ?? []).compactMap { context.model(for: $0.persistentModelID) as? RecurringExpenseRule } + ruleAdditions
            }
            try Task.checkCancellation()
            // No yield or progress callback may occur between these checks and the commit.
            try save(context)
            return current.result
        } catch {
            context.rollback()
            throw error
        }
    }

    /// CSV compatibility API: every row appends with a fresh UUID.
    public func importExpenses(
        _ expenses: [ExportableExpense], ledgerCurrencyCode: String, allowLegacy: Bool = false,
        creatingTagNames: [String] = [], progress: (Int) -> Void = { _ in },
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) async throws -> Int {
        try ExpenseCSVCodec.validateCurrency(expenses, ledgerCurrencyCode: ledgerCurrencyCode, allowLegacy: allowLegacy)
        let review = try plan(.csv(expenses), ledgerCurrencyCode: ledgerCurrencyCode, creatingTagNames: creatingTagNames)
        return try await execute(review, allowLegacy: allowLegacy, currencyGate: { ledgerCurrencyCode }, progress: progress, save: save).inserted
    }
}
