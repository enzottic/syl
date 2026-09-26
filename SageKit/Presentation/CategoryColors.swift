//
//  CategoryColors.swift
//  FinanceTracker
//

import SwiftUI

public struct CategoryColors: Equatable {
    public var needs: Color
    public var wants: Color
    public var savings: Color
    
    public init(needs: Color, wants: Color, savings: Color) {
        self.needs = needs
        self.wants = wants
        self.savings = savings
    }

    public static let `default` = CategoryColors(
        needs: Color("NeedColor"),
        wants: Color("WantColor"),
        savings: Color("SavingColor")
    )

    public static func load() -> CategoryColors {
        let defaults = SagePreferences.defaults
        return CategoryColors(
            needs: defaults.sageColor(forKey: "categoryColorNeeds") ?? Color("NeedColor"),
            wants: defaults.sageColor(forKey: "categoryColorWants") ?? Color("WantColor"),
            savings: defaults.sageColor(forKey: "categoryColorSavings") ?? Color("SavingColor")
        )
    }

    public func color(for category: ExpenseCategory) -> Color {
        switch category {
        case .needs: return needs
        case .wants: return wants
        case .savings: return savings
        }
    }
}

private struct CategoryColorsKey: EnvironmentKey {
    static let defaultValue = CategoryColors.default
}

public extension EnvironmentValues {
    var categoryColors: CategoryColors {
        get { self[CategoryColorsKey.self] }
        set { self[CategoryColorsKey.self] = newValue }
    }
}
