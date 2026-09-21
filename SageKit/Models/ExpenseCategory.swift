//
//  ExpenseCategory.swift
//  FinanceTracker
//
//  Created by Enzo on 10/5/25.
//
import SwiftUI
import AppIntents

public enum ExpenseCategory: String, CaseIterable, Codable, AppEnum {
    case needs = "Needs"
    case wants = "Wants"
    case savings = "Savings"

    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Expense Category"

    public static var caseDisplayRepresentations: [ExpenseCategory: DisplayRepresentation] = [
        .needs: "Needs",
        .wants: "Wants",
        .savings: "Savings"
    ]

    public var defaultColor: Color {
        switch self {
        case .needs: return Color("NeedColor")
        case .wants: return Color("WantColor")
        case .savings: return Color("SavingColor")
        }
    }

    public func color(in colors: CategoryColors) -> Color {
        colors.color(for: self)
    }
    
    public var description: String {
        switch self {
        case .needs: "Essentials like bills and groceries."
        case .wants: "Non-essentials like entertainment, dining-out, etc."
        case .savings: "Money set aside to save."
        }
    }
}
