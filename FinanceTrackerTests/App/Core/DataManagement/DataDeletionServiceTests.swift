import Foundation
import SwiftData
import Testing
import UIKit
@testable import SageKit

@Suite("Data deletion")
struct DataDeletionServiceTests {
    @Test @MainActor
    func expensesOnlyKeepsRecurringRules() throws {
        let container = try SageModelContainer.make(for: .test)
        let context = container.mainContext
        let rule = RecurringExpenseRule(
            name: "Rent",
            amount: 1_000,
            note: "",
            category: .needs,
            frequency: .monthly,
            startDate: .now
        )
        context.insert(Expense(name: "Rent", amount: 1_000, category: .needs))
        context.insert(rule)
        try context.save()

        try DataDeletionService(modelContext: context).deleteExpenses(includeRecurringRules: false)

        #expect(try context.fetch(FetchDescriptor<Expense>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<RecurringExpenseRule>()).map(\.id) == [rule.id])
    }

    @Test @MainActor
    func expensesAndRulesCannotGenerateNewExpenses() throws {
        let container = try SageModelContainer.make(for: .test)
        let context = container.mainContext
        context.insert(Expense(name: "Rent", amount: 1_000, category: .needs))
        context.insert(
            RecurringExpenseRule(
                name: "Rent",
                amount: 1_000,
                note: "",
                category: .needs,
                frequency: .monthly,
                startDate: .now
            )
        )
        try context.save()

        try DataDeletionService(modelContext: context).deleteExpenses(includeRecurringRules: true)
        try RecurringExpenseService(modelContext: context).generateAllExpenses(through: .now)

        #expect(try context.fetch(FetchDescriptor<Expense>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<RecurringExpenseRule>()).isEmpty)
    }

    @Test @MainActor
    func fullResetDeletesEveryUserModel() throws {
        let fileManager = DeletionFileManager()
        try fileManager.createDirectory(at: fileManager.documentsDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: fileManager.documentsDirectory) }
        let exportURL = fileManager.documentsDirectory.appendingPathComponent("sage-export.csv")
        let otherFileURL = fileManager.documentsDirectory.appendingPathComponent("my-backup.csv")
        let externalDirectory = fileManager.documentsDirectory.appendingPathComponent("ExternalCopies")
        try fileManager.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
        let externalCopyURL = externalDirectory.appendingPathComponent("sage-export.csv")
        let csv = Data("private expense data".utf8)
        try csv.write(to: exportURL)
        try csv.write(to: otherFileURL)
        try csv.write(to: externalCopyURL)

        let container = try SageModelContainer.make(for: .test)
        let context = container.mainContext
        let tag = ExpenseTag(name: "Custom", uiColor: .systemBlue, emoji: "💵")
        let account = ExpenseAccount(id: UUID(), name: "Checking", type: .bankAccount)
        context.insert(tag)
        context.insert(account)
        context.insert(Expense(name: "Purchase", amount: 20, category: .wants, tags: [tag], account: account))
        context.insert(
            RecurringExpenseRule(
                name: "Subscription",
                amount: 10,
                note: "",
                category: .wants,
                tags: [tag],
                frequency: .monthly,
                startDate: .now
            )
        )
        try context.save()

        let service = DataDeletionService(modelContext: context)
        try service.deleteAllUserData(fileManager: fileManager)
        try service.deleteAllUserData(fileManager: fileManager)

