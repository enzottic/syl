//
//  NewAddExpenseSheet.swift
//  FinanceTracker
//
//  Created by Enzo on 9/21/26.
//

import SwiftUI
import SwiftData
import SageKit
import WidgetKit


struct NewAddExpenseSheet: View {

    enum AddExpenseStep: Int, CaseIterable {
        case name
        case amount
        case category
        case details
    }

    private enum SheetMode {
        case form
        case camera
        case gallery
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppConfiguration.self) private var config
    @Environment(AppRouter.self) private var appRouter

    @State private var showError = false
    @State private var errorMessage = ""
    @State private var currentStep: AddExpenseStep = .name
    @State private var sheetMode: SheetMode = .form
    @State private var expenseName = ""
    @State private var expenseAmount: Double?
    @State private var expenseCategory: ExpenseCategory = .needs
    @State private var expenseDate = Date.now
    @State private var expenseTags: [ExpenseTag] = []
    @FocusState private var isNameFocused: Bool

    let maxSheetHeight: CGFloat

    var body: some View {
        DynamicSheet(
            animation: pageAnimation,
            isExpanded: sheetMode != .form,
            maxHeight: maxSheetHeight
        ) {
            if sheetMode == .form {
                VStack(spacing: 24) {
                    pageContent
                        .id(currentStep)
                        .transition(.blurReplace)

                    HStack(spacing: 12) {
                        if currentStep != .name {
                            Button(action: previousStep) {
                                Text("Back")
                                    .font(.headline)
                                    .frame(minWidth: 52, minHeight: 44)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.roundedRectangle(radius: 22))
                        }

                        Button(action: advanceStep) {
                            Text(currentStep == .details ? "Done" : "Next")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(Color(red: 0.10, green: 0.17, blue: 0.07))
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.roundedRectangle(radius: 22))
                        .tint(.sage)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                // The sheet's bottom safe area supplies the space below the buttons.
            } else {
                mediaContent
                    .transition(.blurReplace)
            }
        }
        .alert("Could not save expense", isPresented: $showError) {
        } message: {
            Text(errorMessage)
        }
    }

    private var pageAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.35)
    }

    private func setSheetMode(_ mode: SheetMode) {
        withAnimation(pageAnimation) {
            sheetMode = mode
        }
    }

    private var receiptMenu: some View {
        Menu("Import receipt", systemImage: "receipt") {
            Button("Take Receipt Photo", systemImage: "camera") {
                setSheetMode(.camera)
            }
            Button("Choose Photo", systemImage: "photo") {
                setSheetMode(.gallery)
            }
        }
        .labelStyle(.iconOnly)
        .frame(minWidth: 44, minHeight: 44)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }

