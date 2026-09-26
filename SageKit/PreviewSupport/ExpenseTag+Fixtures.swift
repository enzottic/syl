import Foundation
import SwiftUI
import SwiftData

public extension ExpenseTag {
    // Preview-only convenience instances.
    static var shopping: ExpenseTag      { .init(name: "Shopping",          uiColor: .systemYellow, emoji: "🛍️", symbolName: "bag.fill") }
    static var dining: ExpenseTag        { .init(name: "Dining",            uiColor: .systemOrange, emoji: "🍽️", symbolName: "fork.knife") }
    static var billsAndUtils: ExpenseTag { .init(name: "Bills & Utilities", uiColor: .systemBlue,   emoji: "🏠", symbolName: "house.fill") }
    static var groceries: ExpenseTag     { .init(name: "Groceries",         uiColor: .systemGreen,  emoji: "🥗", symbolName: "basket.fill") }
    static var subscriptions: ExpenseTag { .init(name: "Subscriptions",     uiColor: .systemTeal,   emoji: "💻", symbolName: "play.rectangle.fill") }
}
