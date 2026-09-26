//
//  CategoryUtilizationWidget.swift
//  FinanceTracker
//
//  Created by Enzo on 7/12/26.
//
import SwiftUI
import SageKit

struct CategoryUtilizationWidget: View {
    let selectedMonth: Date
    var usesCards = false

    var body: some View {
        if usesCards {
            VStack(spacing: 12) {
                ForEach([ExpenseCategory.needs, .wants, .savings], id: \.self) { category in
                    SingleCategoryUtilizationWidget(category: category, layout: .full, selectedMonth: selectedMonth)
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            Color(.secondarySystemGroupedBackground),
                            in: .rect(cornerRadius: DashboardCardStyle.cornerRadius)
                        )
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("dashboard-category-\(category.rawValue)")
                }
            }
        } else {
            ForEach([ExpenseCategory.needs, .wants, .savings], id: \.self) { category in
                Section {
                    SingleCategoryUtilizationWidget(category: category, layout: .full, selectedMonth: selectedMonth)
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var selectedMonth: Date = .now
    CategoryUtilizationWidget(selectedMonth: selectedMonth)
        .environmentInjection()
}
