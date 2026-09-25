import SwiftUI
import SwiftData
import SageKit
import WidgetKit
import PhotosUI
import Photos

struct NewAddExpenseSheet: View {
    enum AddExpenseStep: Int {
        case name, amount, category, date, details
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppConfiguration.self) private var config
    @Environment(AppRouter.self) private var appRouter
    @Query private var allTags: [ExpenseTag]

    @State private var draft: ExpenseEntryDraft
    @State private var currentStep: AddExpenseStep = .name
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isSaving = false
    @State private var importer = ExpenseReceiptImporter()
    @State private var attachment = ReceiptAttachmentState()
    @State private var showPhotoLibrary = false
    @State private var isLoadingPhoto = false
    @State private var photoItem: PhotosPickerItem?
    @State private var importTask: Task<Void, Never>?
    @State private var suggestionTask: Task<Void, Never>?
    @State private var debouncedName = ""
    @State private var recentSuggestions: [Expense] = []
    @State private var aiSuggestedTagIDs: Set<UUID> = []
    @State private var hasStartedInitialImport = false
    @FocusState private var isNameFocused: Bool
    @FocusState private var isNoteFocused: Bool
    private let initialReceiptData: Data?

    init(expense: Expense? = nil, receiptData: Data? = nil) {
        _draft = State(initialValue: ExpenseEntryDraft(expense: expense))
        initialReceiptData = receiptData
    }

