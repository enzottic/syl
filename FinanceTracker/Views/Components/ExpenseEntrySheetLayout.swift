import SwiftUI

/// UIKit owns both the native detent and keyboard tracking. `animation` enables
/// native sheet animation; page transitions remain the caller's responsibility.
struct ExpenseEntrySheetLayout<Header: View, Content: View, Footer: View>: View {
    var animation: Animation?
    var step: Int
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        ExpenseEntrySheetContainer(animation: animation, step: step,
                                   header: header, content: content, footer: footer)
        // UIKit receives the whole sheet and applies the container safe areas
        // itself. SwiftUI must not shorten it again when the keyboard arrives.
        .ignoresSafeArea()
        .presentationSizing(.form)
    }
}
