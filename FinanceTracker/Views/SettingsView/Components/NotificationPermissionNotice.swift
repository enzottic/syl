import SwiftUI

struct NotificationPermissionNotice: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)
                Text("Notifications are off for Syl. Reminders can’t be delivered until you allow notifications in Settings.")
            }
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
                openURL(url)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

#Preview {
    NotificationPermissionNotice()
}
