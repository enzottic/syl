//
//  ExpenseList.swift
//  FinanceTracker
//
//  Created by Enzo on 10/4/25.
//

import SwiftUI
import SwiftData
import WidgetKit
import SageKit

struct ExpenseList: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var appRouter
    @Environment(\.recurringReminders) private var reminders
    @Query private var recurringRules: [RecurringExpenseRule]

    let expenses: [Expense]
    var rowStyle: ExpenseRowItem.Style = .regular
    var onRowHeightChange: ((PersistentIdentifier, CGFloat) -> Void)? = nil

    @State private var expenseToDelete: Expense? = nil
    @State private var showingDeleteConfirmation: Bool = false
    @State private var deleteErrorMessage: String?
    /// Hides a row while SwiftData removes it from the parent query. Its
    /// persistent identifier is safe to read after model detachment.
    @State private var deletingExpenseIDs: Set<PersistentIdentifier> = []

    private var visibleExpenses: [Expense] {
        expenses.filter { !deletingExpenseIDs.contains($0.persistentModelID) }
    }

    private var recurringRuleToDelete: RecurringExpenseRule? {
        guard let ruleID = expenseToDelete?.recurringExpenseId else { return nil }
        return recurringRules.first { $0.id == ruleID }
    }

    var body: some View {
        Group {
            ForEach(visibleExpenses) { expense in
                NavigationLink(value: AppRoute.expenseDetail(expense)) {
                    ExpenseRowItem(expense: expense, style: rowStyle)
                        .onGeometryChange(for: CGFloat.self) { geometry in
                            geometry.size.height
                        } action: { height in
                            onRowHeightChange?(expense.persistentModelID, height)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("expense-row-\(expense.name)")
                .swipeActions {
                    Button("Delete") {
                        expenseToDelete = expense
                        showingDeleteConfirmation = true
                    }
                    .tint(.red)
                    .accessibilityIdentifier("delete-expense-action")

                    Button("Duplicate") {
                        appRouter.presentSheet(.addExpense(expense))
                    }
                    .accessibilityIdentifier("duplicate-expense-action")
                }
            }
        }
        .alert("Delete Expense?", isPresented: $showingDeleteConfirmation, actions: {
            Button(recurringRuleToDelete == nil ? "Delete" : "Delete Expense Only", role: .destructive) {
                if let expense = expenseToDelete {
                    deleteExpense(expense)
                }
            }
            .accessibilityIdentifier("confirm-delete-expense-button")
            if let rule = recurringRuleToDelete {
                Button("Delete Expense and Rule", role: .destructive) {
                    if let expense = expenseToDelete {
                        deleteExpense(expense, recurringRule: rule)
                    }
                }
                .accessibilityIdentifier("confirm-delete-expense-and-rule-button")
            }
            Button("Cancel", role: .cancel) {
                expenseToDelete = nil
            }
        }, message: {
            if recurringRuleToDelete != nil {
                Text("This expense is recurring. Delete its recurring rule to stop future expenses. Previous expenses will not be deleted.")
            }
        })
        .alert("Could not delete expense", isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "Please try again.")
        }
    }
    
    private func deleteExpense(_ expense: Expense, recurringRule: RecurringExpenseRule? = nil) {
        let expenseID = expense.persistentModelID

        // Do not keep a deleted SwiftData model in view state. SwiftUI can
        // otherwise update the row after its attribute faults are removed.
        expenseToDelete = nil
        withAnimation {
            _ = deletingExpenseIDs.insert(expenseID)
        }
        modelContext.delete(expense)
        if let recurringRule {
            modelContext.delete(recurringRule)
        }

        do {
            try modelContext.save()
            if recurringRule != nil {
                reminders?.refresh()
            }
            WidgetCenter.shared.reloadAllTimelines()
            appRouter.showToast(SageToast(
                message: recurringRule == nil ? "Expense deleted" : "Expense and recurring rule deleted",
                kind: .success
            ))
        } catch {
            modelContext.rollback()
            withAnimation {
                _ = deletingExpenseIDs.remove(expenseID)
            }
            deleteErrorMessage = error.localizedDescription
        }
    }
}

#Preview {
    @Previewable @State var fixture = {
        let container = try! SageModelContainer.make(for: .previewEmpty)
        let expenses = [
            Expense(name: "Car Insurance", amount: 123.43, category: .needs, tag: .billsAndUtils),
            Expense(name: "Coffee", amount: 6.50, tag: .dining),
        ]
        expenses.forEach { container.mainContext.insert($0) }
        try! container.mainContext.save()
        return (container: container, expenses: expenses)
    }()

    NavigationStack {
        List {
            ExpenseList(expenses: fixture.expenses)
        }
    }
    .environmentInjection(container: fixture.container)
}
