import SwiftUI

enum SettingsPage: String, Hashable, CaseIterable {
    case appearance = "Appearance"
    case budget = "Budget and Allocation"
    case recurringExpenses = "Recurring Expenses"
    case notifications = "Notifications"
    case tags = "Tags"
    case backup = "Backup"
    case privacy = "Privacy"

    var icon: String {
        switch self {
        case .appearance: "paintpalette.fill"
        case .budget: "chart.bar.horizontal.page.fill"
        case .recurringExpenses: "arrow.trianglehead.clockwise"
        case .notifications: "bell.fill"
        case .tags: "tag.fill"
        case .backup: "cloud.fill"
        case .privacy: "hand.raised.fill"
        }
    }

    var color: Color {
        switch self {
        case .appearance: .sage
        case .budget: .green
        case .tags: .purple
        case .recurringExpenses: .orange
        case .notifications: .sage
        case .backup: .blue
        case .privacy: .red
        }
    }
}
