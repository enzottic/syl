import Foundation
import SwiftData
import Testing
import UIKit
@testable import SageKit

@Suite("Atomic expense import")
struct ExpenseImportServiceTests {
    private enum SaveFailure: Error {
        case expected
    }

    @Test @MainActor
    func successCommitsOnceAndPreservesPendingUIEdits() async throws {
        let container = try SageModelContainer.make(for: .test)
        let uiContext = container.mainContext
        uiContext.autosaveEnabled = false
        let tag = ExpenseTag(name: "Known", uiColor: .systemBlue, emoji: "")
        let original = Expense(name: "Original", amount: 18, tags: [tag])
        uiContext.insert(tag)
        uiContext.insert(original)
        try uiContext.save()
        original.name = "Pending edit"
        tag.name = "Pending tag edit"
        let draftTag = ExpenseTag(name: "Draft", uiColor: .systemRed, emoji: "")
        let draft = Expense(name: "Draft expense", amount: 2, tags: [draftTag])
        uiContext.insert(draftTag)
        uiContext.insert(draft)

        let rows = (0..<60).map { index in
            ExportableExpense(
                name: "Imported \(index)", date: Date(timeIntervalSince1970: 1_723_500_000),
                amount: -12.34, category: "Wants", tag: "Known|New|Skipped", note: "A note", currencyCode: "USD"
            )
        }
        var saveCount = 0
        var progressValues: [Int] = []
        let count = try await ExpenseImportService(modelContainer: container).importExpenses(
            rows, ledgerCurrencyCode: "USD", creatingTagNames: ["Known", "New", "New", "Unused"],
            progress: { completed in
                progressValues.append(completed)
                let reader = ModelContext(container)
                #expect((try? reader.fetchCount(FetchDescriptor<Expense>())) == 1)
                #expect((try? reader.fetchCount(FetchDescriptor<ExpenseTag>())) == 1)
            },
            save: { context in
                saveCount += 1
                #expect(context !== uiContext)
                #expect(!context.autosaveEnabled)
                let imports = try context.fetch(FetchDescriptor<Expense>()).filter { $0.name.hasPrefix("Imported") }
                #expect(imports.count == rows.count)
                #expect(imports.allSatisfy { $0.modelContext === context })
                #expect(imports.allSatisfy { ($0.tags ?? []).allSatisfy { $0.modelContext === context && $0 !== tag } })
                try context.save()
            }
        )

        #expect(count == rows.count)
        #expect(saveCount == 1)
        #expect(progressValues == Array(1...60))
        #expect(original.name == "Pending edit")
        #expect(tag.name == "Pending tag edit")
        #expect(draft.modelContext === uiContext)
        #expect(draftTag.modelContext === uiContext)
        #expect(uiContext.hasChanges)
        let reader = ModelContext(container)
        let persisted = try reader.fetch(FetchDescriptor<Expense>())
        #expect(persisted.count == 61)
        #expect(persisted.contains { $0.id == original.id && $0.name == "Original" })
        let imported = try #require(persisted.first { $0.name == "Imported 0" })
        #expect(imported.amount == rows[0].amount)
        #expect(imported.date == rows[0].date)
        #expect(imported.category == .wants)
        #expect(imported.note == "A note")
        #expect(Set((imported.tags ?? []).map(\.name)) == ["Known", "New"])
        #expect(imported.tags?.first { $0.name == "Known" }?.id == tag.id)
        #expect(Set(try reader.fetch(FetchDescriptor<ExpenseTag>()).map(\.name)) == ["Known", "New"])
    }

