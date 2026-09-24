import SwiftUI
import Photos

/// Sheet-level layer that morphs one Liquid Glass shape from the receipt button
/// into the attachment menu, then into the full camera / photo panel.
struct ReceiptAttachmentOverlay: View {
    let state: ReceiptAttachmentState
    /// Replaces both options when receipt reading isn't available.
    var unavailableMessage: String?
    var onSelectAsset: (PHAsset) -> Void
    var onCapture: (UIImage) -> Void
    var onAllPhotos: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var menuHeight: CGFloat = 128

    private static let menuWidth: CGFloat = 240
    private static let expandedInset: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let button = state.buttonFrame.offsetBy(dx: -origin.x, dy: -origin.y)
            let size = proxy.size
            let expanded = expandedFrame(button: button, in: size)
            let rect = frame(for: state.mode, button: button, expanded: expanded)

            if state.isPresented {
                ZStack(alignment: .topLeading) {
                    // Blocks the page underneath; tapping outside the menu closes it.
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture {
                            if state.mode == .menu { state.close() }
                        }
                        .accessibilityHidden(true)

                    panel(rect: rect, expanded: expanded)
                        .frame(width: rect.width, height: rect.height, alignment: .topTrailing)
                        .clipShape(shape(for: state.mode))
                        .glassEffect(.regular, in: shape(for: state.mode))
                        .offset(x: rect.minX, y: rect.minY)
                        .accessibilityElement(children: .contain)
                        .accessibilityAddTraits(.isModal)
                        .accessibilityAction(.escape) {
                            state.mode.isExpanded ? state.back() : state.close()
                        }
                }
                // The sheet resizes natively around the panel; follow it smoothly.
                .animation(state.expandAnimation, value: size)
                .animation(state.expandAnimation, value: button)
            }
        }
        .onChange(of: reduceMotion, initial: true) { _, value in state.reduceMotion = value }
    }

    // MARK: - Layers

    private func panel(rect: CGRect, expanded: CGRect) -> some View {
        ZStack(alignment: .topTrailing) {
            ReceiptAttachmentIcon(isBusy: state.isBusy)
                .opacity(state.mode == .closed ? 1 : 0)
                .accessibilityHidden(true)

            menu
                .opacity(state.mode == .menu ? 1 : 0)
                .blur(radius: state.mode == .menu ? 0 : 6)

            // Laid out at the final size and revealed by the growing shape.
            ZStack {
                if state.mode == .photos {
                    ReceiptPhotoGrid(onBack: state.back, onSelect: onSelectAsset, onAllPhotos: onAllPhotos)
                        .transition(.opacity)
                }
                if state.mode == .camera {
                    ReceiptCameraView(camera: state.cameraSession, onBack: state.back, onCapture: onCapture)
                        .transition(.opacity)
                }
            }
            .frame(width: expanded.width, height: expanded.height)
        }
    }

    private var menu: some View {
        VStack(spacing: 0) {
            if let unavailableMessage {
                Label(unavailableMessage, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                cameraRow
                ReceiptAttachmentMenuRow(title: "Photos", systemImage: "photo.on.rectangle") {
                    state.show(.photos)
                }
                .accessibilityIdentifier("receipt-menu-photos")
            }
        }
        .padding(8)
        .frame(width: Self.menuWidth)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { menuHeight = $0 }
        .allowsHitTesting(state.mode == .menu)
        .accessibilityHidden(state.mode != .menu)
    }

    @ViewBuilder private var cameraRow: some View {
        switch state.cameraAvailability {
        case .available:
            ReceiptAttachmentMenuRow(title: "Camera", systemImage: "camera") {
                state.show(.camera)
            }
            .accessibilityIdentifier("receipt-menu-camera")
        case .unavailable(let reason):
            Menu {
                Section("Camera Not Available") {
                    if let reason { Text(reason) }
                }
            } label: {
                ReceiptAttachmentMenuRowLabel(title: "Camera", systemImage: "camera")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("receipt-menu-camera")
        }
    }

    // MARK: - Geometry

    private func frame(for mode: ReceiptAttachmentState.Mode, button: CGRect, expanded: CGRect) -> CGRect {
        switch mode {
        case .closed:
            return button
        case .menu:
            let x = max(Self.expandedInset, button.maxX - Self.menuWidth)
            return CGRect(x: x, y: button.minY, width: Self.menuWidth, height: menuHeight)
        case .photos, .camera:
            return expanded
        }
    }

    private func expandedFrame(button: CGRect, in size: CGSize) -> CGRect {
        let top = max(Self.expandedInset, button.minY)
        return CGRect(x: Self.expandedInset, y: top,
                      width: max(0, size.width - Self.expandedInset * 2),
                      height: max(0, size.height - top - Self.expandedInset))
    }

    private func shape(for mode: ReceiptAttachmentState.Mode) -> RoundedRectangle {
        switch mode {
        case .closed: RoundedRectangle(cornerRadius: max(state.buttonFrame.height / 2, 1), style: .continuous)
        case .menu: RoundedRectangle(cornerRadius: 30, style: .continuous)
        case .photos, .camera: RoundedRectangle(cornerRadius: 40, style: .continuous)
        }
    }
}

private struct ReceiptAttachmentMenuRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ReceiptAttachmentMenuRowLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }
}

private struct ReceiptAttachmentMenuRowLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 40, height: 40)
                .background(.fill.tertiary, in: .circle)
            Text(title)
                .font(.body)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 56)
        .contentShape(.rect)
    }
}

/// Glass circle back button shared by both panels.
struct ReceiptPanelBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Back")
        .accessibilityIdentifier("receipt-panel-back")
    }
}
