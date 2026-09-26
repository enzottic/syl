//
//  DataDeletionService.swift
//  SageKit
//

import Foundation
import SageKit
import SwiftData

@MainActor
public struct DataDeletionService {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // Deletes every expense. Recurring rules stay active unless the caller also deletes them.
    public func deleteExpenses(includeRecurringRules: Bool) throws {
        try modelContext.delete(model: Expense.self)

        if includeRecurringRules {
            try modelContext.delete(model: RecurringExpenseRule.self)
        }

        try modelContext.save()
    }

    // Removes Sage's local CSV export, then deletes all user-created records in the local model store.
    // File removal cannot be rolled back if a later model operation fails. External copies are untouched.
    public func deleteAllUserData(fileManager: FileManager = .default) throws {
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

        try modelContext.delete(model: Expense.self)
        try modelContext.delete(model: RecurringExpenseRule.self)
        try modelContext.delete(model: ExpenseTag.self)
        try modelContext.delete(model: ExpenseAccount.self)
        try modelContext.save()
    }

    public func rollback() {
        modelContext.rollback()
    }
}
