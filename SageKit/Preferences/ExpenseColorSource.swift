//
//  ExpenseColorSource.swift
//  SageKit
//

import Foundation

/// Which colour an expense's badge uses in lists and widgets.
public enum ExpenseColorSource: String, CaseIterable, Sendable {
    case category = "Category"
    case tag = "Tag"

    public static let storageKey = "expenseColorSource"

    public static func load(from defaults: UserDefaults = SagePreferences.defaults) -> ExpenseColorSource {
        defaults.string(forKey: storageKey).flatMap(ExpenseColorSource.init(rawValue:)) ?? .category
    }
}
