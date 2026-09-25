import SwiftUI

struct NotificationPermissionFooter: View {
    let isDenied: Bool
    let error: String?

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isDenied {
                Text("Notifications are off for Syl. Reminders can’t be delivered until you allow notifications in Settings.")
                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
                    openURL(url)
                }
            }
            if let error {
                Text("Could not enable reminders: \(error)")
            }
        }
    }
}
