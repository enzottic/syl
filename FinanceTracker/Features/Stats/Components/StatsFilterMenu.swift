//
//  StatsFilterMenu.swift
//  FinanceTracker
//
//  Created on 3/13/26.
//

import SwiftUI
import SwiftData
import SageKit

struct StatsFilterMenu: View {
    @Binding var selectedCategory: ExpenseCategory?
    @Binding var selectedTag: ExpenseTag?
    @Binding var showsMonthPicker: Bool
    @Query(sort: \ExpenseTag.name) var expenseTags: [ExpenseTag]

    private var hasActiveFilters: Bool {
        selectedCategory != nil || (selectedTag != nil && selectedTag?.isDeleted == false)
    }

    var body: some View {
        Menu {
            Button { showsMonthPicker = true } label: {
                Label("Choose Month", systemImage: "calendar")
            }
            .accessibilityIdentifier("stats-choose-month")

            Section {
                Picker("Category", selection: $selectedCategory.animation()) {
                    Text("All Categories").tag(nil as ExpenseCategory?)
                        .accessibilityIdentifier("stats-category-all")
                    ForEach(ExpenseCategory.allCases, id: \.self) { category in
                        Text(category.rawValue).tag(category as ExpenseCategory?)
                            .accessibilityIdentifier("stats-category-\(category.rawValue.lowercased())")
                    }
                }
                .pickerStyle(.menu)

                Picker("Tag", selection: $selectedTag.animation()) {
                    Text("All Tags").tag(nil as ExpenseTag?)
                    ForEach(expenseTags, id: \.id) { tag in
                        if !tag.isDeleted {
                            TagMenuLabel(tag: tag).tag(tag as ExpenseTag?)
                        }
                    }
                }
                .pickerStyle(.menu)
            }
        } label: {
            Label("Filters", systemImage: hasActiveFilters
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
        .accessibilityIdentifier("stats-filters")
    }
}

#Preview {
    @Previewable @State var container = {
        let container = try! SageModelContainer.make(for: .previewEmpty)
        let tags: [ExpenseTag] = [.dining, .groceries, .subscriptions]
        tags.forEach { container.mainContext.insert($0) }
        try! container.mainContext.save()
        return container
    }()
    @Previewable @State var category: ExpenseCategory? = nil
    @Previewable @State var tag: ExpenseTag? = nil
    @Previewable @State var showsMonthPicker = false
    StatsFilterMenu(selectedCategory: $category, selectedTag: $tag, showsMonthPicker: $showsMonthPicker)
        .modelContainer(container)
}
