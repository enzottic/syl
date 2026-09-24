import SwiftUI

/// The receipt button on the name page. It only reports its frame and opens the
/// menu; the sheet-level overlay draws the morphing shape on top of it.
struct ReceiptAttachmentButton: View {
    let state: ReceiptAttachmentState
    var onOpen: () -> Void = {}

    var body: some View {
        Button {
            onOpen()
            state.openMenu()
        } label: {
            ReceiptAttachmentIcon(isBusy: state.isBusy)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        // Same glass and exact geometry as the overlay's collapsed shape, so the
        // hand-off between the two layers is invisible in both directions.
        .glassEffect(.regular.interactive(), in: .circle)
        .disabled(state.isBusy)
        .accessibilityLabel(state.isBusy ? "Reading receipt" : "Import receipt")
        .accessibilityIdentifier("receipt-attachment-button")
        .opacity(state.isPresented ? 0 : 1)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            state.buttonFrame = frame
        }
    }
}

/// The receipt glyph, shared by the page button and the overlay's collapsed state.
/// While a receipt is being read it becomes a spinner in place.
struct ReceiptAttachmentIcon: View {
    static let size: CGFloat = 44
    var isBusy = false

    var body: some View {
        ZStack {
            if isBusy {
                ProgressView()
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
            } else {
                Image(systemName: "receipt")
                    .font(.system(size: 17, weight: .medium))
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .frame(width: Self.size, height: Self.size)
    }
}
