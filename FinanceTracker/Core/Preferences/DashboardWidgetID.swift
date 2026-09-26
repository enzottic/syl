import Foundation
import UIKit

/// Stable preference identifiers, independent of a widget's rendering style.
enum DashboardWidgetID: String, CaseIterable, Identifiable {
    case monthlyOverview, categories, expenseCalendar
    case mostSpentTags, upcomingRecurring, recentExpenses

    var id: String { rawValue }

    static var defaultOrder: [Self] {
        defaultOrder(isPad: UIDevice.current.userInterfaceIdiom == .pad)
    }

    static func defaultOrder(isPad: Bool) -> [Self] {
        isPad
            ? [.monthlyOverview, .categories, .expenseCalendar,
               .recentExpenses, .mostSpentTags, .upcomingRecurring]
            : allCases
    }

    static func resolvedOrder(_ saved: [String], defaultOrder: [Self] = Self.defaultOrder) -> [Self] {
        var seen = Set<Self>()
        // Collapse previously separate categories at their first saved position.
        let migrated = saved.compactMap { value -> Self? in
            switch value {
            case "needs", "wants", "savings": .categories
            default: Self(rawValue: value)
            }
        }
        return (migrated + defaultOrder)
            .filter { seen.insert($0).inserted }
    }
}
