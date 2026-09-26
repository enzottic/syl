//
//  RecurringRulesSection.swift
//  FinanceTracker
//
import SwiftUI
import SwiftData
import SageKit

struct RecurringExpensesSettingsSection: View {
    @Environment(AppRouter.self) var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.recurringReminders) private var reminders

    @Query private var rules: [RecurringExpenseRule]

    private var sortedRules: [RecurringExpenseRule] {
        rules.sorted {
            let a = $0.nextOccurrence() ?? .distantFuture
            let b = $1.nextOccurrence() ?? .distantFuture
            return a < b
        }
    }

    @State private var ruleToEdit: RecurringExpenseRule? = nil
    @State private var ruleToDelete: RecurringExpenseRule? = nil
    @State private var showDeleteConfirmation = false

    var body: some View {
        List {
            if rules.isEmpty {
                ContentUnavailableView(
                    "No Recurring Expense Rules",
                    systemImage: "arrow.trianglehead.clockwise",
                    description: Text("When you create a recurring expense, you can manage them here.")
                )
            } else {
                Section {
                    ForEach(sortedRules) { rule in
                        RecurringRuleRow(rule: rule, nextOccurrence: rule.nextOccurrence())
                            .contentShape(Rectangle())
                            .onTapGesture { ruleToEdit = rule }
                            .swipeActions {
                                Button("Delete") {
                                    ruleToDelete = rule
                                    showDeleteConfirmation = true
                                }
                                .tint(.red)
                            }
                            .contextMenu {
                                Button("Edit") { ruleToEdit = rule }
                                Button("Delete", role: .destructive) {
                                    ruleToDelete = rule
                                    showDeleteConfirmation = true
                                }
                            }
                    }
                } header: {
                    Text("Recurring Expenses")
                }
            }
        }
        .settingsBackground()
        .sheet(item: $ruleToEdit) { rule in
            EditRecurringRuleSheet(rule: rule)
                .presentationBackground(.sageBackground)
                .presentationDetents([.large])
        }
        .navigationTitle("Recurring Expenses")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete Recurring Rule?", isPresented: $showDeleteConfirmation, presenting: ruleToDelete) { rule in
            Button("Delete Rule", role: .destructive) {
                ruleToDelete = nil
                modelContext.delete(rule)
                do {
                    try modelContext.save()
                    reminders?.refresh()
                    router.showToast(SageToast(message: "Expense Recurrence Rule Deleted", kind: .success))
                } catch {
                    modelContext.rollback()
                    router.showToast(SageToast(message: "Syl could not delete this recurring rule. Please try again.", kind: .error))
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { rule in
            Text("'\(rule.name)' will stop generating future expenses. Past expenses will not be deleted.")
        }
    }
}

private struct RecurringRuleRow: View {
    @Environment(AppConfiguration.self) private var config
    @Environment(\.categoryColors) private var categoryColors
    let rule: RecurringExpenseRule
    let nextOccurrence: Date?

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(rule.category.color(in: categoryColors))
                .frame(width: 4, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(rule.frequency.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let next = nextOccurrence {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(daysLabel(for: next))
                            .font(.caption)
                            .foregroundStyle(isImminent(next) ? .primary : .secondary)
                            .fontWeight(isImminent(next) ? .semibold : .regular)
                    }
                    if let endDate = rule.endDate {
                        Text("· ends \(endDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Text(rule.amount.currencyString(code: config.ledgerCurrencyCode))
                .font(.subheadline)
                .fontWeight(.semibold)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func daysLabel(for date: Date) -> String {
        let days = UpcomingExpenseDays.count(until: date)
        if days == 0 { return "today" }
        if days == 1 { return "in 1 day" }
        return "in \(days) days"
    }

    private func isImminent(_ date: Date) -> Bool {
        let days = UpcomingExpenseDays.count(until: date)
        return days <= 3
    }
}

#Preview {
    @Previewable @State var container = try! SageModelContainer.makeRecurringPreview()

    NavigationStack {
        RecurringExpensesSettingsSection()
    }
    .environmentInjection(container: container)
}
