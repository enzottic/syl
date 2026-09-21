//
//  UITestConfiguration.swift
//  FinanceTracker
//
//  Created by Enzo on 8/17/26.
//
import Foundation

enum UITestConfiguration {
    private static let environment = ProcessInfo.processInfo.environment

    static var isEnabled: Bool { environment["SAGE_UI_TESTING"] == "1" }
    static var showsOnboarding: Bool { environment["SAGE_UI_TEST_ONBOARDING"] == "1" }
    static var seedsSearch: Bool { environment["SAGE_UI_TEST_SEED_SEARCH"] == "1" }
    static var seedsCalendar: Bool { environment["SAGE_UI_TEST_SEED_CALENDAR"] == "1" }
    static var seedExpenseName: String? { environment["SAGE_UI_TEST_SEED_EXPENSE"] }
}
