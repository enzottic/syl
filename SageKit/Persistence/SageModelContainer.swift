//
//  SageModelContainer.swift
//  FinanceTracker
//
//  Created by Enzo on 5/21/26.
//

import Foundation
import SwiftData

public enum SageModelContainer {
    public enum Purpose: Sendable {
        case app
        case test
        case preview
        case previewEmpty
    }

    public enum Error: LocalizedError, Equatable {
        case appGroupUnavailable

        public var errorDescription: String? {
            switch self {
            case .appGroupUnavailable:
                return "The shared app storage is unavailable."
            }
        }
    }

    public nonisolated static let appGroupIdentifier = "group.me.enzottic.SageAppGroup"
    #if DEBUG
    public nonisolated static let supportsCloudSync = false
    public nonisolated static let cloudKitPreferenceKey = "dev.isCloudSyncEnabled"
    private nonisolated static let activeCloudKitPreferenceKey = "dev.activeCloudSyncEnabled"
    public nonisolated static let pendingCloudDeletionKey = "dev.pendingCloudDeletion"
    #else
    public nonisolated static let supportsCloudSync = true
    public nonisolated static let cloudKitPreferenceKey = "isCloudSyncEnabled"
    private nonisolated static let activeCloudKitPreferenceKey = "activeCloudSyncEnabled"
    public nonisolated static let pendingCloudDeletionKey = "pendingCloudDeletion"
    #endif

    // The CloudKit setting used by every process that opens the shared store.
    public nonisolated static var isCloudKitEnabled: Bool {
        guard supportsCloudSync else { return false }
        let defaults = SagePreferences.defaults
        guard !defaults.bool(forKey: pendingCloudDeletionKey) else { return false }
        if defaults.object(forKey: activeCloudKitPreferenceKey) != nil {
            return defaults.bool(forKey: activeCloudKitPreferenceKey)
        }
        return defaults.bool(forKey: cloudKitPreferenceKey)
    }

    /// Applies the requested setting before the main app opens the store.
    public nonisolated static func activateCloudKitPreference() {
        guard supportsCloudSync else { return }
        let defaults = SagePreferences.defaults
        let requestedValue = !defaults.bool(forKey: pendingCloudDeletionKey) && defaults.bool(forKey: cloudKitPreferenceKey)
        defaults.set(requestedValue, forKey: activeCloudKitPreferenceKey)
    }

    public static nonisolated func make(for purpose: Purpose = .app) throws -> ModelContainer {
        UIColorValueTransformer.register()

        let schema = Schema(versionedSchema: SageSchemaV9.self)
        let config = try configuration(for: purpose, schema: schema)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: SageSchemaMigrationPlan.self,
            configurations: [config]
        )

        if case .app = purpose {
            try backfillMultiTags(container)
        }

        return container
    }

    // The shared store result. Callers handle a failed store open instead of terminating.
    @MainActor
    public static let shared: Result<ModelContainer, any Swift.Error> = Result {
        try make(for: .app)
    }

    private static nonisolated func configuration(
        for purpose: Purpose,
        schema: Schema
    ) throws -> ModelConfiguration {
        switch purpose {
        case .test, .preview, .previewEmpty:
            return ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        case .app:
            return try appConfiguration(schema: schema)
        }
    }

    private static nonisolated func appConfiguration(schema: Schema) throws -> ModelConfiguration {
        guard let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw Error.appGroupUnavailable
        }

        #if DEBUG
        return ModelConfiguration(
            "SageDev",
            schema: schema,
            url: groupURL.appending(path: "SageDev.sqlite"),
            cloudKitDatabase: .none
        )
        #else
        let storeURL = groupURL.appending(path: "Sage.sqlite")
        return ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: isCloudKitEnabled ? .automatic : .none
        )
        #endif
    }

    // Migrates legacy single-tag data into the V3 `tags` array.
    static nonisolated func backfillMultiTags(_ container: ModelContainer) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let expenses = try context.fetch(FetchDescriptor<Expense>())
        for expense in expenses {
            if let legacyTag = expense.tag {
                if (expense.tags ?? []).isEmpty {
                    expense.tags = [legacyTag]
                }
                expense.tag = nil
            }
        }

        let rules = try context.fetch(FetchDescriptor<RecurringExpenseRule>())
        for rule in rules {
            if let legacyTag = rule.tag {
                if (rule.tags ?? []).isEmpty {
                    rule.tags = [legacyTag]
                }
                rule.tag = nil
            }
        }

        // Conversion and consumption are one transaction. An explicit modern selection
        // wins; consuming its stale legacy value also prevents later tag resurrection.
        // No global flag: legacy-only records arriving later still need conversion.
        // Older clients can write `tag` again via CloudKit; without a per-record
        // synchronized tombstone we cannot distinguish that from a late legacy record.
        if context.hasChanges {
            try context.save()
        }
    }
}
