import SwiftUI

/// UIKit owns both the native detent and keyboard tracking. `animation` enables
/// native sheet animation; page transitions remain the caller's responsibility.
///
/// `overlay` is hosted above the header, content and footer, spanning the whole
/// sheet. While `overlayActive`, it receives all touches and accessibility; with
/// `expandsForOverlay` the sheet uses a fixed, screen-relative height instead of
/// the measured page height.
struct ExpenseEntrySheetLayout<Header: View, Content: View, Footer: View, Overlay: View>: View {
    var animation: Animation?
    var step: Int
    var overlayActive = false
    var expandsForOverlay = false
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer
    @ViewBuilder var overlay: Overlay

    var body: some View {
        ExpenseEntrySheetContainer(animation: animation, step: step,
                                   overlayActive: overlayActive, expandsForOverlay: expandsForOverlay,
                                   header: header, content: content, footer: footer, overlay: overlay)
        // UIKit receives the whole sheet and applies the container safe areas
        // itself. SwiftUI must not shorten it again when the keyboard arrives.
        .ignoresSafeArea()
        .presentationSizing(.form)
    }
}

extension ExpenseEntrySheetLayout where Overlay == EmptyView {
    init(animation: Animation?, step: Int,
         @ViewBuilder header: () -> Header,
         @ViewBuilder content: () -> Content,
         @ViewBuilder footer: () -> Footer) {
        self.init(animation: animation, step: step,
                  header: header, content: content, footer: footer, overlay: { EmptyView() })
    }
}
