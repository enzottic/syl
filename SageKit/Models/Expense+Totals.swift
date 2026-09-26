import SwiftData
import Foundation
import SwiftUI

public extension [Expense] {
    var total: Double {
        self.reduce(0) { $0 + $1.amount }
    }
    
    var wantsUsed: Double {
        self.filter { $0.category == .wants }
            .reduce(0) { $0 + $1.amount }
    }
    
    var needsUsed: Double {
        self.filter { $0.category == .needs}
            .reduce(0) { $0 + $1.amount }
    }
    
    var savingsUsed: Double {
        self.filter { $0.category == .savings}
            .reduce(0) { $0 + $1.amount }
    }

    /// Total spent against `tag` within the calendar month containing `month`.
    /// Counts an expense once if it carries the tag, regardless of its category.
    func monthlyTotal(for tag: ExpenseTag, in month: Date = .now, calendar: Calendar = .current) -> Double {
        self.filter { expense in
            calendar.isDate(expense.date, equalTo: month, toGranularity: .month)
                && (expense.tags ?? []).contains { $0.id == tag.id }
        }
        .reduce(0) { $0 + $1.amount }
    }
}
