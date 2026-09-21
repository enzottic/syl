//
//  WidgetConfigurationIntents.swift
//  FinanceTracker
//

import AppIntents
import WidgetKit

public struct CategorySpotlightAppIntent: WidgetConfigurationIntent {
    public static var title: LocalizedStringResource { "Category Spotlight" }
    public static var description = IntentDescription("Choose a budget category to spotlight.")
    public static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Category", default: .needs)
    public var category: ExpenseCategory
    
    public init() { }
}