    var body: some View {
        ExpenseEntrySheetLayout(animation: pageAnimation, step: currentStep.rawValue,
                                overlayActive: attachment.isPresented,
                                expandsForOverlay: attachment.mode.isExpanded) {
            EmptyView()
        } content: {
            VStack(spacing: 20) {
                pageContent
            }
            .disabled(importer.isImporting || isSaving)
        } footer: {
            HStack(spacing: 12) {
                if currentStep != .name {
                    Button(action: previousStep) {
                        Text("Back")
                            .font(.headline)
                            .frame(minWidth: 52, minHeight: 48)
                    }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.roundedRectangle(radius: 22))
                        .accessibilityIdentifier("expense-back-button")
                }
                Button(action: advanceStep) {
                    Text(isSaving ? "Saving…" : currentStep == .details ? "Save Expense" : "Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(.onSage)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: 22))
                .tint(.sage)
                .accessibilityIdentifier(currentStep == .details ? "save-expense-button" : "expense-next-button")
            }
            .disabled(isSaving || importer.isImporting)
        } overlay: {
            ReceiptAttachmentOverlay(
                state: attachment,
                onSelectAsset: importAsset,
                onCapture: importCapturedImage,
                onAllPhotos: { showPhotoLibrary = true }
            )
        }
        .interactiveDismissDisabled(attachment.isPresented)
        .alert("Expense", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
        .photosPicker(isPresented: $showPhotoLibrary, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            attachment.close()
            importTask = Task {
                if let parsed = await importer.importPhoto(item, tags: allTags) { applyReceipt(parsed) }
                photoItem = nil
            }
        }
        .onChange(of: importer.isImporting || isLoadingPhoto, initial: true) { _, busy in
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { attachment.isBusy = busy }
            if busy { AccessibilityNotification.Announcement("Reading receipt").post() }
        }
        .onChange(of: importer.errorMessage) { _, message in
            if let message { presentError(message) }
        }
        .task {
            guard !hasStartedInitialImport, let initialReceiptData else { return }
            hasStartedInitialImport = true
            if let parsed = await importer.importData(initialReceiptData, tags: allTags) { applyReceipt(parsed) }
        }
        .task(id: draft.name) {
            suggestionTask?.cancel()
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            withAnimation(pageAnimation) { debouncedName = draft.name }
        }
        .task(id: debouncedName) {
            let name = debouncedName
            let limit = dynamicTypeSize.isAccessibilitySize ? 1 : 3
            recentSuggestions = (try? ExpenseSuggestionHistory.recentDistinctMatches(
                for: name, limit: limit, in: modelContext
            )) ?? []
        }
        .onChange(of: draft.amount) {
            if let amount = draft.amount, amount < 0 { draft.isRecurring = false }
        }
        .onDisappear {
            attachment.tearDown()
            importTask?.cancel()
            suggestionTask?.cancel()
        }
    }

    private var pageAnimation: Animation? { reduceMotion ? nil : .smooth(duration: 0.3) }

    @ViewBuilder private var pageContent: some View {
        switch currentStep {
        case .name:
            if isNameFocused && !recentSuggestions.isEmpty {
                ExpenseEntrySuggestions(expenses: recentSuggestions, currencyCode: config.ledgerCurrencyCode, onSelect: applySuggestion)
                    .transition(.opacity)
            }
            ExpenseNamePage(name: $draft.name, nameFocus: $isNameFocused, onSubmit: advanceStep) { receiptMenu }
        case .amount:
            ExpenseAmountPage(amount: $draft.amount)
        case .category:
            ExpenseCategoryPage(category: $draft.category)
        case .date:
            ExpenseDatePage(date: $draft.date, isRecurring: $draft.isRecurring,
                            frequency: $draft.recurrenceFrequency, allowsRecurrence: (draft.amount ?? 0) > 0)
        case .details:
            ExpenseTagsPage(tags: $draft.tags, note: $draft.note, isNoteFocused: $isNoteFocused,
                            aiSuggestedTagIDs: aiSuggestedTagIDs)
        }
    }

    /// Hidden entirely without Apple Intelligence: there's no receipt reading to offer.
    @ViewBuilder private var receiptMenu: some View {
        if importer.isAvailable {
            ReceiptAttachmentButton(state: attachment, onOpen: clearFocus)
        }
    }

    private func importAsset(_ asset: PHAsset) {
        guard !importer.isImporting else { return }
        attachment.close()
        importTask?.cancel()
        importTask = Task {
            isLoadingPhoto = true
            let image = await ReceiptPhotoLoader.image(for: asset)
            isLoadingPhoto = false
            guard let image else {
                if !Task.isCancelled { presentError("Syl couldn't open that photo. Choose another photo and try again.") }
                return
            }
            if let parsed = await importer.importImage(image, tags: allTags) { applyReceipt(parsed) }
        }
    }

    private func importCapturedImage(_ image: UIImage) {
        guard !importer.isImporting else { return }
        attachment.close()
        importTask?.cancel()
        importTask = Task {
            if let parsed = await importer.importImage(image, tags: allTags) { applyReceipt(parsed) }
        }
    }

    private func applySuggestion(_ expense: Expense) {
        draft.name = expense.name
        draft.amount = expense.amount
        draft.category = expense.category
        draft.tags = expense.tags ?? []
        clearFocus()
    }

    private func suggestTag() {
        guard draft.tags.isEmpty else { return }
        let name = draft.name
        let tags = allTags.filter { !$0.isHiddenFromExpenseEntry }
        let history = (try? ExpenseSuggestionHistory.newestTaggedMatch(for: name, in: modelContext)).map { [$0] } ?? []
        suggestionTask?.cancel()
        suggestionTask = Task {
            let suggestion = await TagSuggestionService().suggestTag(
                for: name, existingExpenses: history, tagNames: tags.map(\.name),
                smartTaggingMode: config.smartTaggingMode)
            guard !Task.isCancelled, draft.name == name, draft.tags.isEmpty,
                  currentStep.rawValue < AddExpenseStep.details.rawValue,
                  let suggestion, let tag = tags.first(where: { $0.name == suggestion.tagName }) else { return }
            draft.tags = [tag]
            aiSuggestedTagIDs = suggestion.source == .ai ? [tag.id] : []
        }
    }

    private func clearFocus() {
        isNameFocused = false
        isNoteFocused = false
    }

    private func advanceStep() {
        guard !isSaving, !importer.isImporting else { return }
        if currentStep == .name {
            guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                presentError("Please enter an expense name")
                return
            }
            suggestTag()
        }
        if currentStep == .amount {
            guard let amount = draft.amount, MonetaryAmount.isValid(amount, currencyCode: config.ledgerCurrencyCode) else {
                presentError(MonetaryAmount.validationMessage(currencyCode: config.ledgerCurrencyCode))
                return
            }
        }
        clearFocus()
        if let next = AddExpenseStep(rawValue: currentStep.rawValue + 1) {
            withAnimation(pageAnimation) { currentStep = next }
        } else {
            saveExpense()
        }
    }

    private func previousStep() {
        guard !isSaving, !importer.isImporting,
              let previous = AddExpenseStep(rawValue: currentStep.rawValue - 1) else { return }
        clearFocus()
        withAnimation(pageAnimation) { currentStep = previous }
    }

    private func saveExpense() {
        guard !isSaving else { return }
        do {
            try draft.validate(currencyCode: config.ledgerCurrencyCode)
            isSaving = true
            try ExpenseEntrySaver(modelContainer: modelContext.container).save(draft, currencyCode: config.ledgerCurrencyCode)
            WidgetCenter.shared.reloadAllTimelines()
            dismiss()
            appRouter.showToast(SageToast(message: "Expense saved", kind: .success))
        } catch {
            isSaving = false
            presentError(error is ExpenseEntryDraft.ValidationError ? error.localizedDescription :
                "Syl could not save this expense. Check available storage and try again.")
        }
    }

    private func applyReceipt(_ parsed: ParsedExpense) {
        guard !Task.isCancelled else { return }
        draft.name = parsed.name
        draft.amount = parsed.price
        if let rawDate = parsed.date {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: rawDate) { draft.date = date }
        }
        draft.category = ExpenseCategory.allCases.first { $0.rawValue.lowercased() == parsed.category.lowercased() } ?? .needs
        if let tagName = parsed.tag,
           let tag = allTags.first(where: { $0.name == tagName && !$0.isHiddenFromExpenseEntry }) {
            draft.tags = [tag]
        }
    }

    private func presentError(_ message: String) {
        errorMessage = message
        showError = true
    }
}

#Preview {
    Text("Expense entry")
        .sheet(isPresented: .constant(true)) { NewAddExpenseSheet() }
        .environmentInjection()
}