        #expect(!fileManager.fileExists(atPath: exportURL.path))
        #expect(try Data(contentsOf: otherFileURL) == csv)
        #expect(try Data(contentsOf: externalCopyURL) == csv)
        #expect(try context.fetch(FetchDescriptor<Expense>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<RecurringExpenseRule>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ExpenseTag>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ExpenseAccount>()).isEmpty)
    }

    @Test @MainActor
    func missingExportDoesNotCreateDocumentsDirectory() throws {
        let fileManager = DeletionFileManager()
        let container = try SageModelContainer.make(for: .test)
        let context = container.mainContext
        context.insert(Expense(name: "Purchase", amount: 20, category: .wants))
        try context.save()

        try DataDeletionService(modelContext: context).deleteAllUserData(fileManager: fileManager)

        #expect(!fileManager.fileExists(atPath: fileManager.documentsDirectory.path))
        #expect(try context.fetch(FetchDescriptor<Expense>()).isEmpty)
    }

    @Test @MainActor
    func exportRemovalFailurePropagatesBeforeDeletingModels() throws {
        let fileManager = DeletionFileManager()
        try fileManager.createDirectory(at: fileManager.documentsDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: fileManager.documentsDirectory) }
        let exportURL = fileManager.documentsDirectory.appendingPathComponent("sage-export.csv")
        let csv = Data("private expense data".utf8)
        try csv.write(to: exportURL)
        fileManager.failingRemovalURL = exportURL
        let container = try SageModelContainer.make(for: .test)
        let context = container.mainContext
        context.insert(Expense(name: "Purchase", amount: 20, category: .wants))
        try context.save()
        let service = DataDeletionService(modelContext: context)

        #expect(throws: CocoaError(.fileWriteNoPermission)) {
            try service.deleteAllUserData(fileManager: fileManager)
        }
        service.rollback()

        #expect(try Data(contentsOf: exportURL) == csv)
        #expect(try context.fetch(FetchDescriptor<Expense>()).count == 1)
    }

    @Test @MainActor
    func directoryAtExportPathIsNotRecursivelyDeleted() throws {
        let fileManager = DeletionFileManager()
        let exportURL = fileManager.documentsDirectory.appendingPathComponent("sage-export.csv")
        try fileManager.createDirectory(at: exportURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: fileManager.documentsDirectory) }
        let childURL = exportURL.appendingPathComponent("keep.csv")
        let csv = Data("user-owned file".utf8)
        try csv.write(to: childURL)
        let container = try SageModelContainer.make(for: .test)

        #expect(throws: CocoaError(.fileWriteInvalidFileName)) {
            try DataDeletionService(modelContext: container.mainContext).deleteAllUserData(fileManager: fileManager)
        }

        #expect(try Data(contentsOf: childURL) == csv)
    }

    @Test @MainActor
    func exportSymlinkDoesNotDeleteItsTarget() throws {
        let fileManager = DeletionFileManager()
        try fileManager.createDirectory(at: fileManager.documentsDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: fileManager.documentsDirectory) }
        let targetURL = fileManager.documentsDirectory.appendingPathComponent("keep.csv")
        let exportURL = fileManager.documentsDirectory.appendingPathComponent("sage-export.csv")
        let csv = Data("user-owned file".utf8)
        try csv.write(to: targetURL)
        try fileManager.createSymbolicLink(at: exportURL, withDestinationURL: targetURL)
        let container = try SageModelContainer.make(for: .test)

        try DataDeletionService(modelContext: container.mainContext).deleteAllUserData(fileManager: fileManager)

        #expect(!fileManager.fileExists(atPath: exportURL.path))
        #expect(try Data(contentsOf: targetURL) == csv)
    }
}

private final class DeletionFileManager: FileManager, @unchecked Sendable {
    let documentsDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SagePrivacyPackaging-\(UUID().uuidString)")
    var failingRemovalURL: URL?

    override func url(
        for directory: FileManager.SearchPathDirectory,
        in domain: FileManager.SearchPathDomainMask,
        appropriateFor url: URL?,
        create shouldCreate: Bool
    ) throws -> URL {
        #expect(directory == .documentDirectory)
        #expect(domain == .userDomainMask)
        #expect(!shouldCreate)
        return documentsDirectory
    }

    override func removeItem(at URL: URL) throws {
        if URL == failingRemovalURL {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.removeItem(at: URL)
    }
}
