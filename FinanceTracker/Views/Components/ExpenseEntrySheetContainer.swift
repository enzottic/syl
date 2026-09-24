import SwiftUI

/// Bridges the caller's environment and live controls into four persistent hosts.
struct ExpenseEntrySheetContainer<Header: View, Content: View, Footer: View, Overlay: View>: UIViewControllerRepresentable {
    var animation: Animation?
    var step: Int
    var overlayActive: Bool
    var expandsForOverlay: Bool
    var header: Header
    var content: Content
    var footer: Footer
    var overlay: Overlay

    func makeUIViewController(context: Context) -> ExpenseEntrySheetViewController {
        let controller = ExpenseEntrySheetViewController()
        controller.loadViewIfNeeded()
        updateUIViewController(controller, context: context)
        return controller
    }

    func updateUIViewController(_ controller: ExpenseEntrySheetViewController, context: Context) {
        // Sheet-spanning layer: no padding, measurement, or page transitions.
        controller.updateOverlay(
            AnyView(overlay.environment(\.self, context.environment)),
            isActive: overlayActive,
            expandsSheet: expandsForOverlay
        )
        controller.update(
            header: hosted(header.padding(.horizontal, 24).padding(.top, 8),
                           context: context, controller: controller, section: .header),
            content: hosted(content.padding(.horizontal, 24).padding(.vertical, 16),
                            context: context, controller: controller, section: .content),
            footer: hosted(footer.padding(.horizontal, 24).padding(.vertical, 12),
                           context: context, controller: controller, section: .footer),
            step: step,
            animatesHeightChanges: animation != nil && !context.environment.accessibilityReduceMotion,
            transaction: context.transaction
        )
    }

    static func dismantleUIViewController(_ controller: ExpenseEntrySheetViewController, coordinator: ()) {
        controller.cancelPendingUpdate()
    }

    private func hosted<V: View>(_ section: V, context: Context,
                                controller: ExpenseEntrySheetViewController,
                                section hostedSection: ExpenseEntrySheetViewController.HostedSection) -> AnyView {
        AnyView(
            section
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                // Also catches internal state changes that don't update the
                // representable (e.g. calendar month or asynchronously loaded tags).
                // Measure inside the page transition, before blur/scale and the
                // outgoing page's ZStack affect its presentation geometry.
                .onGeometryChange(for: CGSize.self) { $0.size } action: { [weak controller] size in
                    controller?.receiveIdealSize(size, for: hostedSection, step: step)
                }
                .environment(\.self, context.environment)
                .ignoresSafeArea(.keyboard)
                .transaction { transaction in
                    // Content transitions animate independently of the fixed
                    // header/footer and UIKit's keyboard tracking.
                    if hostedSection != .content {
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
                }
        )
    }
}
