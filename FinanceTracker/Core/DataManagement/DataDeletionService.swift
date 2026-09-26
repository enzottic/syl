//
//  DataDeletionService.swift
//  FinanceTracker
//

import Foundation
import CloudKit
import CoreData
import SageKit
import SwiftData

@MainActor
struct DataDeletionService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // Deletes every expense. Recurring rules stay active unless the caller also deletes them.
    func deleteExpenses(includeRecurringRules: Bool) throws {
        try modelContext.delete(model: Expense.self)

        if includeRecurringRules {
            try modelContext.delete(model: RecurringExpenseRule.self)
        }

        try modelContext.save()
    }

    // Removes Sage's local CSV export, then deletes all user-created records in the local model store.
    // File removal cannot be rolled back if a later model operation fails. External copies are untouched.
    func deleteAllUserData(fileManager: FileManager = .default) throws {
        try Self.deleteLocalExport(fileManager: fileManager)
        try modelContext.delete(model: Expense.self)
        try modelContext.delete(model: RecurringExpenseRule.self)
        try modelContext.delete(model: ExpenseTag.self)
        try modelContext.delete(model: ExpenseAccount.self)
        try modelContext.save()
    }

    static func deleteLocalExport(fileManager: FileManager = .default) throws {
        let documentsDirectory = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        
        let exportURL = documentsDirectory.appendingPathComponent("sage-export.csv")
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: exportURL.path)
            let type = attributes[.type] as? FileAttributeType
            
            // Never recursively remove a directory, even if it has the export's filename.
            guard type == .typeRegular || type == .typeSymbolicLink else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            
            try fileManager.removeItem(at: exportURL)
            
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            // No local export is already the desired state, including on repeated resets.
        }
    }

    func rollback() {
        modelContext.rollback()
    }
}

/// Run only before SwiftData opens its store. Core Data records the user purge in
/// its mirroring metadata, unlike an out-of-band CKDatabase zone delete.
@MainActor
enum CloudDataDeletionService {
    static func purgeMirroredData() async throws {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SageModelContainer.appGroupIdentifier
        ) else {
            throw SageModelContainer.Error.appGroupUnavailable
        }
        guard let model = NSManagedObjectModel.makeManagedObjectModel(
            for: Schema(versionedSchema: SageSchemaV9.self)
        ) else {
            throw CocoaError(.coderInvalidValue)
        }
        let description = NSPersistentStoreDescription(url: groupURL.appending(path: "Sage.sqlite"))
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.me.enzottic.FinanceTracker"
        )
        description.shouldAddStoreAsynchronously = false
        let container = NSPersistentCloudKitContainer(name: "Sage", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            container.loadPersistentStores { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
        let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone")
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                container.purgeObjectsAndRecordsInZone(with: zoneID, in: nil) { _, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
        } catch {
            if let store = container.persistentStoreCoordinator.persistentStores.first {
                try? container.persistentStoreCoordinator.remove(store)
            }
            throw error
        }
        if let store = container.persistentStoreCoordinator.persistentStores.first {
            try container.persistentStoreCoordinator.remove(store)
        }
    }
}
