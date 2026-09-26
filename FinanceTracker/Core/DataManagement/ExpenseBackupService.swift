import Foundation
import SwiftData
import SageKit

final class ExpenseBackupService: Sendable {
    static let shared = ExpenseBackupService()

    @MainActor func createBackup(modelContainer: ModelContainer, currencyCode: String) async throws -> URL {
        let snapshot = try ExpenseBackupCodec.snapshot(modelContainer: modelContainer, currency: currencyCode)
        
        return try await Task.detached(priority: .userInitiated) {
            try Self.write(ExpenseBackupCodec.encode(snapshot), extension: "json")
        }.value
    }

    @MainActor func exportCSV(modelContainer: ModelContainer, currencyCode: String) async throws -> URL {
        let reader = ModelContext(modelContainer)
        reader.autosaveEnabled = false
        
        let snapshot = try reader.fetch(FetchDescriptor<Expense>()).toExportable()
        
        return try await Task.detached(priority: .userInitiated) {
            try Self.write(Data(ExpenseCSVCodec.encode(snapshot, currencyCode: currencyCode).utf8), extension: "csv")
        }.value
    }

    func readExpenses(from url: URL) async throws -> ExpenseImportSource {
        try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: url)
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
            
            // A malformed JSON document must never be retried as a legacy CSV.
            if url.pathExtension.lowercased() == "json" || text.first == "{" || text.first == "[" {
                return .backup(try ExpenseBackupCodec.decode(Data(text.utf8)))
            }
            
            guard let csv = String(data: data, encoding: .utf8) else {
                throw ExpenseBackupError.invalid("the file is not UTF-8 text.")
            }
            
            return .csv(try ExpenseCSVCodec.decode(csv))
        }.value
    }

    nonisolated private static func write(_ data: Data, extension suffix: String) throws -> URL {
        // Temporary share files are not a second permanent, app-owned financial archive.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("syl-expenses-\(UUID().uuidString.lowercased()).\(suffix)")
        
        try data.write(to: url, options: .atomic)
        
        return url
    }
}

extension [Expense] {
    func toExportable() -> [ExportableExpense] {
        map {
            let tags = ($0.tags?.isEmpty == false ? $0.tags : $0.tag.map { [$0] }) ?? []
            return ExportableExpense(
                name: $0.name,
                date: $0.date,
                amount: $0.amount,
                category: $0.category.rawValue,
                tag: tags.map(\.name).joined(separator: "|"),
                note: $0.note
            )
        }
    }
}
