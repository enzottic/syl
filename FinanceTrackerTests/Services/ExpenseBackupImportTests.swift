import Foundation
import SwiftData
import Testing
import UIKit
@testable import SageKit

@Suite("Identity-preserving expense import")
@MainActor
struct ExpenseBackupImportTests {
    private enum Failure: Error { case expected }

    @Test(arguments: ["symbol", "emoji", "wideGamut", "legacy"])
    func tagAppearanceSurvivesBackupAndKeepsExistingEdits(kind: String) async throws {
        let source = try SageModelContainer.make(for: .test)
        let color: UIColor = kind == "wideGamut" ? UIColor(displayP3Red: 1, green: 0.2, blue: 0, alpha: 0.6) : .systemBlue
        let tag = ExpenseTag(name: "Travel", uiColor: color, emoji: kind == "emoji" ? "\u{1F680}" : "", symbolName: kind == "emoji" ? nil : "airplane")
        let expense = Expense(name: "Ticket", amount: 10, tags: [tag])
        let rule = RecurringExpenseRule(name: "Pass", amount: 5, note: "", category: .needs, tags: [tag], frequency: .monthly, startDate: .now)
        source.mainContext.insert(expense)
        source.mainContext.insert(rule)
        try source.mainContext.save()
        var backup = try ExpenseBackupCodec.decode(ExpenseBackupCodec.encode(ExpenseBackupCodec.snapshot(modelContainer: source, currency: "USD")))
        if kind == "legacy" { backup.tags[0].appearance = nil }
        let target = try SageModelContainer.make(for: .test)
        let importer = ExpenseImportService(modelContainer: target)
        _ = try await importer.execute(importer.plan(.backup(backup), ledgerCurrencyCode: "USD"), currencyGate: { "USD" })
        let reader = ModelContext(target)
        let restored = try #require(reader.fetch(FetchDescriptor<ExpenseTag>()).first)
        #expect(restored.emoji == (kind == "legacy" ? "" : tag.emoji))
        #expect(restored.symbolName == (kind == "legacy" ? "tag" : tag.symbolName))
        let expected = try ExpenseBackup.Tag.Appearance(color: kind == "legacy" ? .systemGray : color, emoji: "", symbolName: nil)
        let actual = try ExpenseBackup.Tag.Appearance(color: restored.uiColor, emoji: "", symbolName: nil)
        for (lhs, rhs) in zip(expected.light + expected.dark, actual.light + actual.dark) {
            #expect(abs(lhs - rhs) < 0.00001)
        }
        #expect(restored.taggedExpenses?.count == 1 && restored.taggedRecurringRules?.count == 1)
        restored.uiColor = .purple
        restored.emoji = "\u{1F33F}"
        restored.symbolName = nil
        try reader.save()
        // A new expense using the same tag must not reapply the backup's appearance.
        var extra = backup.expenses[0]
        extra.id = UUID().uuidString
        backup.expenses.append(extra)
        _ = try await importer.execute(importer.plan(.backup(backup), ledgerCurrencyCode: "USD"), currencyGate: { "USD" })
        let check = try #require(ModelContext(target).fetch(FetchDescriptor<ExpenseTag>()).first)
        #expect(check.emoji == "\u{1F33F}" && check.symbolName == nil && check.uiColor.isEqual(UIColor.purple))
    }

