import SwiftUI
import SageKit

struct ExpenseDetailsPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var date: Date
    @Binding var tags: [ExpenseTag]
    @State private var showDatePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(spacing: 0) {
                Button(action: toggleCalendar) {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar")
                            .foregroundStyle(.secondary)
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
                            .rotationEffect(.degrees(showDatePicker ? 180 : 0))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Date")
                .accessibilityValue(date.formatted(date: .long, time: .omitted))
                .accessibilityHint(showDatePicker ? "Closes the date picker" : "Opens the date picker")

                if showDatePicker {
                    ExpenseDateCalendar(selection: $date, onSelect: closeCalendar)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                        .transition(reduceMotion ? .identity : .move(edge: .bottom))
                }
            }
            .background(.cardBackground, in: .rect(cornerRadius: 16))
            .clipShape(.rect(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 12) {
                Text("Tags")
                    .font(.headline)
                    .padding(.horizontal, 10)
                TagPicker(selectedTags: $tags)
            }
            .sensoryFeedback(.selection, trigger: tags.map(\.id))
        }
    }

    private func toggleCalendar() {
        withAnimation(calendarAnimation) {
            showDatePicker.toggle()
        }
    }

    private var calendarAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.35)
    }

    private func closeCalendar() {
        withAnimation(calendarAnimation) {
            showDatePicker = false
        }
    }
}
