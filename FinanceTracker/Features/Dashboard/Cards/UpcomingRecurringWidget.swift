//
//  UpcomingRecurringWidget.swift
//  FinanceTracker
//
//  Created by Codex on 7/31/26.
//

import SwiftUI
import SwiftData
import SageKit

struct UpcomingRecurringWidget: View {
    private struct UpcomingRule: Identifiable {
        let rule: RecurringExpenseRule
        let date: Date

        var id: UUID { rule.id }
    }

    @Query private var recurringRules: [RecurringExpenseRule]

    let layout: DashboardWidgetLayout

    private let calendar = Calendar.current

    private var upcomingRules: [UpcomingRule] {
        recurringRules
            .compactMap { rule in
                guard let date = rule.nextOccurrence(calendar: calendar) else { return nil }
                return UpcomingRule(rule: rule, date: date)
            }
            .sorted { $0.date < $1.date }
    }

    private var visibleRules: [UpcomingRule] {
        Array(upcomingRules.prefix(layout == .compact ? 4 : 5))
    }

    init(layout: DashboardWidgetLayout = .full) {
        self.layout = layout
    }

    var body: some View {
        if !visibleRules.isEmpty {
            if layout == .compact {
                VStack(alignment: .leading, spacing: 12) {
                    section
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(
                    Color(.secondarySystemGroupedBackground),
                    in: .rect(cornerRadius: DashboardCardStyle.cornerRadius)
                )
            } else {
                section
            }
        }
    }

    private var section: some View {
        Section {
            Group {
                if layout == .compact {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible()),
                        ],
                        spacing: 12
                    ) {
                        ForEach(visibleRules) { upcoming in
                            UpcomingRecurringCard(
                                rule: upcoming.rule,
                                nextDate: upcoming.date
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(visibleRules) { upcoming in
                                UpcomingRecurringCard(
                                    rule: upcoming.rule,
                                    nextDate: upcoming.date
                                )
                                .frame(width: 150)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            Text("Upcoming Expenses")
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal, layout == .compact ? 16 : 0)
        }
    }

}

private struct UpcomingRecurringCard: View {
    @Environment(AppConfiguration.self) private var config
    let rule: RecurringExpenseRule
    let nextDate: Date

    private var daysAway: Int {
        UpcomingExpenseDays.count(until: nextDate)
    }

    private var isImminent: Bool { daysAway <= 3 }

    private var tag: ExpenseTag? {
        rule.tags?.first ?? rule.tag
    }

    private var relativeDateDescription: String {
        switch daysAway {
        case 0: "Today"
        case 1: "Tomorrow"
        default: "\(daysAway) days away"
        }
    }

    private var accessibilityDescription: String {
        [
            rule.name,
            tag?.name,
            rule.amount.currencyString(code: config.ledgerCurrencyCode),
            relativeDateDescription
        ]
        .compactMap { $0 }
        .joined(separator: ". ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let tag {
                    TagGlyphView(tag: tag)
                        .font(.title2)
                        .foregroundStyle(tag.color)
                }

                Spacer()

                Text(daysAway == 0 ? "today" : daysAway == 1 ? "1 day" : "\(daysAway)d")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(isImminent ? .black : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(isImminent ? Color.orange : Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }

            Text(rule.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)

            Text(rule.amount.currencyString(code: config.ledgerCurrencyCode))
                .font(.headline)
                .fontWeight(.bold)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }
}

#Preview {
    @Previewable @State var container = try! SageModelContainer.makeRecurringPreview()

    List {
        UpcomingRecurringWidget()
    }
    .environmentInjection(container: container)
}