    @Test(arguments: [false, true])
    func recurringRulesAndNewTagsRollBackTogether(cancel: Bool) async throws {
        let container = try SageModelContainer.make(for: .test)
        let tagID = UUID().uuidString
        let rule = ExpenseBackup.Rule(id: UUID().uuidString, name: "Rule", amount: "10", category: "Needs", note: "", tagIDs: [tagID], frequency: "Daily", startDateSecondsSince2001: 800_000_000)
        let backup = ExpenseBackup(currency: "USD", tags: [.init(id: tagID, name: "New tag")], expenses: [], recurringRules: [rule])
        let service = ExpenseImportService(modelContainer: container)
        let plan = try service.plan(.backup(backup), ledgerCurrencyCode: "USD")
        let task = Task {
            try await service.execute(plan, currencyGate: { "USD" }, progress: { _ in
                if cancel { withUnsafeCurrentTask { $0?.cancel() } }
            }, save: { _ in throw Failure.expected })
        }
        do {
            _ = try await task.value
            Issue.record("Expected rollback")
        } catch {
            #expect(cancel ? error is CancellationError : error is Failure)
        }
        let reader = ModelContext(container)
        reader.insert(Expense(name: "Unrelated later save", amount: 1))
        try reader.save()
        #expect(try reader.fetchCount(FetchDescriptor<RecurringExpenseRule>()) == 0)
        #expect(try reader.fetchCount(FetchDescriptor<ExpenseTag>()) == 0)
        #expect(try await service.execute(service.plan(.backup(backup), ledgerCurrencyCode: "USD"), currencyGate: { "USD" }).insertedRules == 1)
    }

