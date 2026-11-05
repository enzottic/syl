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
    func removesInboxCopiesButNotOtherFiles() throws {
        let imageData = try #require(
            UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { _ in }.pngData()
        )
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let inbox = root.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let inboxCopy = inbox.appendingPathComponent("receipt.png")
        let original = root.appendingPathComponent("receipt.png")
        let invalidCopy = inbox.appendingPathComponent("broken.png")
        try imageData.write(to: inboxCopy)
        try imageData.write(to: original)
        try Data("not an image".utf8).write(to: invalidCopy)

        _ = try ReceiptImageImport.loadData(from: inboxCopy, inboxDirectory: inbox)
        _ = try ReceiptImageImport.loadData(from: original, inboxDirectory: inbox)
        _ = try? ReceiptImageImport.loadData(from: invalidCopy, inboxDirectory: inbox)

        #expect(!FileManager.default.fileExists(atPath: inboxCopy.path))
        #expect(!FileManager.default.fileExists(atPath: invalidCopy.path))
        #expect(FileManager.default.fileExists(atPath: original.path))
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
