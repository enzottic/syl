//
//  ExpenseTag+Templates.swift
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
}
