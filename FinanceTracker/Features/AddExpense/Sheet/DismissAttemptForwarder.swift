import UIKit

/// Wraps SwiftUI's own presentation delegate so `interactiveDismissDisabled`
/// keeps working, while reporting blocked swipe-to-dismiss attempts.
@MainActor
final class DismissAttemptForwarder: NSObject, UIAdaptivePresentationControllerDelegate {
    weak var original: UIAdaptivePresentationControllerDelegate?
    var onAttempt: (() -> Void)?

    func install(on presentation: UIPresentationController) {
        guard presentation.delegate !== self else { return }
        original = presentation.delegate
        presentation.delegate = self
    }

    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        original?.presentationControllerDidAttemptToDismiss?(presentationController)
        onAttempt?()
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (original?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        original?.responds(to: selector) == true ? original : nil
    }
}
