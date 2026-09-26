//
//  SearchExpensesView.swift
//  FinanceTracker
//
//  Created on 4/10/26.
//

import SwiftUI
import SwiftData
import SageKit

struct SearchExpensesView: View {
    @Environment(AppRouter.self) private var appRouter
    @State private var searchText: String = ""
    @State private var activeSearchText: String = ""

    private var isSearchEmpty: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        @Bindable var appRouter = appRouter
        NavigationStack(path: $appRouter.searchPath) {
            VStack {
                if isSearchEmpty {
                    ContentUnavailableView(
                        "Search All Expenses",
                        systemImage: "magnifyingglass",
                        description: Text("Search by name, note, or tag")
                    )
                } else if activeSearchText.isEmpty {
                    Color.clear
                        .accessibilityHidden(true)
                } else {
                    PaginatedExpenseSearchResults(searchText: activeSearchText)
                        .id(activeSearchText)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.sageBackground)
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: "Search expenses")
            .task(id: searchText) {
                let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedSearchText.isEmpty else {
                    activeSearchText = ""
                    return
                }

                do {
                    try await Task.sleep(for: .milliseconds(150))
                    activeSearchText = trimmedSearchText
                } catch is CancellationError {
                    // A new character cancels this search before it reaches SwiftData.
                } catch {
                    // Task.sleep only throws when SwiftUI cancels this task.
                }
            }
            .detailRouteDestinations()
            .gradientBackground()
        }
    }
}

private struct PaginatedExpenseSearchResults: View {
    @State private var visibleLimit = 100
    let searchText: String

    var body: some View {
        ExpenseSearchResults(searchText: searchText, visibleLimit: visibleLimit) {
            visibleLimit += 100
        }
    }
}

private struct ExpenseSearchResults: View {
    @Query private var expenses: [Expense]
    let visibleLimit: Int
    let loadMore: () -> Void

    init(searchText: String, visibleLimit: Int, loadMore: @escaping () -> Void) {
        self.visibleLimit = visibleLimit
        self.loadMore = loadMore
        _expenses = Query(ExpenseFetchDescriptors.search(searchText, visibleLimit: visibleLimit))
    }

    var body: some View {
        let sections = makeSections()

        Group {
            if expenses.isEmpty {
                ContentUnavailableView(
                    "No matching expenses",
                    systemImage: "magnifyingglass"
                )
            } else {
                List {
                    ForEach(sections) { section in
                        Section {
                            ExpenseList(expenses: section.expenses)
                        } header: {
                            Text(section.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                        }
                    }

                    if expenses.count > visibleLimit {
                        Button("Load more results", action: loadMore)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityIdentifier("search-load-more")
                    }
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }

    private func makeSections() -> [ExpenseSearchSection] {
        let calendar = Calendar.current
        let groupedExpenses = Dictionary(grouping: expenses.prefix(visibleLimit)) { expense in
            calendar.startOfDay(for: expense.date)
        }

        return groupedExpenses
            .map { ExpenseSearchSection(date: $0.key, expenses: $0.value) }
            .sorted { $0.date > $1.date }
    }
}

private struct ExpenseSearchSection: Identifiable {
    let date: Date
    let expenses: [Expense]

    var id: Date { date }
}

#Preview {
    SearchExpensesView()
        .environmentInjection()
}
