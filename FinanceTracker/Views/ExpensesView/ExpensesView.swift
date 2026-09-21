//
//  ExpensesScreen.swift
//  FinanceTracker
//
//  Created by Enzo on 9/21/25.
//

import SwiftUI
import SwiftData
import SageKit

struct ExpensesView: View {
    @Environment(AppRouter.self) private var appRouter

    @State private var selectedMonth: Date
    @State private var slideDirection: Edge = .leading
    @State private var searchText: String = ""
    @State private var showsMonthPicker = false

    let calendar = Calendar.current
    let formatter: DateFormatter

    init(month: Date = Date()) {
        _selectedMonth = State(initialValue: month)
        formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
    }

    var body: some View {
        @Bindable var appRouter = appRouter
        NavigationStack(path: $appRouter.expensesPath) {
            MonthExpensesList(month: selectedMonth, searchText: searchText)
                .frame(maxWidth: .infinity)
                .background(.sageBackground)
                .navigationTitle(formatter.string(from: selectedMonth))
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $searchText, prompt: "Search expenses")
                .detailRouteDestinations()
                .toolbar {
                    ToolbarItem(placement: .title) {
                        monthTitle
                            .font(.headline)
                    }
                    SageToolbar(
                        onPrevious: {
                            slideDirection = .leading
                            selectedMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                        },
                        onNext: {
                            slideDirection = .trailing
                            selectedMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                        },
                        onAdd: { appRouter.presentSheet(.addExpense(nil)) }
                    )
                }
                .gradientBackground()
                .sheet(isPresented: $showsMonthPicker) {
                    MonthPicker(month: selectedMonth, allowsFutureMonths: true) {
                        selectedMonth = $0
                    }
                }
                .onChange(of: appRouter.expensesRequestID) { _, _ in
                    selectedMonth = appRouter.expensesMonth
                    searchText = ""
                }
        }
    }

    private var monthTitle: some View {
        Button {
            showsMonthPicker = true
        } label: {
            HStack(spacing: 8) {
                Text(formatter.string(from: selectedMonth))
                Image(systemName: "chevron.down")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Choose month")
        .accessibilityIdentifier("expenses-month-picker")
    }
}


#Preview {
    ExpensesView()
        .environmentInjection()
}
