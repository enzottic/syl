//
//  ToastPill.swift
//  FinanceTracker
//

import SwiftUI

struct ToastPill: View {
    let toast: SageToast

    var body: some View {
        HStack(spacing: 8) {
            toastIcon
            Text(toast.message)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(accessibilityPrefix): \(toast.message)")
    }

    @ViewBuilder
    private var toastIcon: some View {
        switch toast.kind {
        case .progress:
            ProgressView()
                .controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private var accessibilityPrefix: String {
        switch toast.kind {
        case .progress: return "In progress"
        case .success: return "Success"
        case .error: return "Error"
        }
    }
}
