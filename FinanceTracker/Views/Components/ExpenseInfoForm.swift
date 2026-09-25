//
//  ExpenseInfoFormNew.swift
//  FinanceTracker
//
//  Created by Enzo on 5/19/26.
//

import SwiftUI
import SwiftData
import SageKit

struct ExpenseInfoForm: View {
    @Environment(AppConfiguration.self) private var config
    @Environment(\.categoryColors) private var categoryColors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(filter: #Predicate<ExpenseTag> { !$0.isHiddenFromExpenseEntry }, sort: \ExpenseTag.name)
    private var expenseTags: [ExpenseTag]
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]

    @Binding var name: String
    @Binding var amount: Double?
    @Binding var date: Date
    @Binding var category: ExpenseCategory
    @Binding var tags: [ExpenseTag]
    @Binding var note: String

    private let tagSuggestionService = TagSuggestionService()
    @FocusState private var focusedField: Field?
    /// IDs of currently-selected tags that were suggested by the AI (drives the rainbow border).
    @State private var aiSuggestedTagIDs: Set<UUID> = []

    private enum Field: Hashable { case name, amount, note }
    
    @State private var showDatePicker = false
    init(
        name: Binding<String>,
        amount: Binding<Double?>,
        date: Binding<Date>,
        category: Binding<ExpenseCategory>,
        tags: Binding<[ExpenseTag]>,
        note: Binding<String>
    ) {
        self._name = name
        self._amount = amount
        self._date = date
        self._category = category
        self._tags = tags
        self._note = note
    }

    var body: some View {
        VStack(spacing: 20) {
            entryCard
            sectionHeader(title: "Category") {
                inlineCategoryPicker
            }
            detailsCard
            sectionHeader(title: "Tags") {
                TagPicker(
                    selectedTags: $tags,
                    aiSuggestedTagIDs: aiSuggestedTagIDs,
                    onInteraction: dismissKeyboard
                )
                    .padding(.horizontal, 8)
            }
        }
        .onChange(of: tags) { _, newValue in
            // Keep the AI-suggested highlight only for tags that are still selected.
            let selectedIDs = Set(newValue.map(\.id))
            aiSuggestedTagIDs.formIntersection(selectedIDs)
        }
        .sensoryFeedback(.selection, trigger: category)
        .sensoryFeedback(.selection, trigger: tags.map(\.id))
        .onChange(of: focusedField) { old, _ in
            if old == .name { suggestTagIfNeeded() }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(focusedField == .name ? "Next" : "Done") {
                    if focusedField == .name { focusedField = .amount } else { dismissKeyboard() }
                }
                .fontWeight(.semibold)
                .accessibilityIdentifier("expense-keyboard-continue-button")
            }
        }
    }

    // MARK: - Name header

    private var entryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            nameHeader
                .padding(20)
            Divider().padding(.horizontal, 20)
            CentsFirstCurrencyField(amount: $amount, focus: $focusedField, focusValue: .amount)
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 20)
        }
        .background(.cardBackground, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var nameHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("What was it for?", text: $name)
                .accessibilityIdentifier("expense-name-field")
                .accessibilityLabel("Expense name")
                .font(.title2.weight(.semibold))
                .submitLabel(.next)
                .focused($focusedField, equals: .name)
                .onSubmit { focusedField = .amount }
                .frame(minHeight: 44)
        }
    }

    // MARK: - Details card

    private var detailsCard: some View {
        VStack(spacing: 0) {
            Button {
                dismissKeyboard()
                withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) { showDatePicker.toggle() }
            } label: {
                HStack(spacing: 12) {
                    rowIcon("calendar")
                    Text("Date")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Calendar.current.isDateInToday(date) ? "Today" : date.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Date")
            .accessibilityValue(date.formatted(date: .long, time: .omitted))
            .accessibilityHint(showDatePicker ? "Closes the date picker" : "Opens the date picker")

            if showDatePicker {
                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .onChange(of: date) {
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) { showDatePicker = false }
                    }
                    .transition(.opacity.combined(with: .offset(y: -8)))
            }

            Divider().padding(.leading, 52)

            HStack(spacing: 12) {
                rowIcon("text.alignleft")
                    .accessibilityHidden(true)
                Text("Note")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Spacer()
                TextField("Optional", text: $note, axis: .vertical)
                    .accessibilityIdentifier("expense-note-field")
                    .accessibilityLabel("Note")
                    .font(.subheadline)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .note)
                    .lineLimit(1...4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func rowIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(width: 24, alignment: .center)
    }

    private func dismissKeyboard() {
        focusedField = nil
    }

    // MARK: - Category picker (inline)

    private var inlineCategoryPicker: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                inlineCategoryButtons
            }

            VStack(spacing: 10) {
                inlineCategoryButtons
            }
        }
        .padding(.horizontal)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: category)
    }

    @ViewBuilder
    private var inlineCategoryButtons: some View {
            ForEach(ExpenseCategory.allCases, id: \.self) { cat in
                let isSelected = category == cat
                Button {
                    dismissKeyboard()
                    category = cat
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(cat.color(in: categoryColors))
                            .frame(width: 10, height: 10)
                        Text(cat.rawValue)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isSelected ? cat.color(in: categoryColors).opacity(0.18) : .cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isSelected ? cat.color(in: categoryColors).opacity(0.6) : Color.clear,
                                lineWidth: 1.5
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("expense-category-\(cat.rawValue.lowercased())")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
            }
    }


    // MARK: - Section wrapper

    @ViewBuilder
    private func sectionHeader<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            content()
        }
    }

    // MARK: - Tag suggestion

    private func suggestTagIfNeeded() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              tags.isEmpty,
              config.smartTaggingMode != .none else { return }

        let tagNames = expenseTags.map(\.name)
        let currentName = name
        let history = expenses.map { (name: $0.name, tagName: $0.tags?.first?.name) }

        Task {
            if let result = await tagSuggestionService.suggestTag(
                for: currentName,
                existingExpenses: history,
                tagNames: tagNames,
                smartTaggingMode: config.smartTaggingMode
            ) {
                await MainActor.run {
                    if tags.isEmpty, let suggested = expenseTags.first(where: { $0.name == result.tagName && !$0.isHiddenFromExpenseEntry }) {
                        tags = [suggested]
                        if result.source == .ai {
                            aiSuggestedTagIDs = [suggested.id]
                        }
                    }
                }
            }
        }
    }
}

#Preview("Add") {
    @Previewable @State var name: String = ""
    @Previewable @State var amount: Double? = nil
    @Previewable @State var date: Date = Date.now
    @Previewable @State var category: ExpenseCategory = .needs
    @Previewable @State var tags: [ExpenseTag] = []
    @Previewable @State var note: String = ""

    ScrollView {
        ExpenseInfoForm(
            name: $name,
            amount: $amount,
            date: $date,
            category: $category,
            tags: $tags,
            note: $note
        )
        .padding(.vertical, 20)
    }
    .environmentInjection()
}

#Preview("Edit") {
    @Previewable @State var name: String = "Safeway"
    @Previewable @State var amount: Double? = 57.57
    @Previewable @State var date: Date = Date.now
    @Previewable @State var category: ExpenseCategory = .needs
    @Previewable @State var tags: [ExpenseTag] = []
    @Previewable @State var note: String = "Weekly shop + party stuff"

    ScrollView {
        ExpenseInfoForm(
            name: $name,
            amount: $amount,
            date: $date,
            category: $category,
            tags: $tags,
            note: $note
        )
        .padding(.vertical, 20)
    }
    .environmentInjection()
}