    @Test @MainActor
    func failedSaveCannotResurrectExpensesTagsOrRelationshipsOnLaterSaves() async throws {
        let container = try SageModelContainer.make(for: .test)
        let uiContext = container.mainContext
        uiContext.autosaveEnabled = false
        let tag = ExpenseTag(name: "Known", uiColor: .systemBlue, emoji: "")
        let original = Expense(name: "Original", amount: 18, tags: [tag])
        uiContext.insert(tag)
        uiContext.insert(original)
        try uiContext.save()
        original.name = "Pending edit"
        tag.budget = 100
        let draftTag = ExpenseTag(name: "Draft", uiColor: .systemRed, emoji: "")
        let draft = Expense(name: "Draft expense", amount: 2, tags: [draftTag])
        uiContext.insert(draftTag)
        uiContext.insert(draft)
        let rows = (0..<60).map { index in
            ExportableExpense(name: "Failed \(index)", date: .now, amount: 4, category: "Needs", tag: "Known|New", note: "", currencyCode: "USD")
        }
        var failedContext: ModelContext?
        var saveCount = 0

        do {
            _ = try await ExpenseImportService(modelContainer: container).importExpenses(
                rows, ledgerCurrencyCode: "USD", creatingTagNames: ["New"],
                save: { context in
                    failedContext = context
                    saveCount += 1
                    #expect(!context.autosaveEnabled)
                    #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 61)
                    #expect(try context.fetchCount(FetchDescriptor<ExpenseTag>()) == 2)
                    throw SaveFailure.expected
                }
            )
            Issue.record("The injected save failure was suppressed.")
        } catch SaveFailure.expected {}

        #expect(saveCount == 1)
        let context = try #require(failedContext)
        #expect(!context.hasChanges)
        #expect(original.name == "Pending edit")
        #expect(tag.budget == 100)
        #expect(tag.taggedExpenses?.map(\.id) == [original.id])
        #expect(draft.modelContext === uiContext)
        #expect(draftTag.modelContext === uiContext)
        #expect(uiContext.hasChanges)

        // Exercise both possible later saves, not just immediate visibility after rollback.
        try context.save()
        let reader = ModelContext(container)
        #expect(try reader.fetch(FetchDescriptor<Expense>()).map(\.name) == ["Original"])
        #expect(try reader.fetch(FetchDescriptor<ExpenseTag>()).map(\.name) == ["Known"])
        try uiContext.save()
        try context.save()
        let laterReader = ModelContext(container)
        let persisted = try laterReader.fetch(FetchDescriptor<Expense>())
        #expect(Set(persisted.map(\.name)) == ["Pending edit", "Draft expense"])
        let tags = try laterReader.fetch(FetchDescriptor<ExpenseTag>())
        #expect(Set(tags.map(\.name)) == ["Known", "Draft"])
        let known = try #require(tags.first { $0.id == tag.id })
        #expect(known.budget == 100)
        #expect(known.taggedExpenses?.map(\.id) == [original.id])
    }

