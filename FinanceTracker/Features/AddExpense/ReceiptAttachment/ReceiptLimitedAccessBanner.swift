import SwiftUI

/// Sits above the grid when Syl can see only selected photos, and offers the
/// two ways to change that.
struct ReceiptLimitedAccessBanner: View {
    let onSelectPhotos: () -> Void
    let onOpenSettings: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))

        layout {
            Text("Syl can see only the photos you've selected.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Menu("Manage") {
                Button("Select More Photos", systemImage: "photo.badge.plus", action: onSelectPhotos)
                Button("Open Settings", systemImage: "gear", action: onOpenSettings)
            }
            .font(.footnote.weight(.semibold))
            .accessibilityIdentifier("receipt-photos-manage")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }
}
