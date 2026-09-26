import SwiftUI

/// Form-sheet width with a window-tall height limit. The entry sheet sizes
/// itself with custom detents, but a plain `.form` caps those at the fixed form
/// height, which leaves the expanded receipt panel short on iPad.
struct ExpenseEntryPresentationSizing: PresentationSizing {
    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize {
        let form = FormPresentationSizing.form.proposedSize(for: root, context: context)
        return ProposedViewSize(width: form.width, height: .infinity)
    }
}
