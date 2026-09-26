import Foundation
import Testing
import UIKit
@testable import SageKit

@Suite("Receipt image import")
struct ReceiptImageImportTests {
    @Test
    func loadsImageDataFromFileURL() throws {
        let imageData = try #require(
            UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
                .image { context in
                    UIColor.white.setFill()
                    context.fill(CGRect(origin: .zero, size: CGSize(width: 2, height: 2)))
                }
                .pngData()
        )
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try imageData.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let importedData = try ReceiptImageImport.loadData(from: fileURL)

        #expect(importedData == imageData)
    }

    @Test
    func rejectsInvalidImageData() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try Data("not an image".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        #expect(throws: ReceiptImageImport.Error.invalidImage) {
            try ReceiptImageImport.loadData(from: fileURL)
        }
    }

    @Test
    func rejectsNonFileURL() {
        #expect(throws: ReceiptImageImport.Error.unsupportedURL) {
            try ReceiptImageImport.loadData(from: URL(string: "https://example.com/receipt.png")!)
        }
    }
}