    private var mediaContent: some View {
        VStack(spacing: 24) {
            HStack {
                Button("Back", systemImage: "chevron.left") {
                    setSheetMode(.form)
                }
                .frame(minHeight: 44)
                .buttonStyle(.glass)

                Spacer()

                Text(sheetMode == .camera ? "Take Receipt Photo" : "Choose Photo")
                    .font(.headline)
            }

            // Replace these placeholders with the capture and photo library views.
            ContentUnavailableView(
                sheetMode == .camera ? "Receipt Camera" : "Receipt Photos",
                systemImage: sheetMode == .camera ? "camera" : "photo.on.rectangle",
                description: Text(sheetMode == .camera
                    ? "Camera capture is not available yet."
                    : "Photo browsing is not available yet.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    private func advanceStep() {
        guard validateCurrentStep() else { return }
        if let next = AddExpenseStep(rawValue: currentStep.rawValue + 1) {
            if currentStep == .name {
                isNameFocused = false
                Task { @MainActor in
                    await Task.yield()
                    withAnimation(pageAnimation) {
                        currentStep = next
                    }
                }
                return
            }
            withAnimation(pageAnimation) {
                currentStep = next
            }
        } else {
            saveExpense()
        }
    }

    private func validateCurrentStep() -> Bool {
        if currentStep == .name || currentStep == .details {
            guard !expenseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = "Please enter an expense name"
                showError = true
                return false
            }
        }
        if currentStep == .amount || currentStep == .details {
            guard let amount = expenseAmount,
                  MonetaryAmount.isValid(amount, currencyCode: config.ledgerCurrencyCode) else {
                errorMessage = MonetaryAmount.validationMessage(currencyCode: config.ledgerCurrencyCode)
                showError = true
                return false
            }
        }
        return true
    }

    private func saveExpense() {
        guard let amount = expenseAmount else { return }
        let expense = Expense(
            name: expenseName.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amount,
            category: expenseCategory,
            date: expenseDate,
            tags: expenseTags
        )
        modelContext.insert(expense)
        do {
            try modelContext.save()
            WidgetCenter.shared.reloadAllTimelines()
            dismiss()
            appRouter.showToast(SageToast(message: "Expense saved", kind: .success))
        } catch {
            modelContext.rollback()
            errorMessage = "Syl could not save this expense. Check available storage and try again."
            showError = true
        }
    }

    private func previousStep() {
        if let previous = AddExpenseStep(rawValue: currentStep.rawValue - 1) {
            withAnimation(pageAnimation) {
                currentStep = previous
            }
        }
    }

    @ViewBuilder
    var pageContent: some View {
        switch(currentStep) {
        case .name:
            ExpenseNamePage(name: $expenseName, nameFocus: $isNameFocused, onSubmit: advanceStep) {
                receiptMenu
            }
        case .amount: ExpenseAmountPage(amount: $expenseAmount)
        case .category: ExpenseCategoryPage(category: $expenseCategory)
        case .details: ExpenseDetailsPage(date: $expenseDate, tags: $expenseTags)
        }
    }
}

struct DynamicSheet<Content: View>: View {
    var animation: Animation?
    var isExpanded = false
    var maxHeight: CGFloat
    @ViewBuilder var content: Content
    @State private var contentHeight: CGFloat = 0

    // Approximately half an iPhone screen, with the bottom safe area added by the sheet.
    private let mediaHeight: CGFloat = 420

    private var sheetHeight: CGFloat {
        min(contentHeight, maxHeight)
    }

    var body: some View {
        ScrollView {
            content
                .frame(height: isExpanded ? mediaHeight : nil, alignment: .top)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: { newHeight in
                    guard newHeight > 0, abs(newHeight - contentHeight) > 0.5 else { return }
                    if contentHeight == .zero {
                        contentHeight = newHeight
                    } else {
                        withAnimation(animation) {
                            contentHeight = newHeight
                        }
                    }
                }
                .frame(minHeight: maxHeight, alignment: .bottom)
        }
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .defaultScrollAnchor(.bottom, for: .alignment)
        .scrollBounceBehavior(.basedOnSize)
        // Every page shares one stable, bottom-aligned viewport. Changing both the
        // scroll viewport and its content size during the same animation causes
        // scroll-offset corrections that briefly push the footer offscreen, and
        // switching anchoring per page made those page changes animate differently.
        .frame(height: maxHeight)
        .frame(height: sheetHeight == .zero ? nil : sheetHeight, alignment: .bottom)
        // Anchor the footer to the presented sheet, including while its detent
        // catches up with a new page or the calendar's changing content height.
        .frame(maxHeight: .infinity, alignment: .bottom)
        .clipped()
        .modifier(SheetHeightModifier(height: sheetHeight))
    }
}

fileprivate struct SheetHeightModifier: ViewModifier, Animatable {
    var height: CGFloat
    var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }

    func body(content: Content) -> some View {
        content
            .presentationDetents(height == .zero ? [.medium] : [.height(height)])
    }
}

#Preview {
    @Previewable @State var container = try! SageModelContainer.make(for: .preview)

    @Previewable @State var showSheet = true

    Button("Open sheet") { showSheet = true }
        .sheet(isPresented: $showSheet) {
            NewAddExpenseSheet(maxSheetHeight: 600)
        }
        .modelContainer(container)
        .environment(AppConfiguration.preview)
        .environment(AppRouter())
}
