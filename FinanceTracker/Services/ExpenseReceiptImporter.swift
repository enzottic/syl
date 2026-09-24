import Foundation
import FoundationModels
import Observation
import PhotosUI
import SwiftUI
import SageKit
import UIKit

@available(iOS 26.0, *)
@Observable
@MainActor
final class ExpenseReceiptImporter {
    private(set) var isImporting = false
    var errorMessage: String?

    var unavailableMessage: String? {
        SystemLanguageModel.default.isAvailable
            ? nil
            : "Receipt reading requires Apple Intelligence on this device."
    }

    var canUseCamera: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    /// Returns receipt details for the caller to apply to its draft.
    /// Concurrent starts and cancelled imports return nil without reporting an error.
    func importPhoto(_ item: PhotosPickerItem, tags: [ExpenseTag]) async -> ParsedExpense? {
        guard beginImport() else { return nil }
        defer { isImporting = false }

        let image: UIImage
        do {
            let data = try await item.loadTransferable(type: Data.self)
            try Task.checkCancellation()

            guard let data, let loadedImage = UIImage(data: data) else {
                errorMessage = "Syl couldn't open that photo."
                return nil
            }
            image = loadedImage
        } catch is CancellationError {
            return nil
        } catch {
            guard !Task.isCancelled else { return nil }
            errorMessage = "Syl couldn't open that photo. Choose another photo and try again."
            return nil
        }

        return await parse(image, tags: tags)
    }

    func importImage(_ image: UIImage, tags: [ExpenseTag]) async -> ParsedExpense? {
        guard beginImport() else { return nil }
        defer { isImporting = false }

        return await parse(image, tags: tags)
    }

    /// Imports initial receipt data supplied by a share or file action.
    func importData(_ data: Data, tags: [ExpenseTag]) async -> ParsedExpense? {
        guard beginImport() else { return nil }
        defer { isImporting = false }

        guard let image = UIImage(data: data) else {
            guard !Task.isCancelled else { return nil }
            errorMessage = "Syl couldn't open the shared receipt."
            return nil
        }

        return await parse(image, tags: tags)
    }

    private func beginImport() -> Bool {
        guard !isImporting, !Task.isCancelled else { return false }

        errorMessage = nil
        if let unavailableMessage {
            errorMessage = unavailableMessage
            return false
        }

        // Claim the entire operation before the first suspension, including photo loading.
        isImporting = true
        return true
    }

    private func parse(_ image: UIImage, tags: [ExpenseTag]) async -> ParsedExpense? {
        do {
            try Task.checkCancellation()
            let parsed = try await ReceiptParserService().parseReceipt(image: image, tags: tags)
            try Task.checkCancellation()
            return parsed
        } catch is CancellationError {
            return nil
        } catch {
            // The parser may wrap a cancellation in ReceiptParserError.
            guard !Task.isCancelled else { return nil }
            if let receiptError = error as? ReceiptParserError {
                errorMessage = receiptError.localizedDescription
            } else {
                errorMessage = "Syl couldn't read this receipt. Try again later."
            }
            return nil
        }
    }
}
