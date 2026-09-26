import SwiftData
import Foundation
import SwiftUI

public class SageSchemaMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] = [SageSchemaV1.self, SageSchemaV2.self, SageSchemaV3.self, SageSchemaV4.self, SageSchemaV5.self, SageSchemaV6.self, SageSchemaV7.self, SageSchemaV8.self, SageSchemaV9.self]

    public static var stages: [MigrationStage] = [
        MigrationStage.lightweight(fromVersion: SageSchemaV1.self, toVersion: SageSchemaV2.self),
        MigrationStage.lightweight(fromVersion: SageSchemaV2.self, toVersion: SageSchemaV3.self),
        MigrationStage.lightweight(fromVersion: SageSchemaV3.self, toVersion: SageSchemaV4.self),
        MigrationStage.lightweight(fromVersion: SageSchemaV4.self, toVersion: SageSchemaV5.self),
        MigrationStage.lightweight(fromVersion: SageSchemaV5.self, toVersion: SageSchemaV6.self),
        MigrationStage.custom(fromVersion: SageSchemaV6.self, toVersion: SageSchemaV7.self, willMigrate: nil) { context in
            let expenses = try context.fetch(FetchDescriptor<SageSchemaV7.Expense>(
                predicate: #Predicate { $0.recurringExpenseId != nil }
            ))
            for expense in expenses {
                expense.backfillRecurringScheduledDate()
            }
            try context.save()
        },
        MigrationStage.lightweight(fromVersion: SageSchemaV7.self, toVersion: SageSchemaV8.self),
        MigrationStage.lightweight(fromVersion: SageSchemaV8.self, toVersion: SageSchemaV9.self)
    ]
}
