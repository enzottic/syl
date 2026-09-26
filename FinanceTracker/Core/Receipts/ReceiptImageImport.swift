//
//  ReceiptImageImport.swift
//  SageKit
//

import Foundation
import ImageIO

public nonisolated enum ReceiptImageImport {
    public enum Error: LocalizedError {
        case unsupportedURL
        case invalidImage

        public var errorDescription: String? {
            switch self {
            case .unsupportedURL:
                "Syl can only import receipt files from this action."
            case .invalidImage:
                "The selected file is not a valid image."
            }
        }
    }

    public static func loadData(from url: URL) throws -> Data {
        guard url.isFileURL else { throw Error.unsupportedURL }

        let hasSecurityScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
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
}
