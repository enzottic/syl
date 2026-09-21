//
//  AddExpenseShortcut.swift
//  FinanceTracker
//
//  Created by Enzo on 10/4/25.
//

import Foundation
import AppIntents

// Keep shortcut phrases in the same module as their intents and parameter types
// so App Intents training can resolve enum and entity vocabulary.
public struct SageShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] = [
        AppShortcut(
            intent: AddExpenseAppIntent(),
            phrases: [
                "Add a new expense to ${applicationName}",
                "Add an expense to ${applicationName}",
                "Create a new ${applicationName} expense",
                "Add expense in ${applicationName}",
                "Create a new expense in ${applicationName}",
                "Ask ${applicationName} to add a new expense",
                "Ask ${applicationName} to add an expense",
            ],
            shortTitle: "Add Expense",
            systemImageName: "dollarsign"
        ),
        AppShortcut(
            intent: GetMonthlySpendingTotalIntent(),
            phrases: [
                "Get my monthly total in ${applicationName}",
                "${applicationName} monthly total",
                "Get my monthly total for \(\.$category) in ${applicationName}",
                "Get my monthly total for \(\.$tag) in ${applicationName}",
            ],
            shortTitle: "Monthly Spending Total",
            systemImageName: "sum"
        ),
        AppShortcut(
            intent: GetBudgetRemainingIntent(),
            phrases: [
                "Get my remaining budget in ${applicationName}",
                "${applicationName} remaining budget",
                "Get my \(\.$category) budget in ${applicationName}",
                "Get my remaining budget for \(\.$category) in ${applicationName}",
            ],
            shortTitle: "Budget Remaining",
            systemImageName: "creditcard"
        ),
        AppShortcut(
            intent: FindExpensesIntent(),
            phrases: [
                "Get my expense total in ${applicationName}",
                "${applicationName} expense total",
                "Get my expense total for \(\.$timePeriod) in ${applicationName}",
                "Get my expense total for \(\.$category) in ${applicationName}",
                "Get my expense total for \(\.$tag) in ${applicationName}",
            ],
            shortTitle: "Find Expenses",
            systemImageName: "magnifyingglass"
        ),
    ]
}
