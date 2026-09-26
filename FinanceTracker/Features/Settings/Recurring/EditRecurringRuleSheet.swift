//
//  EditRecurringRuleSheet.swift
//  FinanceTracker
//
import SwiftUI
import SwiftData
import WidgetKit
import SageKit

struct EditRecurringRuleSheet: View {
    @Environment(AppConfiguration.self) private var config
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let rule: RecurringExpenseRule

    @State private var name: String
    @State private var amount: Double?
    @State private var note: String
    @State private var category: ExpenseCategory
    @State private var tags: [ExpenseTag]
    @State private var startDate: Date
    @State private var frequency: RecurrenceFrequency
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var showScheduleConfirmation = false

    @State private var showError = false
    @State private var errorMessage: String?
    @State private var showDiscardConfirmation = false

    init(rule: RecurringExpenseRule) {
        self.rule = rule
        _name = State(initialValue: rule.name)
        _amount = State(initialValue: rule.amount)
        _note = State(initialValue: rule.note)
        _category = State(initialValue: rule.category)
        _tags = State(initialValue: rule.tags ?? [])
        _startDate = State(initialValue: rule.startDate)
        _frequency = State(initialValue: rule.frequency)
        _hasEndDate = State(initialValue: rule.endDate != nil)
        _endDate = State(initialValue: rule.endDate ?? Calendar.current.date(byAdding: .month, value: 1, to: Date.now) ?? Date.now)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ExpenseInfoForm(
                        name: $name,
                        amount: $amount,
                        date: $startDate,
                        category: $category,
                        tags: $tags,
                        note: $note
                    )

                    Divider()
                        .padding(.horizontal)

                    VStack(spacing: 12) {
                        Text("Date sets the schedule’s start and repeating day. Changing it or the frequency updates future occurrences only. End date changes only limit when generation stops; extending it allows catch-up on the current schedule.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("Frequency")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("Frequency", selection: $frequency) {
                                ForEach(RecurrenceFrequency.allCases, id: \.self) { freq in
                                    Text(freq.rawValue).tag(freq)
                                }
                            }
                            .pickerStyle(.menu)
                            .accessibilityIdentifier("recurring-frequency-picker")
                            .tint(.primary)
                        }

                        Toggle(isOn: $hasEndDate) {
                            Text("End Date")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if hasEndDate {
                            DatePicker(
                                "Ends on",
                                selection: $endDate,
                                in: startDate...,
                                displayedComponents: .date
                            )
                            .font(.subheadline)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .animation(reduceMotion ? nil : .default, value: hasEndDate)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { requestDismissal() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveChanges() }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unexpected error occurred")
            }
            .confirmationDialog("Update Future Schedule?", isPresented: $showScheduleConfirmation, titleVisibility: .visible) {
                Button("Update Future Schedule") { saveChanges(scheduleConfirmed: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                if frequency == .monthly {
                    Text("Existing expenses stay unchanged. Monthly expenses resume after this month or the latest recorded month, whichever is later. A later start date is kept. No past expenses will be added.")
                } else {
                    Text("Existing expenses stay unchanged. The schedule repeats from the selected start date, beginning after today or the latest recorded expense, whichever is later. No past expenses will be added.")
                }
            }
            .confirmationDialog("Discard changes?", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                    .accessibilityIdentifier("discard-recurring-rule-button")
                Button("Keep Editing", role: .cancel) {}
                    .accessibilityIdentifier("keep-editing-recurring-rule-button")
            } message: {
                Text("Your unsaved recurring expense changes will be lost.")
            }
        }
        .interactiveDismissDisabled(hasChanges)
    }

    private var changesAnchor: Bool {
        startDate != rule.startDate || frequency != rule.frequency
    }

    private var hasChanges: Bool {
        name != rule.name || amount != rule.amount || note != rule.note || category != rule.category
            || tags.map(\.persistentModelID) != (rule.tags ?? []).map(\.persistentModelID)
            || startDate != rule.startDate || frequency != rule.frequency || hasEndDate != (rule.endDate != nil)
            || (hasEndDate && endDate != rule.endDate)
    }

    private func requestDismissal() {
        if hasChanges { showDiscardConfirmation = true } else { dismiss() }
    }

    private func saveChanges(scheduleConfirmed: Bool = false) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter an expense name"
            showError = true
            return
        }
        let currencyCode = config.ledgerCurrencyCode
        guard let expenseAmount = amount,
              expenseAmount == rule.amount || MonetaryAmount.isValid(expenseAmount, currencyCode: currencyCode, requiresPositive: true) else {
            errorMessage = MonetaryAmount.validationMessage(currencyCode: currencyCode, requiresPositive: true)
            showError = true
            return
        }

        guard !hasEndDate || endDate >= startDate else {
            errorMessage = "End date must be on or after the start date."
            showError = true
            return
        }

        let changesSchedule = changesAnchor
        if changesSchedule && !scheduleConfirmed {
            showScheduleConfirmation = true
            return
        }

        // Fetch before mutating the rule; confirmation alone must not persist any changes.
        let existingExpenses: [Expense]
        do {
            if changesSchedule {
                existingExpenses = try modelContext.fetch(FetchDescriptor<Expense>())
            } else {
                existingExpenses = []
            }
        } catch {
            errorMessage = "Could not check existing occurrences: \(error.localizedDescription)"
            showError = true
            return
        }
        do {
            if changesSchedule {
                try rule.editSchedule(startDate: startDate, frequency: frequency,
                                      endDate: hasEndDate ? endDate : nil,
                                      in: .current, after: .now, existingExpenses: existingExpenses)
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            return
        }

        rule.name = name
        rule.amount = expenseAmount
        rule.note = note
        rule.category = category
        rule.tags = tags
        rule.endDate = hasEndDate ? endDate : nil

        do {
            try modelContext.save()
            WidgetCenter.shared.reloadAllTimelines()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = "Failed to save: \(error.localizedDescription)"
            showError = true
        }
    }
}
