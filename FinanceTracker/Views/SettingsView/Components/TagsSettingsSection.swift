//
//  TagsSettingsSection.swift
//  FinanceTracker
//
//  Created by Enzo on 5/19/26.
//

import SwiftUI
import SwiftData
import SageKit

struct TagsSettingsSection: View {
    @Query(sort: \ExpenseTag.name) var expenseTags: [ExpenseTag]
    @Query private var allExpenses: [Expense]
    @Environment(\.modelContext) private var modelContext
    @Environment(AppConfiguration.self) private var config

    @State private var showAddTagSheet = false
    @State private var tagToEdit: ExpenseTag? = nil
    @State private var tagPendingDelete: ExpenseTag? = nil
    @State private var deleteErrorMessage: String?
    @State private var tagPendingHide: ExpenseTag?
    @State private var showHideConfirmation = false
    @State private var visibilityErrorMessage: String?
    @State private var showVisibilityError = false

    /// This month's spend against `tag` versus its cap. Over-budget reads in red.
    @ViewBuilder
    private func budgetProgress(for tag: ExpenseTag, budget: Double) -> some View {
        let spent = allExpenses.monthlyTotal(for: tag)
        let fraction = min(spent / budget, 1)
        let isOver = spent > budget

        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(tag.color.opacity(0.15))
                    Capsule()
                        .fill(isOver ? Color.red : tag.color)
                        .frame(width: max(0, geometry.size.width * fraction))
                }
            }
            .frame(height: 5)

            HStack(spacing: 4) {
                Text("\(spent.currencyString(code: config.ledgerCurrencyCode)) of \(budget.currencyString(code: config.ledgerCurrencyCode))")
                    .font(.caption2)
                    .foregroundStyle(isOver ? .red : .secondary)
                Spacer()
                if isOver {
                    Text("Over by \((spent - budget).currencyString(code: config.ledgerCurrencyCode))")
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else {
                    Text("\((budget - spent).currencyString(code: config.ledgerCurrencyCode)) left")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var availableTaggingModes: [AppConfiguration.SmartTaggingMode] {
        AppConfiguration.SmartTaggingMode.allCases.filter { mode in
            switch mode {
            case .ai, .both: return TagSuggestionService.isAIAvailable
            case .history, .none: return true
            }
        }
    }

    var body: some View {
        @Bindable var config = config
        List {
            Section {
                Picker("Smart Tagging Mode", selection: $config.smartTaggingMode) {
                    ForEach(availableTaggingModes, id: \.self) {
                        Text($0.rawValue)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Smart Tagging")
            } footer: {
                VStack(alignment: .leading) {
                    Text("Automatically suggests tags when creating a new expense.")
                    if TagSuggestionService.isAIAvailable {
                        Text("AI mode uses an on-device AI model to determine a tag. History + AI starts by searching for a matching expense, then uses AI if no match is found.")
                    }
                }
            }

            Section("Tags") {
                ForEach(visibleTags) { tag in
                    tagRow(for: tag)
                }
            }

            if !hiddenTags.isEmpty {
                Section("Hidden Tags") {
                    ForEach(hiddenTags) { tag in
                        tagRow(for: tag)
                    }
                }
            }
        }
        .settingsBackground()
        .navigationTitle("Tags")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddTagSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add new tag")
            }
        }
        .sheet(isPresented: $showAddTagSheet) {
            AddExpenseTagSheet()
                .presentationBackground(.sageBackground)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $tagToEdit) { tag in
            AddExpenseTagSheet(tagToEdit: tag)
                .presentationBackground(.background)
                .presentationDetents([.large])
        }
        .alert("Remove Tag from Expenses?", isPresented: Binding(
            get: { tagPendingDelete != nil },
            set: { if !$0 { tagPendingDelete = nil } }
        )) {
            Button("Delete Tag", role: .destructive) {
                if let tag = tagPendingDelete {
                    tagPendingDelete = nil
                    deleteTag(tag)
                }
            }
            Button("Cancel", role: .cancel) {
                tagPendingDelete = nil
            }
        } message: {
            if let tag = tagPendingDelete {
                let count = tag.taggedExpenses?.count ?? 0
                Text("\(count) expenses have the \(tag.name) tag. Deleting it will remove the tag from those expenses.")
            }
        }
        .alert("Hide Tag?", isPresented: $showHideConfirmation, presenting: tagPendingHide) { tag in
            Button("Hide Tag") {
                setHidden(true, for: tag)
                tagPendingHide = nil
            }
            Button("Cancel", role: .cancel) {
                tagPendingHide = nil
            }
        } message: { tag in
            Text("\(tag.name) will still appear on existing expenses, but will be hidden from the expense creator. You can show it again in tag settings.")
        }
        .alert("Could not update tag", isPresented: $showVisibilityError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(visibilityErrorMessage ?? "Please try again.")
        }
        .alert("Could not delete tag", isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "Please try again.")
        }
    }

    private var visibleTags: [ExpenseTag] {
        expenseTags.filter { !$0.isDeleted && !$0.isHiddenFromExpenseEntry }
    }

    private var hiddenTags: [ExpenseTag] {
        expenseTags.filter { !$0.isDeleted && $0.isHiddenFromExpenseEntry }
    }

    private func tagRow(for tag: ExpenseTag) -> some View {
        Button {
            tagToEdit = tag
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(tag.color)
                            .frame(width: 35, height: 35)
                        // The circle is filled with the tag color, so a symbol has to
                        // be knocked out in white rather than tinted to match.
                        TagGlyphView(tag: tag)
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                    }
                    Text(tag.name)
                        .foregroundStyle(.primary)
                    Spacer()
                    if tag.isHiddenFromExpenseEntry {
                        Label("Hidden", systemImage: "eye.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let budget = tag.budget, budget > 0 {
                    budgetProgress(for: tag, budget: budget)
                }
            }
        }
        .tint(.primary)
        .contextMenu {
            visibilityButton(for: tag)
        }
        .swipeActions {
            Button("Delete") {
                if (tag.taggedExpenses ?? []).isEmpty {
                    deleteTag(tag)
                } else {
                    tagPendingDelete = tag
                }
            }
            .tint(.red)
            visibilityButton(for: tag)
                .tint(.indigo)
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
    }

    private func deleteTag(_ tag: ExpenseTag) {
        modelContext.delete(tag)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            deleteErrorMessage = "Syl could not delete this tag. Please try again."
        }
    }

    private func visibilityButton(for tag: ExpenseTag) -> some View {
        Button(tag.isHiddenFromExpenseEntry ? "Show" : "Hide",
               systemImage: tag.isHiddenFromExpenseEntry ? "eye" : "eye.slash") {
            if tag.isHiddenFromExpenseEntry {
                setHidden(false, for: tag)
            } else {
                tagPendingHide = tag
                showHideConfirmation = true
            }
        }
    }

    private func setHidden(_ hidden: Bool, for tag: ExpenseTag) {
        let previousValue = tag.isHiddenFromExpenseEntry
        tag.isHiddenFromExpenseEntry = hidden
        do {
            try modelContext.save()
        } catch {
            tag.isHiddenFromExpenseEntry = previousValue
            visibilityErrorMessage = "The tag's visibility could not be saved. Please try again."
            showVisibilityError = true
        }
    }
}

#Preview {
    @Previewable @State var config = AppConfiguration.preview
    TagsSettingsSection()
        .environment(config)
        .modelContainer(SageModelContainer.preview)
}
