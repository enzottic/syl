//
//  ExpenseTag.swift
//  FinanceTracker
//
//  Created by Enzo on 3/7/26.
//
import Foundation
import SwiftUI
import SwiftData

public extension ExpenseTag {
    /// Templates shown during onboarding. Each call produces fresh instances with new UUIDs —
    /// they are only inserted into the store if the user selects them.
    static var suggestedTags: [ExpenseTag] {
        [
            ExpenseTag(name: "Shopping",          uiColor: .systemYellow, emoji: "🛍️", symbolName: "bag.fill"),
            ExpenseTag(name: "Dining",            uiColor: .systemOrange, emoji: "🍽️", symbolName: "fork.knife"),
            ExpenseTag(name: "Entertainment",     uiColor: .systemPink,   emoji: "🍿", symbolName: "film.fill"),
            ExpenseTag(name: "Bills & Utilities", uiColor: .systemBlue,   emoji: "🏠", symbolName: "house.fill"),
            ExpenseTag(name: "Groceries",         uiColor: .systemGreen,  emoji: "🥗", symbolName: "basket.fill"),
            ExpenseTag(name: "Subscriptions",     uiColor: .systemTeal,   emoji: "💻", symbolName: "play.rectangle.fill"),
            ExpenseTag(name: "Travel",            uiColor: .systemPurple, emoji: "✈️", symbolName: "airplane"),
            ExpenseTag(name: "Other",             uiColor: .systemGray,   emoji: "🔖", symbolName: "ellipsis.circle.fill"),
        ]
    }

    // Preview-only convenience instances.
    static var shopping: ExpenseTag      { .init(name: "Shopping",          uiColor: .systemYellow, emoji: "🛍️", symbolName: "bag.fill") }
    static var dining: ExpenseTag        { .init(name: "Dining",            uiColor: .systemOrange, emoji: "🍽️", symbolName: "fork.knife") }
    static var entertainment: ExpenseTag { .init(name: "Entertainment",     uiColor: .systemPink,   emoji: "🍿", symbolName: "film.fill") }
    static var billsAndUtils: ExpenseTag { .init(name: "Bills & Utilities", uiColor: .systemBlue,   emoji: "🏠", symbolName: "house.fill") }
    static var groceries: ExpenseTag     { .init(name: "Groceries",         uiColor: .systemGreen,  emoji: "🥗", symbolName: "basket.fill") }
    static var subscriptions: ExpenseTag { .init(name: "Subscriptions",     uiColor: .systemTeal,   emoji: "💻", symbolName: "play.rectangle.fill") }
    static var travel: ExpenseTag        { .init(name: "Travel",            uiColor: .systemPurple, emoji: "✈️", symbolName: "airplane") }
    static var other: ExpenseTag         { .init(name: "Other",             uiColor: .systemGray,   emoji: "🔖", symbolName: "ellipsis.circle.fill") }
    
    var entity: ExpenseTagEntity {
        ExpenseTagEntity(id: self.id, name: self.name, emoji: self.emoji, symbolName: self.symbolName)
    }
}
