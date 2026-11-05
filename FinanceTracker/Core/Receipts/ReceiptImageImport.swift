//
//  ReceiptImageImport.swift
//  FinanceTracker
//

import Foundation
import ImageIO

nonisolated enum ReceiptImageImport {
    enum Error: LocalizedError {
        case unsupportedURL
        case invalidImage

        var errorDescription: String? {
            switch self {
            case .unsupportedURL:
                "Syl can only import receipt files from this action."
            case .invalidImage:
                "The selected file is not a valid image."
            }
        }
    }

    /// Where iOS copies files that other apps send to Syl. Files opened in place live elsewhere.
    static var inboxDirectory: URL {
        URL.documentsDirectory.appending(path: "Inbox", directoryHint: .isDirectory)
    }

    static func loadData(from url: URL, inboxDirectory: URL = inboxDirectory) throws -> Data {
        guard url.isFileURL else { throw Error.unsupportedURL }

        let hasSecurityScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
            removeIfInboxCopy(url, inboxDirectory: inboxDirectory)
        }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetCount(source) > 0,
            CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCache: false] as CFDictionary
            ) != nil
        else {
            throw Error.invalidImage
        }

        return data
    }

    /// Syl keeps the receipt's data, so the inbox copy is no longer needed. Never touches
    /// files outside the inbox, which belong to the user.
    private static func removeIfInboxCopy(_ url: URL, inboxDirectory: URL) {
        let inboxPath = inboxDirectory.resolvingSymlinksInPath().path(percentEncoded: false)
        let filePath = url.resolvingSymlinksInPath().path(percentEncoded: false)
        let prefix = inboxPath.hasSuffix("/") ? inboxPath : inboxPath + "/"
        guard filePath.hasPrefix(prefix) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
