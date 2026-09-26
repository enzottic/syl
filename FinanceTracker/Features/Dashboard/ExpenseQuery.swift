import Foundation
import SwiftUI
import SwiftData
import SageKit

func expenseQuery(for month: Date, limit: Int? = nil) -> Query<Expense, [Expense]> {
    var descriptor = ExpenseFetchDescriptors.month(month)
    descriptor.fetchLimit = limit
    return Query(descriptor)
}

func expenseQuery(start: Date, end: Date, limit: Int? = nil) -> Query<Expense, [Expense]> {
    var descriptor = ExpenseFetchDescriptors.range(start: start, end: end)
    descriptor.fetchLimit = limit
    return Query(descriptor)
}
