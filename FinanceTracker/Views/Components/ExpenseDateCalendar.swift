import SwiftUI

/// A date-only calendar with a stable height; its parent owns the reveal animation.
struct ExpenseDateCalendar: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .body) private var dayHeight = 44
    @Binding var selection: Date
    var onSelect: () -> Void
    @State private var displayedMonth: Date

    init(selection: Binding<Date>, onSelect: @escaping () -> Void) {
        _selection = selection
        self.onSelect = onSelect
        _displayedMonth = State(initialValue: selection.wrappedValue)
    }

    private var dateFormat: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    private var monthStart: Date {
        calendar.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
    }

    private var leadingDays: Int {
        (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
    }

    private var dayCount: Int {
        calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 0
    }

    private var monthsInYear: [Date] {
        guard let year = calendar.dateInterval(of: .year, for: displayedMonth) else { return [] }
        return (0..<13).compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: offset, to: year.start),
                  month < year.end else { return nil }
            return month
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    Button("Previous year", systemImage: "chevron.left.2") { moveYear(by: -1) }
                    Button("Next year", systemImage: "chevron.right.2") { moveYear(by: 1) }
                    Divider()
                    ForEach(monthsInYear, id: \.self) { month in
                        Button(month.formatted(dateFormat.month(.wide))) {
                            displayedMonth = month
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(displayedMonth, format: dateFormat.month(.wide).year())
                            .font(.headline)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityLabel("Choose month and year")
                .accessibilityValue(displayedMonth.formatted(dateFormat.month(.wide).year()))
                .accessibilityIdentifier("expense-date-calendar-month")
                Spacer(minLength: 0)
                Button("Previous month", systemImage: "chevron.left") { moveMonth(by: -1) }
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .accessibilityIdentifier("expense-date-calendar-previous-month")
                Button("Next month", systemImage: "chevron.right") { moveMonth(by: 1) }
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .accessibilityIdentifier("expense-date-calendar-next-month")
            }

            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(0..<7) { column in
                        let weekday = (calendar.firstWeekday - 1 + column) % 7
                        Text(calendar.veryShortStandaloneWeekdaySymbols[weekday])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 24)
                            .accessibilityLabel(calendar.standaloneWeekdaySymbols[weekday])
                    }
                }
                // Always reserve six weeks, including February and months starting
                // at the end of the week, so month navigation never resizes the sheet.
                ForEach(0..<6) { week in
                    GridRow {
                        ForEach(0..<7) { column in
                            let day = week * 7 + column - leadingDays + 1
                            if (1...max(1, dayCount)).contains(day),
                               let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                                let isSelected = calendar.isDate(date, inSameDayAs: selection)
                                Button { select(date) } label: {
                                    Text(day, format: .number.grouping(.never))
                                        .font(.body)
                                        .fontWeight(isSelected ? .semibold : .regular)
                                        .frame(maxWidth: .infinity, minHeight: dayHeight)
                                        .background {
                                            if isSelected {
                                                Circle().fill(.sage)
                                                    .frame(width: dayHeight - 4, height: dayHeight - 4)
                                            } else if calendar.isDateInToday(date) {
                                                Circle().stroke(.sage, lineWidth: 1)
                                                    .frame(width: dayHeight - 4, height: dayHeight - 4)
                                            }
                                        }
                                        .foregroundStyle(isSelected ? Color.black : Color.primary)
                                        .contentShape(.rect)
                                }
                                .accessibilityLabel(date.formatted(dateFormat.weekday(.wide).month(.wide).day().year()))
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                                .accessibilityIdentifier("expense-date-calendar-day-\(day)")
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity, minHeight: dayHeight)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
            Button("Today") { select(.now) }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("expense-date-calendar-today")
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("expense-date-calendar")
    }

    private func moveMonth(by offset: Int) {
        guard let month = calendar.date(byAdding: .month, value: offset, to: monthStart) else { return }
        displayedMonth = month
    }

    private func moveYear(by offset: Int) {
        guard let month = calendar.date(byAdding: .year, value: offset, to: monthStart) else { return }
        displayedMonth = month
    }

    private func select(_ day: Date) {
        // Preserve the draft's time of day, just as a date-only picker does.
        let time = calendar.dateComponents([.hour, .minute, .second], from: selection)
        selection = calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: day
        ) ?? day
        onSelect()
    }
}
