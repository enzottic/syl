//
//  SageToolbar.swift
//  FinanceTracker
//
//  Created by Enzo on 3/13/26.
//

import SwiftUI

struct SageToolbar: ToolbarContent {
    var onPrevious: () -> Void
    var onNext: () -> Void
    var onAdd: () -> Void
    var isNextDisabled: Bool = false
    
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button(action: onPrevious) {
                Label("Previous Month", systemImage: "chevron.left")
            }

            Button(action: onNext) {
                Label("Next Month", systemImage: "chevron.right")
            }
            .disabled(isNextDisabled)
        }

        ToolbarItem(placement: addButtonPlacement) {
            addButton
        }
    }

    private var addButtonPlacement: ToolbarItemPlacement {
        if #available(iOS 27.0, *) {
            // Keep expense creation visible when the toolbar runs out of space.
            .topBarPinnedTrailing
        } else {
            .topBarTrailing
        }
    }

    @ViewBuilder
    private var addButton: some View {
        Button {
            onAdd()
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Add Expense")
        .accessibilityIdentifier("add-expense-button")
        .tint(.sage)
        .buttonStyle(.borderedProminent)
    }
}
