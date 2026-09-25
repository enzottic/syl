import SwiftUI

/// Shown in place of the grid when there's nothing to pick from. It scrolls
/// instead of clipping at large text sizes and stays clear of the panel's
/// bottom buttons.
struct ReceiptPhotoAccessMessage<Actions: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let description: LocalizedStringKey
    @ViewBuilder var actions: Actions

    var body: some View {
        ScrollView {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(description)
            } actions: {
                actions
            }
        }
        .defaultScrollAnchor(.center, for: .alignment)
        .scrollBounceBehavior(.basedOnSize)
        .contentMargins(.bottom, 72, for: .scrollContent)
        .scrollIndicators(.hidden)
    }
}

extension ReceiptPhotoAccessMessage where Actions == EmptyView {
    init(title: LocalizedStringKey, systemImage: String, description: LocalizedStringKey) {
        self.init(title: title, systemImage: systemImage, description: description) { EmptyView() }
    }
}
