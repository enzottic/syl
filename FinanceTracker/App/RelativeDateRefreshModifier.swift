import SwiftUI
import UIKit

extension EnvironmentValues {
    @Entry var relativeDateReference = Date.now
}

/// Makes the passage of a calendar day an explicit dependency of expense rows.
struct RelativeDateRefreshModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var referenceDate = Date.now

    func body(content: Content) -> some View {
        content
            .environment(\.relativeDateReference, referenceDate)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { referenceDate = .now }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                referenceDate = .now
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                referenceDate = .now
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                referenceDate = .now
            }
    }
}