    @Test(arguments: [false, true])
    func recurringRuleSnapshotRestoreAndRepeat(legacy: Bool) async throws {
        let source = try SageModelContainer.make(for: .test)
        source.mainContext.autosaveEnabled = false
        let modern = ExpenseTag(name: "Rent|Home", uiColor: .red, emoji: "")
        let old = ExpenseTag(name: "Legacy", uiColor: .blue, emoji: "")
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000.125)
        let rule = RecurringExpenseRule(name: "Rent", amount: 48.695, note: "Keep precision", category: .needs,
                                        tags: legacy ? [] : [modern], frequency: .monthly, startDate: start,
                                        endDate: start.addingTimeInterval(50_000_000), lastGeneratedDate: start,
                                        recurrenceTimeZoneIdentifier: legacy ? nil : "America/New_York")
        rule.tag = old
        rule.recurrenceEffectiveDate = legacy ? nil : start
        source.mainContext.insert(rule)
        try source.mainContext.save()
        rule.name = "Pending edit"
        let snapshot = try ExpenseBackupCodec.snapshot(modelContainer: source, currency: "USD")
        let backup = try ExpenseBackupCodec.decode(ExpenseBackupCodec.encode(snapshot))
        #expect(backup.version == 2 && backup.expenses.isEmpty && backup.recurringRules.count == 1)
        #expect(backup.tags.map(\.name) == [legacy ? "Legacy" : "Rent|Home"])
        #expect(backup.recurringRules[0].name == "Rent")
        #expect(source.mainContext.hasChanges)
        let destination = try SageModelContainer.make(for: .test)
        let service = ExpenseImportService(modelContainer: destination)
        let review = try service.plan(.backup(backup), ledgerCurrencyCode: "USD")
        #expect(review.result.inserted == 0 && review.result.insertedRules == 1 && review.result.newTags == 1)
        let result = try await service.execute(review, currencyGate: { "USD" })
        #expect(result.insertedRules == 1)
        let reader = ModelContext(destination)
        let restored = try #require(reader.fetch(FetchDescriptor<RecurringExpenseRule>()).first)
        #expect(restored.id == rule.id && restored.name == "Rent" && restored.amount == 48.695)
        #expect(restored.startDate == start && restored.lastGeneratedDate == start && restored.endDate == rule.endDate)
        #expect(restored.recurrenceEffectiveDate == rule.recurrenceEffectiveDate)
        #expect(restored.recurrenceTimeZoneIdentifier == rule.recurrenceTimeZoneIdentifier)
        #expect(restored.frequency == .monthly && restored.note == "Keep precision" && restored.account == nil)
        #expect(restored.tags?.first?.id == (legacy ? old.id : modern.id))
        restored.name = "Keep local rule"
        restored.amount = 99
        restored.tags = []
        for tag in try reader.fetch(FetchDescriptor<ExpenseTag>()) { reader.delete(tag) }
        try reader.save()
        let repeatPlan = try service.plan(.backup(backup), ledgerCurrencyCode: "USD")
        #expect(repeatPlan.result.totalInserted == 0 && repeatPlan.result.skippedRules == 1 && repeatPlan.result.newTags == 0)
        _ = try await service.execute(repeatPlan, currencyGate: { "USD" }, save: { _ in Issue.record("No-op must not save") })
        let check = ModelContext(destination)
        #expect(try check.fetch(FetchDescriptor<RecurringExpenseRule>()).first?.name == "Keep local rule")
        #expect(try check.fetchCount(FetchDescriptor<ExpenseTag>()) == 0)
    }

    @Test(arguments: [false, true], [false, true])
    func restoredRulesContinueWithoutRegeneratingHistory(staleCursor: Bool, keyless: Bool) async throws {
        let source = try SageModelContainer.make(for: .test)
        let start = try Date("2026-08-01T12:00:00Z", strategy: .iso8601)
        let rule = RecurringExpenseRule(name: "Daily", amount: 10, note: "", category: .needs, frequency: .daily,
                                        startDate: start, endDate: start.addingTimeInterval(2 * 86_400), recurrenceTimeZoneIdentifier: "UTC")
        source.mainContext.insert(rule)
        try source.mainContext.save()
        _ = try RecurringExpenseService(modelContext: source.mainContext).generateAllExpenses(through: start)
        let generated = try #require(source.mainContext.fetch(FetchDescriptor<Expense>()).first)
        if keyless { generated.recurringOccurrenceKey = nil }
        generated.date = start.addingTimeInterval(40 * 86_400)
        try source.mainContext.save()
        if staleCursor { rule.lastGeneratedDate = nil; try source.mainContext.save() }
        let backup = try ExpenseBackupCodec.snapshot(modelContainer: source, currency: "USD")
        #expect(backup.expenses.first?.recurringOccurrenceKey == RecurringExpenseOccurrence.key(ruleID: rule.id, scheduledDate: start))
        let destination = try SageModelContainer.make(for: .test)
        let importer = ExpenseImportService(modelContainer: destination)
        _ = try await importer.execute(importer.plan(.backup(backup), ledgerCurrencyCode: "USD"), currencyGate: { "USD" })
        let imported = try #require(ModelContext(destination).fetch(FetchDescriptor<Expense>()).first)
        #expect(imported.recurringScheduledDate == start)
        #expect(imported.date == generated.date)
        let maintenance = RecurringExpenseService(modelContext: ModelContext(destination))
        #expect(try maintenance.generateAllExpenses(through: start.addingTimeInterval(86_400)).generatedCount == 1)
        #expect(try maintenance.generateAllExpenses(through: start.addingTimeInterval(86_400)).generatedCount == 0)
        let reader = ModelContext(destination)
        #expect(try reader.fetchCount(FetchDescriptor<Expense>()) == 2)
        #expect(Set(try reader.fetch(FetchDescriptor<Expense>()).compactMap(\.recurringOccurrenceKey)).count == 2)
        #expect(try importer.plan(.backup(backup), ledgerCurrencyCode: "USD").result.totalInserted == 0)
    }

    @Test(arguments: ["saveFailure", "newRule", "replaceRule", "duplicateRule", "renameTag"])
    func recurringImportAtomicityAndInterleavedChanges(kind: String) async throws {
        let container = try SageModelContainer.make(for: .test)
        let writer = ModelContext(container)
        writer.autosaveEnabled = false
        let tag = ExpenseTag(name: "Original", uiColor: .red, emoji: "")
        writer.insert(tag)
        let existing = RecurringExpenseRule(name: "Existing", amount: 5, note: "", category: .needs, tags: [tag], frequency: .weekly, startDate: .now)
        writer.insert(existing)
        try writer.save()
        let newID = UUID()
        let newRule = ExpenseBackup.Rule(id: newID.uuidString, name: "New", amount: "5", category: "Needs", note: "", tagIDs: [tag.id.uuidString], frequency: "Monthly", startDateSecondsSince2001: 800_000_000)
        var backup = try ExpenseBackupCodec.snapshot(modelContainer: container, currency: "USD")
        backup.recurringRules.append(newRule)
        let service = ExpenseImportService(modelContainer: container)
        let plan = try service.plan(.backup(backup), ledgerCurrencyCode: "USD")
        do {
            _ = try await service.execute(plan, currencyGate: { "USD" }, progress: { _ in
                do {
                    if kind == "renameTag" {
                        tag.name = "New local name"
                        existing.name = "Local rule edit"
                    } else if ["newRule", "replaceRule", "duplicateRule"].contains(kind) {
                        if kind == "replaceRule" { writer.delete(existing); try writer.save() }
                        let collision = RecurringExpenseRule(name: "Interleaved", amount: 3, note: "", category: .needs, frequency: .daily, startDate: .now)
                        collision.id = kind == "newRule" ? newID : existing.id
                        writer.insert(collision)
                    }
                    try writer.save()
                } catch { Issue.record(error) }
            }, save: { context in
                if kind == "saveFailure" { throw Failure.expected }
                try context.save()
            })
            #expect(kind == "renameTag")
        } catch { #expect(kind != "renameTag") }
        let reader = ModelContext(container)
        let rules = try reader.fetch(FetchDescriptor<RecurringExpenseRule>())
        if kind == "renameTag" {
            #expect(rules.count == 2)
            #expect(rules.first { $0.id == existing.id }?.name == "Local rule edit")
            let savedTag = try #require(reader.fetch(FetchDescriptor<ExpenseTag>()).first)
            #expect(savedTag.name == "New local name" && savedTag.taggedRecurringRules?.count == 2)
            #expect(rules.first { $0.id == newID }?.tags?.first?.id == tag.id)
        } else {
            #expect(!rules.contains { $0.name == "New" })
        }
    }

    private func record(id: UUID = UUID(), rule: UUID? = nil, key: String? = nil, tags: [UUID] = [], date: Double = 812_345_678.1234567) -> ExpenseBackup.Record {
        .init(id: id.uuidString.lowercased(), name: "Backup", dateSecondsSince2001: date, amount: "48.695",
              category: "Needs", note: "Original", tagIDs: tags.map { $0.uuidString.lowercased() },
              recurringExpenseID: rule?.uuidString.lowercased(), recurringOccurrenceKey: key)
    }

    private func local(_ row: ExpenseBackup.Record, context: ModelContext) -> Expense {
        let expense = Expense(name: row.name, amount: Double(row.amount)!, category: .needs, date: row.date, note: row.note,
                              recurringExpenseId: row.recurringExpenseID.flatMap(UUID.init(uuidString:)), recurringOccurrenceKey: row.recurringOccurrenceKey)
        expense.id = UUID(uuidString: row.id)!
        context.insert(expense)
        return expense
    }

    @Test
    func sequentialRepeatKeepsEditsAndDoesNotSaveOrCreateSkippedTags() async throws {
        let container = try SageModelContainer.make(for: .test)
        let service = ExpenseImportService(modelContainer: container)
        let tagID = UUID()
        let sameNameID = UUID()
        let rows = [record(tags: [tagID, sameNameID]), record()]
        let backup = ExpenseBackup(currency: "USD", tags: [.init(id: tagID.uuidString, name: "Work|Travel"), .init(id: sameNameID.uuidString, name: "Work|Travel")], expenses: rows)
        let review = try service.plan(.backup(backup), ledgerCurrencyCode: "USD")
        #expect(review.result.inserted == 2)
        #expect(review.result.newTags == 2)
        var saves = 0
        let result = try await service.execute(review, currencyGate: { "USD" }, save: { context in
            saves += 1
            #expect(!context.autosaveEnabled)
            let expenses = try context.fetch(FetchDescriptor<Expense>())
            #expect(expenses.allSatisfy { $0.modelContext === context && ($0.tags ?? []).allSatisfy { $0.modelContext === context } })
            try context.save()
        })
        #expect(result.inserted == 2 && saves == 1)
        let editor = ModelContext(container)
        let saved = try #require(editor.fetch(FetchDescriptor<Expense>()).first { $0.id == UUID(uuidString: rows[0].id) })
        saved.name = "Local edit"
        saved.amount = 1.2345
        saved.date = saved.date.addingTimeInterval(999)
        saved.note = "Keep"
        saved.tags = []
        for tag in try editor.fetch(FetchDescriptor<ExpenseTag>()) { editor.delete(tag) }
        try editor.save()
        let repeatPlan = try service.plan(.backup(backup), ledgerCurrencyCode: "USD")
        #expect(repeatPlan.result.inserted == 0 && repeatPlan.result.skipped == 2 && repeatPlan.result.newTags == 0)
        _ = try await service.execute(repeatPlan, currencyGate: { "USD" }, save: { _ in Issue.record("No-op must not save") })
        let reader = ModelContext(container)
        #expect(try reader.fetchCount(FetchDescriptor<ExpenseTag>()) == 0)
        let unchanged = try #require(reader.fetch(FetchDescriptor<Expense>()).first { $0.id == saved.id })
        #expect(unchanged.name == "Local edit" && unchanged.amount == 1.2345 && unchanged.note == "Keep")
        #expect(unchanged.tags?.isEmpty == true)
    }

    @Test(arguments: [false, true])
    func legacyRecurrenceAfterDateEditAndRepairAddsOnlyMissing(repair: Bool) async throws {
        let container = try SageModelContainer.make(for: .test)
        let service = ExpenseImportService(modelContainer: container)
        let rule = UUID()
        let old = record(rule: rule)
        let incoming = record()
        let expense = local(old, context: container.mainContext)
        expense.date = expense.date.addingTimeInterval(100)
        expense.name = "Keep date edit"
        try container.mainContext.save()
        let backup = ExpenseBackup(currency: "USD", tags: [], expenses: [old, incoming])
        let review = try service.plan(.backup(backup), ledgerCurrencyCode: "USD")
        if repair {
            _ = try RecurringExpenseRepairService(modelContext: container.mainContext).repair()
            try container.mainContext.save()
        }
        let result = try await service.execute(review, currencyGate: { "USD" })
        #expect(result.inserted == 1 && result.skipped == 1)
        let reader = ModelContext(container)
        #expect(try reader.fetchCount(FetchDescriptor<RecurringExpenseRule>()) == 0)
        #expect(try reader.fetch(FetchDescriptor<Expense>()).first { $0.id == expense.id }?.name == "Keep date edit")
        #expect(try service.plan(.backup(backup), ledgerCurrencyCode: "USD").result.skipped == 2)
    }

    @Test(arguments: ["crossed", "uuidDuplicate", "keyDuplicate", "matchedOtherUUIDGroup", "matchedOtherKeyGroup", "differentRule", "recurringVsManual", "differentExplicitKey"])
    func relevantConflictsBlock(kind: String) throws {
        let container = try SageModelContainer.make(for: .test)
        let context = container.mainContext
        let rule = UUID()
        var row = record(rule: rule)
        row.recurringOccurrenceKey = row.effectiveOccurrenceKey
        let first = local(row, context: context)
        switch kind {
        case "crossed":
            first.recurringOccurrenceKey = nil
            first.date = first.date.addingTimeInterval(500)
            _ = local(record(rule: rule, key: row.recurringOccurrenceKey), context: context)
        case "uuidDuplicate": _ = local(record(id: first.id), context: context)
        case "keyDuplicate": _ = local(record(rule: rule, key: row.recurringOccurrenceKey), context: context)
        case "matchedOtherUUIDGroup":
            row.id = UUID().uuidString
            _ = local(record(id: first.id), context: context)
        case "matchedOtherKeyGroup":
            row.recurringOccurrenceKey = nil
            row.dateSecondsSince2001 += 500
            _ = local(record(rule: rule, key: first.recurringOccurrenceKey), context: context)
        case "differentRule": first.recurringExpenseId = UUID()
        case "recurringVsManual": first.recurringExpenseId = nil; first.recurringOccurrenceKey = nil
        default: first.recurringOccurrenceKey = RecurringExpenseOccurrence.key(ruleID: rule, scheduledDate: first.date.addingTimeInterval(10))
        }
        try context.save()
        #expect(throws: ExpenseImportError.conflict) {
            try ExpenseImportService(modelContainer: container).plan(.backup(.init(currency: "USD", tags: [], expenses: [row])), ledgerCurrencyCode: "USD")
        }
    }

    @Test
    func sameKeyDifferentUUIDSkipsAndUnrelatedDuplicateGroupsDoNotBlock() async throws {
        let container = try SageModelContainer.make(for: .test)
        let rule = UUID()
        let row = record(rule: rule)
        let existing = local(row, context: container.mainContext)
        existing.id = UUID()
        let unrelated = record()
        _ = local(unrelated, context: container.mainContext)
        _ = local(unrelated, context: container.mainContext)
        for _ in 0..<2 { container.mainContext.insert(ExpenseTag(name: "Unrelated", uiColor: .red, emoji: "")) }
        try container.mainContext.save()
        let service = ExpenseImportService(modelContainer: container)
        let review = try service.plan(.backup(.init(currency: "USD", tags: [], expenses: [row, record()])), ledgerCurrencyCode: "USD")
        #expect(review.result.skipped == 1)
        #expect(try await service.execute(review, currencyGate: { "USD" }).inserted == 1)
    }

    @Test(arguments: ["newExpense", "newKey", "replaceExpense", "deleteExpense", "newTag", "replaceTag", "deleteTag", "duplicateTag", "currency"])
    func freshReaderRejectsInterleavedChanges(kind: String) async throws {
        let container = try SageModelContainer.make(for: .test)
        let writer = ModelContext(container)
        writer.autosaveEnabled = false
        let tagID = UUID()
        let tag = ExpenseTag(id: tagID, name: "Tag", uiColor: .red, emoji: "")
        let tagInitiallyMissing = kind == "newTag"
        if !tagInitiallyMissing { writer.insert(tag) }
        let matchedRow = record()
        let matched = local(matchedRow, context: writer)
        let added = record(rule: UUID(), tags: [tagID])
        try writer.save()
        let backup = ExpenseBackup(currency: "USD", tags: [.init(id: tagID.uuidString, name: "Tag")], expenses: [matchedRow, added])
        let service = ExpenseImportService(modelContainer: container)
        let review = try service.plan(.backup(backup), ledgerCurrencyCode: "USD")
        var currency = "USD"
        do {
            _ = try await service.execute(review, currencyGate: { currency }, progress: { _ in
                do {
                    switch kind {
                    case "newExpense": _ = local(added, context: writer)
                    case "newKey":
                        var other = added
                        other.id = UUID().uuidString
                        _ = local(other, context: writer)
                    case "replaceExpense": writer.delete(matched); try writer.save(); _ = local(matchedRow, context: writer)
                    case "deleteExpense": writer.delete(matched)
                    case "newTag": writer.insert(tag)
                    case "replaceTag":
                        writer.delete(tag)
                        try writer.save()
                        writer.insert(ExpenseTag(id: tagID, name: "Tag", uiColor: .blue, emoji: ""))
                    case "deleteTag": writer.delete(tag)
                    case "duplicateTag": writer.insert(ExpenseTag(id: tagID, name: "Other", uiColor: .blue, emoji: ""))
                    case "currency": currency = "EUR"
                    default: break
                    }
                    try writer.save()
                } catch { Issue.record(error) }
            }, save: { _ in Issue.record("A changed plan must not save") })
            Issue.record("Interleaved change was accepted")
        } catch is ExpenseImportError {}
        let reader = ModelContext(container)
        let expenses = try reader.fetch(FetchDescriptor<Expense>())
        #expect(expenses.count == (["newExpense", "newKey"].contains(kind) ? 2 : (kind == "deleteExpense" ? 0 : 1)))
        #expect(try reader.fetchCount(FetchDescriptor<RecurringExpenseRule>()) == 0)
    }

    @Test
    func tagRenameAndUnrelatedContentEditsAllowedDuringStaging() async throws {
        let container = try SageModelContainer.make(for: .test)
        let writer = ModelContext(container)
        let tag = ExpenseTag(name: "Old", uiColor: .red, emoji: "", budget: 123)
        writer.insert(tag)
        let matchedRow = record()
        let matched = local(matchedRow, context: writer)
        matched.tags = [tag]
        let removed = Expense(name: "Remove tag during import", amount: 2, tags: [tag])
        writer.insert(removed)
        try writer.save()
        let backup = ExpenseBackup(currency: "USD", tags: [.init(id: tag.id.uuidString, name: "Incoming name")], expenses: [matchedRow, record(tags: [tag.id])])
        let service = ExpenseImportService(modelContainer: container)
        let review = try service.plan(.backup(backup), ledgerCurrencyCode: "USD")
        let result = try await service.execute(review, currencyGate: { "USD" }, progress: { _ in
            tag.name = "Renamed during import"
            tag.budget = 456
            matched.name = "Saved edit"
            removed.tags = []
            writer.insert(Expense(name: "New UI expense", amount: 2, tags: [tag]))
            do { try writer.save() } catch { Issue.record(error) }
        })
        #expect(result.inserted == 1 && result.newTags == 0)
        let reader = ModelContext(container)
        let persistedTag = try #require(reader.fetch(FetchDescriptor<ExpenseTag>()).first)
        #expect(persistedTag.name == "Renamed during import" && persistedTag.budget == 456)
        #expect(Set((persistedTag.taggedExpenses ?? []).map(\.name)) == ["Saved edit", "New UI expense", "Backup"])
        #expect(try reader.fetch(FetchDescriptor<Expense>()).first { $0.name == "Remove tag during import" }?.tags?.isEmpty == true)
        #expect(try reader.fetch(FetchDescriptor<Expense>()).first { $0.name == "Backup" }?.tags?.first?.id == tag.id)
    }

    @Test(arguments: [false, true])
    func failureAndCancellationRollbackAndReleaseGuard(cancel: Bool) async throws {
        let container = try SageModelContainer.make(for: .test)
        let service = ExpenseImportService(modelContainer: container)
        let tagID = UUID()
        let backup = ExpenseBackup(currency: "USD", tags: [.init(id: tagID.uuidString, name: "New")], expenses: (0..<30).map { _ in record(tags: [tagID]) })
        let review = try service.plan(.backup(backup), ledgerCurrencyCode: "USD")
        var failedContext: ModelContext?
        let task = Task { @MainActor in
            try await service.execute(review, currencyGate: { "USD" }, progress: { count in
                if cancel && count == 26 { withUnsafeCurrentTask { $0?.cancel() } }
            }, save: { context in failedContext = context; throw Failure.expected })
        }
        do { _ = try await task.value; Issue.record("Expected failure") }
        catch is CancellationError { #expect(cancel) }
        catch Failure.expected { #expect(!cancel) }
        if let failedContext { #expect(!failedContext.hasChanges); try failedContext.save() }
        let reader = ModelContext(container)
        #expect(try reader.fetchCount(FetchDescriptor<Expense>()) == 0)
        #expect(try reader.fetchCount(FetchDescriptor<ExpenseTag>()) == 0)
        #expect(try await service.execute(review, currencyGate: { "USD" }).inserted == 30)
    }

    @Test
    func overlappingInstancesAreRejectedAndChangedReviewMustBeAcceptedAgain() async throws {
        let container = try SageModelContainer.make(for: .test)
        let service = ExpenseImportService(modelContainer: container)
        let row = record()
        let backup = ExpenseBackup(currency: "USD", tags: [], expenses: [row])
        let review = try service.plan(.backup(backup), ledgerCurrencyCode: "USD")
        var other: Task<Void, Never>?
        _ = try await service.execute(review, currencyGate: { "USD" }, progress: { _ in
            other = Task { @MainActor in
                do {
                    _ = try await ExpenseImportService(modelContainer: container).execute(review, currencyGate: { "USD" })
                    Issue.record("Overlapping import was accepted")
                } catch { #expect(error as? ExpenseImportError == .alreadyImporting) }
            }
        })
        await other?.value
        do {
            _ = try await service.execute(review, currencyGate: { "USD" }, save: { _ in Issue.record("Stale review saved") })
            Issue.record("Stale review accepted")
        } catch { #expect(error as? ExpenseImportError == .changed) }
        let updated = try service.plan(.backup(backup), ledgerCurrencyCode: "USD")
        #expect(updated.result.skipped == 1)
    }

    @Test(arguments: ["ambiguous", "rename", "replacement", "idChange", "newSkippedName", "repeatedNames"])
    func csvNameResolutionIsUnambiguousAndRechecked(kind: String) async throws {
        let container = try SageModelContainer.make(for: .test)
        let writer = ModelContext(container)
        let tag = ExpenseTag(name: "Known", uiColor: .red, emoji: "")
        writer.insert(tag)
        if kind == "ambiguous" { writer.insert(ExpenseTag(name: "Known", uiColor: .blue, emoji: "")) }
        try writer.save()
        let rows = [ExportableExpense(name: "CSV", date: .now, amount: 4, category: "Needs", tag: "Known|Known|Skipped", note: "", currencyCode: "USD")]
        let service = ExpenseImportService(modelContainer: container)
        do {
            let review = try service.plan(.csv(rows), ledgerCurrencyCode: "USD")
            let result = try await service.execute(review, currencyGate: { "USD" }, progress: { _ in
                do {
                    switch kind {
                    case "rename": tag.name = "Renamed"
                    case "replacement":
                        writer.delete(tag)
                        try writer.save()
                        writer.insert(ExpenseTag(id: tag.id, name: "Known", uiColor: .blue, emoji: ""))
                    case "idChange": tag.id = UUID()
                    case "newSkippedName": writer.insert(ExpenseTag(name: "Skipped", uiColor: .blue, emoji: ""))
                    default: break
                    }
                    try writer.save()
                } catch { Issue.record(error) }
            })
            #expect(kind == "repeatedNames" && result.inserted == 1)
            #expect(try ModelContext(container).fetch(FetchDescriptor<Expense>()).first?.tags?.count == 1)
        } catch {
            if kind == "ambiguous" { #expect(error as? ExpenseImportError == .ambiguousTag("Known")) }
            else { #expect(error as? ExpenseImportError == .changed) }
            #expect(try ModelContext(container).fetchCount(FetchDescriptor<Expense>()) == 0)
        }
    }

    @Test
    func diskReopenAndRecurringGenerationSuppression() async throws {
        UIColorValueTransformer.register()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BackupTest-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Sage.sqlite")
        let schema = Schema(versionedSchema: SageSchemaV9.self)
        func open() throws -> ModelContainer {
            try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        }
        let ruleID = UUID()
        let row = record(rule: ruleID)
        let backup = ExpenseBackup(currency: "USD", tags: [], expenses: [row], recurringRules: [
            .init(id: ruleID.uuidString, name: "Rule", amount: "48.695", category: "Needs", note: "", tagIDs: [],
                  frequency: "Daily", startDateSecondsSince2001: row.dateSecondsSince2001, recurrenceTimeZoneIdentifier: "GMT")
        ])
        var container: ModelContainer? = try open()
        if let container {
            let service = ExpenseImportService(modelContainer: container)
            let review = try service.plan(.backup(backup), ledgerCurrencyCode: "USD")
            _ = try await service.execute(review, currencyGate: { "USD" })
            #expect(try ModelContext(container).fetch(FetchDescriptor<RecurringExpenseRule>()).first?.lastGeneratedDate == nil)
        }
        container = nil
        let reopened = try open()
        let service = ExpenseImportService(modelContainer: reopened)
        #expect(try service.plan(.backup(backup), ledgerCurrencyCode: "USD").result.skipped == 1)
        #expect(try service.plan(.backup(backup), ledgerCurrencyCode: "USD").result.skippedRules == 1)
        let reader = ModelContext(reopened)
        let saved = try #require(reader.fetch(FetchDescriptor<Expense>()).first)
        #expect(saved.date == row.date && saved.amount == 48.695 && saved.id == UUID(uuidString: row.id))
        #expect(saved.recurringOccurrenceKey == nil)
        #expect(saved.recurringScheduledDate == row.date)
        let result = try RecurringExpenseService(modelContext: reader).generateAllExpenses(through: row.date)
        #expect(result.generatedCount == 0 && result.skippedCount == 1 && result.repair.backfilledCount == 1)
        #expect(try reader.fetchCount(FetchDescriptor<Expense>()) == 1)
    }
}
