import SwiftUI
import SageKit

struct ExpenseDatePage: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var date: Date
    @Binding var isRecurring: Bool
    @Binding var frequency: RecurrenceFrequency
    var allowsRecurrence: Bool

    var body: some View {
        VStack(spacing: 16) {
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
                    .accessibilityIdentifier("expense-date-picker")
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

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $isRecurring) {
                    Label("Recurring", systemImage: "arrow.triangle.2.circlepath")
                }
                .font(.subheadline)
                .tint(.sageAccent)
                .frame(minHeight: 44)
                .disabled(!allowsRecurrence)
                .accessibilityIdentifier("expense-recurring-toggle")

                if !allowsRecurrence {
                    Text("Refunds can’t repeat. Choose Expense on the amount page to set up a recurring expense.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("expense-recurrence-explanation")
                } else if isRecurring {
                    Divider()

                    frequencyLayout {
                        Label("Frequency", systemImage: "calendar.badge.clock")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityHidden(true)
                        if !dynamicTypeSize.isAccessibilitySize {
                            Spacer(minLength: 8)
                        }
                        Picker("Frequency", selection: $frequency) {
                            ForEach(RecurrenceFrequency.allCases, id: \.self) { frequency in
                                Text(frequency.rawValue).tag(frequency)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .tint(.primary)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("expense-frequency-picker")
                    }
                    .font(.subheadline)
                }
            }
            .padding(16)
            .background(.cardBackground, in: .rect(cornerRadius: 16))
        }
        .onChange(of: allowsRecurrence, initial: true) {
            disableDisallowedRecurrence()
        }
        .onChange(of: isRecurring) {
            disableDisallowedRecurrence()
        }
    }

    private var frequencyLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    private func disableDisallowedRecurrence() {
        if !allowsRecurrence && isRecurring {
            isRecurring = false
        }
    }
}