    @Test(arguments: [false, true]) @MainActor
    func interleavedUISavePreservesImportIsolation(shouldFail: Bool) async throws {
        let container = try SageModelContainer.make(for: .test)
        let uiContext = container.mainContext
        uiContext.autosaveEnabled = false
        let tag = ExpenseTag(name: "Known", uiColor: .systemBlue, emoji: "")
        let original = Expense(name: "Original", amount: 18, tags: [tag])
        uiContext.insert(tag)
        uiContext.insert(original)
        try uiContext.save()
        let rows = (0..<30).map { index in
            ExportableExpense(name: "Imported \(index)", date: .now, amount: 4, category: "Needs", tag: "Known|New", note: "", currencyCode: "USD")
        }

        do {
            let count = try await ExpenseImportService(modelContainer: container).importExpenses(
                rows, ledgerCurrencyCode: "USD", creatingTagNames: ["New"],
                progress: { completed in
                    guard completed == 27 else { return }
                    // Deterministic interleaving, not a test of automatic-save timing.
                    do {
                        original.name = "Committed UI edit"
                        try uiContext.save()
                        let reader = ModelContext(container)
                        let persisted = try reader.fetch(FetchDescriptor<Expense>())
                        #expect(persisted.count == 1)
                        let saved = try #require(persisted.first { $0.id == original.id })
                        #expect(saved.name == "Committed UI edit")
                        #expect(saved.tags?.map(\.id) == [tag.id])
                        #expect(try reader.fetch(FetchDescriptor<ExpenseTag>()).map(\.name) == ["Known"])
                        original.tags = []
                    } catch {
                        Issue.record(error)
                    }
                },
                save: { context in
                    if shouldFail { throw SaveFailure.expected }
                    try context.save()
                }
            )
            #expect(!shouldFail)
            #expect(count == rows.count)
        } catch SaveFailure.expected {
            #expect(shouldFail)
        }

        #expect(original.tags?.isEmpty == true)
        #expect(uiContext.hasChanges)
        let reader = ModelContext(container)
        let persisted = try reader.fetch(FetchDescriptor<Expense>())
        let saved = try #require(persisted.first { $0.id == original.id })
        #expect(saved.name == "Committed UI edit")
        #expect(saved.tags?.map(\.id) == [tag.id])
        #expect(saved.tags?.map(\.name) == ["Known"])
        let tags = try reader.fetch(FetchDescriptor<ExpenseTag>())
        #expect(persisted.count == (shouldFail ? 1 : 31))
        #expect(tags.count == (shouldFail ? 1 : 2))
        #expect(Set(tags.map(\.name)) == (shouldFail ? ["Known"] : ["Known", "New"]))
        if !shouldFail {
            let imported = persisted.filter { $0.name.hasPrefix("Imported ") }
            #expect(imported.count == 30)
            #expect(imported.allSatisfy { Set(($0.tags ?? []).map(\.name)) == ["Known", "New"] })
            #expect(imported.allSatisfy { $0.tags?.first { $0.name == "Known" }?.id == tag.id })
        }
    }

    @Test(arguments: ["category", "currency", "legacy", "amount", "mixed"]) @MainActor
    func invalidBatchNeverStartsWriting(invalidField: String) async throws {
        let container = try SageModelContainer.make(for: .test)
        let uiContext = container.mainContext
        uiContext.autosaveEnabled = false
        let draft = Expense(name: "Pending", amount: 2)
        uiContext.insert(draft)
        let valid = ExportableExpense(name: "Valid", date: .now, amount: 4, category: "Needs", tag: "New", note: "", currencyCode: invalidField == "legacy" ? nil : "USD")
        let invalid = ExportableExpense(
            name: "Invalid", date: .now, amount: invalidField == "amount" ? 0 : 4,
            category: invalidField == "category" ? "Invalid" : "Wants", tag: "New", note: "",
            currencyCode: invalidField == "legacy" || invalidField == "mixed" ? nil : "USD"
        )
        let expected: ExpenseCSVError
        switch invalidField {
        case "category": expected = .invalidCategory(row: 3, value: "Invalid")
        case "currency": expected = .currencyMismatch(expected: "EUR", actual: "USD")
        case "legacy": expected = .legacyCurrencyConfirmationRequired
        case "amount": expected = .invalidAmount(row: 3, value: "0.0")
        default: expected = .mixedCurrencies
        }

        do {
            _ = try await ExpenseImportService(modelContainer: container).importExpenses(
                [valid, invalid], ledgerCurrencyCode: invalidField == "currency" ? "EUR" : "USD",
                creatingTagNames: ["New"],
                progress: { _ in Issue.record("Insertion started before complete validation.") },
                save: { _ in Issue.record("Save called for an invalid batch.") }
            )
            Issue.record("Invalid batch was accepted.")
        } catch let error as ExpenseCSVError {
            #expect(error == expected)
        }

        #expect(uiContext.hasChanges)
        #expect(draft.name == "Pending")
        try uiContext.save()
        let reader = ModelContext(container)
        #expect(try reader.fetch(FetchDescriptor<Expense>()).map(\.name) == ["Pending"])
        #expect(try reader.fetch(FetchDescriptor<ExpenseTag>()).isEmpty)
    }

