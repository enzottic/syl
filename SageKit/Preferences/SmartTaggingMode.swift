//
//  SmartTaggingMode.swift
//  SageKit
//

import Foundation

public enum SmartTaggingMode: String, CaseIterable, Sendable {
    case history = "History"
    case ai = "AI"
    case both = "History + AI"
    case none = "None"

    public static let storageKey = "smartTaggingMode"

    public static func stored(in defaults: UserDefaults) -> SmartTaggingMode? {
        defaults.string(forKey: storageKey).flatMap(SmartTaggingMode.init(rawValue:))
    }
}
