import SwiftUI

struct ReminderTimePicker: View {
    @Binding var minutes: Int

    private var selection: Binding<Date> {
        // A fixed UTC reference day keeps nonexistent DST hours selectable as a preference.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return Binding(
            get: { Date(timeIntervalSince1970: Double(minutes * 60)) },
            set: { date in
                let time = calendar.dateComponents([.hour, .minute], from: date)
                minutes = (time.hour ?? 0) * 60 + (time.minute ?? 0)
            }
        )
    }

    var body: some View {
        DatePicker("Reminder Time", selection: selection, displayedComponents: .hourAndMinute)
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            .datePickerStyle(.compact)
    }
}
