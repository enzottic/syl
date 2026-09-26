//
//  EditExpenseView.swift
//  FinanceTracker
//
//  Created by Enzo on 10/11/25.
//
import SwiftUI
import SwiftData
import WidgetKit
import SageKit

struct EditExpenseView: View {
    @Environment(AppConfiguration.self) private var config
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext
    @Environment(AppRouter.self) private var appRouter
    @Environment(\.recurringReminders) private var reminders
    @Query private var recurringRules: [RecurringExpenseRule]
    
    let expense: Expense
    
    @State private var workingExpense: EditableExpense
    @State private var showingDeleteConfirmation: Bool = false
    @State private var saveErrorMessage: String?
    @State private var isSaving = false
    @State private var showingRecurringRuleConfirmation = false
    @State private var showDiscardConfirmation = false
    @State private var discardAction: (() -> Void)?

    private var recurringRule: RecurringExpenseRule? {
        guard let ruleID = expense.recurringExpenseId else { return nil }
        return recurringRules.first { $0.id == ruleID }
    }

    init(expense: Expense) {
        self.expense = expense
        _workingExpense = State(initialValue: EditableExpense(
            name: expense.name,
            amount: expense.amount,
            date: expense.date,
            category: expense.category,
            tags: expense.tags ?? [],
            note: expense.note
        ))
    }
    
    var body: some View {
        ScrollView {
            ExpenseInfoForm(
                name: $workingExpense.name,
                amount: $workingExpense.amount,
                date: $workingExpense.date,
                category: $workingExpense.category,
                tags: $workingExpense.tags,
                note: $workingExpense.note
            )
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
        .background(.sageBackground)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Edit Expense")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back") { requestDismissal { dismiss() } }
                    .accessibilityIdentifier("back-expense-button")
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Saving expense")
                } else {
                    Button("Save") {
                        Task { await saveItem() }
                    }
                    .accessibilityIdentifier("save-expense-changes-button")
                    .tint(.sageTint)
                    .disabled(isSaving)
                }
            }
        }
        .alert("Update Recurring Rule?", isPresented: $showingRecurringRuleConfirmation) {
            Button("Update Expense Only") {
                Task { await saveItem(updateRecurringRule: false) }
            }
            .accessibilityIdentifier("save-expense-only-button")
            Button("Update Expense and Rule") {
                Task { await saveItem(updateRecurringRule: true) }
            }
            .accessibilityIdentifier("save-expense-and-rule-button")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Future expenses will use these details. The schedule and other existing expenses will stay unchanged.")
        }
        .alert("Could not save expense", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "Please try again.")
        }
        .confirmationDialog("Discard changes?", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) {
                let action = discardAction
                discardAction = nil
                action?()
            }
            .accessibilityIdentifier("discard-expense-changes-button")
            Button("Keep Editing", role: .cancel) {}
                .accessibilityIdentifier("keep-editing-expense-changes-button")
        } message: {
            Text("Your unsaved expense changes will be lost.")
        }
        .onAppear {
            appRouter.expenseDraftNavigationHandler = { month in
                requestDismissal { appRouter.completeShowExpenses(for: month) }
            }
        }
        .onDisappear {
            appRouter.expenseDraftNavigationHandler = nil
        }
        .gradientBackground()
    }

    private var hasChanges: Bool {
        workingExpense.name != expense.name
            || workingExpense.amount != expense.amount
            || workingExpense.date != expense.date
            || workingExpense.category != expense.category
            || workingExpense.note != expense.note
            || workingExpense.tags.map(\.persistentModelID) != (expense.tags ?? []).map(\.persistentModelID)
    }

    private func requestDismissal(_ action: @escaping () -> Void) {
        guard hasChanges else {
            action()
            return
        }
        discardAction = action
        showDiscardConfirmation = true
    }
    
    private func saveItem(updateRecurringRule: Bool? = nil) async {
        guard !isSaving else { return }
        let currencyCode = config.ledgerCurrencyCode

        let trimmedName = workingExpense.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            saveErrorMessage = "Enter an expense name."
            return
        }

        guard let amount = workingExpense.amount,
              amount == expense.amount || MonetaryAmount.isValid(amount, currencyCode: currencyCode) else {
            saveErrorMessage = "Correct the changed amount before saving. "
                + MonetaryAmount.validationMessage(currencyCode: currencyCode)
            return
        }

        if updateRecurringRule == nil, recurringRule != nil {
            showingRecurringRuleConfirmation = true
            return
        }

        let ruleToUpdate = updateRecurringRule == true ? recurringRule : nil
        if let ruleToUpdate, amount != ruleToUpdate.amount,
           !MonetaryAmount.isValid(amount, currencyCode: currencyCode, requiresPositive: true) {
            saveErrorMessage = MonetaryAmount.validationMessage(currencyCode: currencyCode, requiresPositive: true)
            return
        }

        isSaving = true
        defer { isSaving = false }

        await Task.yield()

        expense.name = trimmedName
        expense.amount = amount
        expense.date = workingExpense.date
        expense.category = workingExpense.category
        expense.tags = workingExpense.tags
        expense.note = workingExpense.note
        if let rule = ruleToUpdate {
            rule.name = trimmedName
            rule.amount = amount
            rule.category = workingExpense.category
            rule.tags = workingExpense.tags
            rule.note = workingExpense.note
        }
        do {
            try modelContext.save()
            if ruleToUpdate != nil {
                reminders?.refresh()
            }
            WidgetCenter.shared.reloadAllTimelines()
            dismiss()
            appRouter.showToast(SageToast(
                message: ruleToUpdate == nil ? "Expense updated" : "Expense and recurring rule updated",
                kind: .success
            ))
        } catch {
            modelContext.rollback()
            saveErrorMessage = "Syl could not save this expense. Check available storage and try again."
        }
    }
}

private struct EditableExpense {
    var name: String
    var amount: Double?
    var date: Date
    var category: ExpenseCategory
    var tags: [ExpenseTag]
    var note: String
}

#Preview {
    @Previewable @State var fixture = {
        let container = try! SageModelContainer.make(for: .previewEmpty)
        let expense = Expense(
            name: "Car Insurance", amount: 123.43, category: .needs,
            tag: .billsAndUtils, note: "Progressive Insurance"
        )
        container.mainContext.insert(expense)
        try! container.mainContext.save()
        return (container: container, expense: expense)
    }()

    NavigationStack {
        EditExpenseView(expense: fixture.expense)
    }
    .environmentInjection(container: fixture.container)
}
