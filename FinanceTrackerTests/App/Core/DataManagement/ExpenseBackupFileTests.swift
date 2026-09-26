import Foundation
import SwiftData
import Testing
@testable import SageKit

@Suite("Expense backup files")
struct ExpenseBackupFileTests {
    @Test @MainActor
    func zeroValueRecordsCanBeBackedUpAndRestored() async throws {
        let source = try SageModelContainer.make(for: .test)
        let expense = Expense(name: "Historical zero", amount: 0)
        let rule = RecurringExpenseRule(name: "Historical rule", amount: 0, note: "", category: .needs,
                                        frequency: .monthly, startDate: .now)
        source.mainContext.insert(expense)
        source.mainContext.insert(rule)
        try source.mainContext.save()
        let file = try await ExpenseBackupService.shared.createBackup(modelContainer: source, currencyCode: "USD")
        defer { try? FileManager.default.removeItem(at: file) }
        let data = try await ExpenseBackupService.shared.readExpenses(from: file)
        let destination = try SageModelContainer.make(for: .test)
        let importer = ExpenseImportService(modelContainer: destination)
        let result = try await importer.execute(importer.plan(data, ledgerCurrencyCode: "USD"), currencyGate: { "USD" })
        #expect(result.inserted == 1 && result.insertedRules == 1)
        let reader = ModelContext(destination)
        let restored = try #require(reader.fetch(FetchDescriptor<Expense>()).first)
        let restoredRule = try #require(reader.fetch(FetchDescriptor<RecurringExpenseRule>()).first)
        #expect(restored.amount == 0 && restored.id == expense.id)
        #expect(restoredRule.amount == 0 && restoredRule.id == rule.id)
        #expect(try importer.plan(data, ledgerCurrencyCode: "USD").result.totalInserted == 0)
    }

    @Test @MainActor
    func uniqueJSONAndCSVFilesReadPersistedSnapshots() async throws {
        let container = try SageModelContainer.make(for: .test)
        container.mainContext.autosaveEnabled = false
        let expense = Expense(name: "Saved", amount: 0.004)
        container.mainContext.insert(expense)
        try container.mainContext.save()
        expense.name = "Pending"
        container.mainContext.insert(Expense(name: "Draft", amount: 5))
        let service = ExpenseBackupService.shared
        let first = try await service.createBackup(modelContainer: container, currencyCode: "USD")
        defer { try? FileManager.default.removeItem(at: first) }
        let second = try await service.createBackup(modelContainer: container, currencyCode: "USD")
        defer { try? FileManager.default.removeItem(at: second) }
        let csv = try await service.exportCSV(modelContainer: container, currencyCode: "USD")
        defer { try? FileManager.default.removeItem(at: csv) }
        #expect(first != second && first.pathExtension == "json" && csv.pathExtension == "csv")
        let source = try await service.readExpenses(from: first)
        guard case .backup(let backup) = source else { Issue.record("JSON routed to CSV"); return }
        #expect(backup.expenses.map(\.name) == ["Saved"])
        #expect(backup.expenses[0].id == expense.id.uuidString.lowercased())
        let csvSource = try await service.readExpenses(from: csv)
        guard case .csv(let rows) = csvSource else { Issue.record("CSV routed to JSON"); return }
        #expect(rows.map(\.name) == ["Saved"] && rows[0].amount == 0.004)
        #expect(container.mainContext.hasChanges && expense.name == "Pending")
    }

    @Test(arguments: ["jsonInCSV", "malformedJSON", "csvInJSON", "sixColumn", "sevenColumn"])
    func routingUsesContentAndFormatWithoutFallback(kind: String) async throws {
        let csv = "name,date,amount,category,tag,note\nTest,2026-08-12T18:30:00Z,4,Needs,,"
        let data: Data
        switch kind {
        case "jsonInCSV": data = try ExpenseBackupCodec.encode(.init(currency: "USD", tags: [], expenses: []))
        case "malformedJSON": data = Data("{\"format\":\"sage.expense-backup\",\"version\":1,".utf8)
        case "sevenColumn": data = Data("name,date,amount,category,tag,note,currency\nTest,2026-08-12T18:30:00Z,4,Needs,,,USD".utf8)
        default: data = Data(csv.utf8)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Routing-\(UUID()).\(kind == "csvInJSON" ? "json" : "csv")")
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let source = try await ExpenseBackupService.shared.readExpenses(from: url)
            switch kind {
            case "jsonInCSV": #expect(!source.isCSV && source.count == 0)
            case "sixColumn": #expect(source.requiresCurrencyConsent && source.count == 1)
            case "sevenColumn": #expect(!source.requiresCurrencyConsent && source.isCSV && source.count == 1)
            default: Issue.record("Malformed or mislabeled JSON accepted")
            }
        } catch {
            #expect(kind == "malformedJSON" || kind == "csvInJSON")
        }
    }
}