    @Test @MainActor
    func explicitLegacyConsentAppendsWithoutConversionOrDuplicateTags() async throws {
        let container = try SageModelContainer.make(for: .test)
        let service = ExpenseImportService(modelContainer: container)
        let csv = "name,date,amount,category,tag,note\nRefund,2026-08-12T18:30:00Z,-12.34,Wants,New,"
        let rows = try ExpenseCSVCodec.decode(csv)
        for _ in 0..<2 {
            let count = try await service.importExpenses(rows, ledgerCurrencyCode: "USD", allowLegacy: true, creatingTagNames: ["New"])
            #expect(count == 1)
        }
        let reader = ModelContext(container)
        let persisted = try reader.fetch(FetchDescriptor<Expense>())
        #expect(persisted.count == 2)
        #expect(Set(persisted.map(\.id)).count == 2)
        #expect(persisted.allSatisfy { $0.amount == -12.34 && $0.tags?.count == 1 })
        #expect(try reader.fetchCount(FetchDescriptor<ExpenseTag>()) == 1)
    }

    @Test(arguments: [48.695, -48.695, 0.004, -0.004]) @MainActor
    func historicalAmountSurvivesExportRestoreAndReexport(amount: Double) async throws {
        let source = try SageModelContainer.make(for: .test)
        source.mainContext.insert(Expense(
            name: "Historical", amount: amount, category: .wants,
            date: Date(timeIntervalSince1970: 1_723_500_000.125)
        ))
        try source.mainContext.save()
        let sourceReader = ModelContext(source)
        let saved = try #require(sourceReader.fetch(FetchDescriptor<Expense>()).first)
        let rows = [ExportableExpense(
            name: saved.name, date: saved.date, amount: saved.amount,
            category: saved.category.rawValue, tag: "", note: saved.note
        )]
        let csv = try ExpenseCSVCodec.encode(rows, currencyCode: "USD")
        let decoded = try ExpenseCSVCodec.decode(csv)
        let restored = try SageModelContainer.make(for: .test)
        let count = try await ExpenseImportService(modelContainer: restored).importExpenses(
            decoded, ledgerCurrencyCode: "USD"
        )
        #expect(count == 1)
        let restoredReader = ModelContext(restored)
        let expense = try #require(restoredReader.fetch(FetchDescriptor<Expense>()).first)
        #expect(expense.amount == amount)
        let reexported = try ExpenseCSVCodec.encode([ExportableExpense(
            name: expense.name, date: expense.date, amount: expense.amount,
            category: expense.category.rawValue, tag: "", note: expense.note
        )], currencyCode: "USD")
        #expect(reexported == csv)
        #expect(saved.amount == amount)
    }

    @Test @MainActor
    func cancellationDuringInsertionDiscardsTheEntireBatch() async throws {
        let container = try SageModelContainer.make(for: .test)
        let task = Task { @MainActor in
            let rows = (0..<60).map { index in
                ExportableExpense(name: "Cancelled \(index)", date: .now, amount: 4, category: "Needs", tag: "New", note: "", currencyCode: "USD")
            }
            return try await ExpenseImportService(modelContainer: container).importExpenses(
                rows, ledgerCurrencyCode: "USD", creatingTagNames: ["New"],
                progress: { completed in
                    if completed == 26 {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                },
                save: { _ in Issue.record("A cancelled import must not commit.") }
            )
        }
        do {
            _ = try await task.value
            Issue.record("Cancellation was suppressed.")
        } catch is CancellationError {}
        try container.mainContext.save()
        let reader = ModelContext(container)
        #expect(try reader.fetch(FetchDescriptor<Expense>()).isEmpty)
        #expect(try reader.fetch(FetchDescriptor<ExpenseTag>()).isEmpty)
    }
}
