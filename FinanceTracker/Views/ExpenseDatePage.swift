import SwiftUI

struct ExpenseDatePage: View {
    @Environment(\.calendar) private var calendar
    @Binding var date: Date

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Date")
                    .font(.headline)
                Spacer()
                Text(calendar.isDateInToday(date) ? "Today" : date.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Date")
            .accessibilityValue(date.formatted(date: .long, time: .omitted))
            .accessibilityIdentifier("expense-selected-date")

            DatePicker("Date", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(.sageAccent)
                .fixedSize(horizontal: false, vertical: true)
                // Animate the surrounding page and sheet, not the native calendar's layout.
                .transaction { transaction in
                    transaction.animation = nil
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .background(.cardBackground, in: .rect(cornerRadius: 16))
    }
}
