//
//  ExpenseImportExportSection.swift
//  FinanceTracker
//
//  Created by Enzo on 5/16/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import WidgetKit
import SageKit

struct ExpenseBackupSettingsSection: View {
    @Environment(\.modelContext) var modelContext
    @Environment(AppConfiguration.self) var config
    @Environment(AppRouter.self) var appRouter
    
    @State private var showFileImporter: Bool = false
    @State private var showImportConfirmation: Bool = false
    @State private var pendingSource: ExpenseImportSource?
    @State private var importPlan: ExpenseImportPlan?
    @State private var legacyCurrencyConsent = false
    @State private var operationError: String?
    @State private var exportedURL: URL?
    @State private var exportDocument: ExpenseExportDocument?
    @State private var showFileExporter = false
    @State private var importTask: Task<Void, Never>?
    @State private var pendingImportCurrencyCode: String?
    // Nil means unresolved/cancelled; an empty selection means explicitly skipping new tags.
    @State private var pendingImportTagNames: [String]?
    @State private var unknownTagNames: [String] = []
    @State private var showUnknownTagsSheet: Bool = false
    @State private var isReadingImport = false
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var importedExpenseCount = 0
    @State private var importTotal = 0
    
    let expenseExporter = ExpenseBackupService.shared

    private var isWorking: Bool {
        isReadingImport || isImporting || isExporting || showFileExporter
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: cloudSyncBinding) {
                    HStack {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .frame(width: 35, height: 35)
                                .foregroundStyle(.blue)
                            Image(systemName: "arrow.triangle.2.circlepath.icloud.fill")
                                .frame(width: 35)
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading) {
                            Text("Enable iCloud Sync")
                        }
                    }
                }
                .disabled(isWorking || !config.supportsCloudSync)
            } header: {
                Text("iCloud Sync")
            } footer: {
                if !config.supportsCloudSync {
                    Text("This dev build is local-only. Expenses and preferences do not sync with iCloud or your main Syl install.")
                } else {
                    Text("Preference sync changes take effect immediately. Fully close and reopen Syl to apply changes to expense sync. Previously queued iCloud activity may still finish; turning sync off does not delete existing iCloud data.")
                    if config.cloudSyncStatus == .accountChanged {
                        Text("Your iCloud account changed. Preference sync is off. Fully restart Syl to stop expense sync, then review your account before enabling sync again.")
                    } else if config.cloudSyncStatus == .quotaExceeded {
                        Text("iCloud preference storage is full. Changes are saved on this device, but new preference uploads are paused.")
                    } else if config.cloudSyncStatus == .synchronizationUnavailable {
                        Text("iCloud preferences are currently unavailable. Your settings remain saved on this device.")
                    }
                }
            }

            Section {
                Button {
                    guard !isWorking else { return }
                    showFileImporter = true
                } label: {
                    SettingsListItem(text: "Import File", icon: "square.and.arrow.down", color: .green)
                }
                .disabled(isWorking)

                Button {
                    exportExpenses(csv: false)
                } label: {
                    SettingsListItem(text: "Create Expense Backup", icon: "doc.badge.arrow.up", color: .orange)
                }
                .disabled(isWorking)
                Button {
                    exportExpenses(csv: true)
                } label: {
                    SettingsListItem(text: "Export CSV", icon: "tablecells", color: .orange)
                }
                .disabled(isWorking)
            } header: {
                Text("Expense Backup")
            } footer: {
                Text("JSON backups preserve saved expenses, recurring rules and their tags, including tag colors and icons, schedule time zones and generation progress. CSV includes expenses only and always adds every row on import. Exports exclude pending edits, accounts, budgets, settings and unused tags. Choose a location in Files to save your export. Files contain readable, unencrypted financial data; store them carefully.")
            }
            if let operationError {
                Section("Could Not Complete") {
                    Text(operationError).foregroundStyle(.red).textSelection(.enabled)
                }
            }
        }
        .settingsBackground()
        .navigationTitle("Backup")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if isWorking {
                operationProgress
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType.json, UTType.commaSeparatedText],
            allowsMultipleSelection: false,
            onCompletion: importExpenses
        )
        .fileExporter(
            isPresented: $showFileExporter,
            document: exportDocument,
            contentTypes: [exportedURL?.pathExtension == "csv" ? .commaSeparatedText : .json],
            defaultFilename: exportedURL?.deletingPathExtension().lastPathComponent,
            onCompletion: { result in
                defer { clearExport() }
                switch result {
                case .success:
                    appRouter.showToast(SageToast(message: "Saved expense backup file", kind: .success))
                case .failure(let error):
                    let nsError = error as NSError
                    if nsError.domain != NSCocoaErrorDomain || nsError.code != NSUserCancelledError {
                        operationError = error.localizedDescription
                    }
                }
            },
            onCancellation: clearExport
        )
        .sheet(isPresented: $showImportConfirmation, onDismiss: clearPendingImport) {
            importSummary
        }
        .sheet(isPresented: $showUnknownTagsSheet, onDismiss: {
            if pendingImportTagNames != nil {
                prepareReview()
                showImportConfirmation = true
            } else {
                clearPendingImport()
            }
        }) {
            UnknownTagsSheet(
                unknownTagNames: unknownTagNames,
                onResolve: { selectedNames in
                    pendingImportTagNames = selectedNames
                    showUnknownTagsSheet = false
                }
            )
            .presentationDetents([.medium])
        }
    }

    private var cloudSyncBinding: Binding<Bool> {
        Binding(
            get: { config.isCloudSyncEnabled },
            set: { enabled in
                if config.updateCloudSyncEnabled(enabled) {
                    appRouter.showToast(
                        SageToast(message: "Sync preference saved. Fully close and reopen Syl to apply it to expenses.", kind: .success)
                    )
                } else {
                    appRouter.showToast(
                        SageToast(
                            message: "Syl could not save the sync preference. Try again.",
                            kind: .error
                        )
                    )
                }
            }
        )
    }

    @ViewBuilder
    private var operationProgress: some View {
        VStack(spacing: 6) {
            if isImporting {
                ProgressView(value: Double(importedExpenseCount), total: Double(max(importTotal, 1))) {
                    Text(importedExpenseCount == importTotal ? "Saving import" : "Preparing import")
                } currentValueLabel: {
                    Text("\(importedExpenseCount) of \(importTotal)")
                }
            } else if isReadingImport {
                ProgressView("Preparing import")
            } else {
                ProgressView("Creating export")
            }
        }
        .font(.subheadline)
        .padding()
        .frame(maxWidth: .infinity)
        .background(.bar)
        .accessibilityElement(children: .combine)
    }
    
    private func importExpenses(filePickerResult: Result<[URL], any Error>) {
        guard !isWorking else { return }
        clearPendingImport()
        operationError = nil
        do {
            let urls = try filePickerResult.get()
            guard let url = urls.first else { return }
            let currency = config.ledgerCurrencyCode
            let scoped = url.startAccessingSecurityScopedResource()
            isReadingImport = true
            Task {
                defer {
                    if scoped { url.stopAccessingSecurityScopedResource() }
                    isReadingImport = false
                }
                do {
                    let source = try await expenseExporter.readExpenses(from: url)
                    pendingSource = source
                    pendingImportCurrencyCode = currency
                    if case .csv(let rows) = source {
                        let reader = ModelContext(modelContext.container)
                        reader.autosaveEnabled = false
                        let known = Set(try reader.fetch(FetchDescriptor<ExpenseTag>()).map(\.name))
                        unknownTagNames = Set(rows.flatMap(\.tagNames)).subtracting(known).sorted()
                    }
                    prepareReview()
                    if !unknownTagNames.isEmpty, importPlan != nil {
                        showUnknownTagsSheet = true
                    } else {
                        showImportConfirmation = true
                    }
                } catch { operationError = error.localizedDescription }
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain != NSCocoaErrorDomain || nsError.code != NSUserCancelledError {
                operationError = error.localizedDescription
            }
        }
    }

    private func exportExpenses(csv: Bool) {
        guard !isWorking else { return }
        isExporting = true
        operationError = nil
        clearExport()
        Task {
            defer { isExporting = false }
            do {
                let currency = config.ledgerCurrencyCode
                if csv {
                    exportedURL = try await expenseExporter.exportCSV(modelContainer: modelContext.container, currencyCode: currency)
                } else {
                    exportedURL = try await expenseExporter.createBackup(modelContainer: modelContext.container, currencyCode: currency)
                }
                if let url = exportedURL {
                    exportDocument = try await Task.detached(priority: .userInitiated) {
                        ExpenseExportDocument(data: try Data(contentsOf: url))
                    }.value
                    showFileExporter = true
                }
            } catch {
                clearExport()
                operationError = error.localizedDescription
            }
        }
    }

    private func clearExport() {
        if let exportedURL { try? FileManager.default.removeItem(at: exportedURL) }
        exportedURL = nil
        exportDocument = nil
    }

    private func prepareReview() {
        importPlan = nil
        guard let pendingSource, let currency = pendingImportCurrencyCode else { return }
        do {
            importPlan = try ExpenseImportService(modelContainer: modelContext.container).plan(
                pendingSource, ledgerCurrencyCode: currency, creatingTagNames: pendingImportTagNames ?? []
            )
        } catch { operationError = error.localizedDescription }
    }

    private var importSummary: some View {
        NavigationStack {
            Form {
                if let plan = importPlan {
                    Section {
                        LabeledContent("Currency", value: plan.currency)
                        LabeledContent("Expenses to Add", value: String(plan.result.inserted))
                        LabeledContent("Expenses to Skip", value: String(plan.result.skipped))
                        if plan.source.ruleCount > 0 {
                            LabeledContent("Recurring Rules to Add", value: String(plan.result.insertedRules))
                            LabeledContent("Recurring Rules to Skip", value: String(plan.result.skippedRules))
                        }
                        LabeledContent("Tags to Create", value: String(plan.result.newTags))
                    } header: {
                        Text("Summary")
                    }
                    if plan.source.requiresCurrencyConsent {
                        Section {
                            Toggle("These amounts were entered in \(plan.currency)", isOn: $legacyCurrencyConsent)
                        } header: {
                            Text("Confirm Legacy Currency")
                        } footer: {
                            Text("This CSV has no currency information. Confirm before importing.")
                        }
                    }
                    if isImporting {
                        Section { operationProgress }
                    } else if plan.result.totalInserted > 0 {
                        Section {
                            Button(plan.source.isCSV ? "Add Every Row" : (plan.source.ruleCount > 0 ? "Add Missing Items" : "Add Missing Expenses")) {
                                guard !isWorking else { return }
                                isImporting = true
                                importTask = Task { await importPendingExpenses() }
                            }
                            .disabled(isWorking || (plan.source.requiresCurrencyConsent && !legacyCurrencyConsent))
                        }
                    } else {
                        Text(plan.source.ruleCount > 0 ? "All expenses and recurring rules are already present. Nothing will be saved." : (plan.source.count == 0 ? "This file contains no expenses." : "All expenses are already present. Nothing will be saved."))
                    }
                }
                if let operationError {
                    Section("Could Not Complete") { Text(operationError).foregroundStyle(.red).textSelection(.enabled) }
                }
            }
            .navigationTitle("Review Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isImporting ? "Cancel Import" : (importPlan?.result.totalInserted == 0 ? "Done" : "Cancel")) {
                        if isImporting { importTask?.cancel() }
                        else { showImportConfirmation = false }
                    }
                }
            }
            .interactiveDismissDisabled(isImporting)
        }
    }

    private func importPendingExpenses() async {
        defer { isImporting = false; importTask = nil }
        guard let importPlan else { return }
        operationError = nil
        importedExpenseCount = 0
        importTotal = importPlan.result.totalInserted
        do {
            let result = try await ExpenseImportService(modelContainer: modelContext.container).execute(
                importPlan, allowLegacy: legacyCurrencyConsent,
                currencyGate: { config.ledgerCurrencyCode },
                progress: { importedExpenseCount = $0 }
            )
            if result.totalInserted > 0 { WidgetCenter.shared.reloadAllTimelines() }
            showImportConfirmation = false
            let message = importPlan.source.ruleCount > 0
                ? "Added \(result.inserted) expenses and \(result.insertedRules) recurring rules; skipped \(result.skipped + result.skippedRules) existing items."
                : "Added \(result.inserted) expenses; skipped \(result.skipped)."
            appRouter.showToast(SageToast(message: message, kind: .success))
        } catch is CancellationError {
            operationError = "Import cancelled. No expenses or recurring rules were saved."
        } catch {
            operationError = error.localizedDescription
            prepareReview()
        }
    }

    private func clearPendingImport() {
        pendingSource = nil
        importPlan = nil
        legacyCurrencyConsent = false
        pendingImportCurrencyCode = nil
        pendingImportTagNames = nil
        unknownTagNames = []
        showImportConfirmation = false
    }
}

nonisolated private struct ExpenseExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json, .commaSeparatedText]
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct UnknownTagsSheet: View {
    let unknownTagNames: [String]
    let onResolve: ([String]) -> Void

    @State private var selectedNames: Set<String>

    init(unknownTagNames: [String], onResolve: @escaping ([String]) -> Void) {
        self.unknownTagNames = unknownTagNames
        self.onResolve = onResolve
        _selectedNames = State(initialValue: Set(unknownTagNames))
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "tag.slash.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
                    .padding(.top, 24)

                Text("Unknown Tags Found")
                    .font(.title3.bold())

                Text("\(unknownTagNames.count) tag\(unknownTagNames.count == 1 ? "" : "s") in this file don't exist yet. Select the ones you'd like to create, or skip to leave those expenses untagged.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }

            List(unknownTagNames, id: \.self) { name in
                Button {
                    if selectedNames.contains(name) {
                        selectedNames.remove(name)
                    } else {
                        selectedNames.insert(name)
                    }
                } label: {
                    HStack {
                        Image(systemName: "tag.fill")
                            .foregroundStyle(.orange)
                        Text(name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedNames.contains(name) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.sageTint)
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedNames.contains(name) ? .isSelected : [])
            }
            .listStyle(.plain)

            VStack(spacing: 10) {
                Button {
                    onResolve(unknownTagNames.filter { selectedNames.contains($0) })
                } label: {
                    Text(selectedNames.isEmpty ? "Continue Without Creating" : "Create \(selectedNames.count) Tag\(selectedNames.count == 1 ? "" : "s")")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.sage)
                        .cornerRadius(15)
                }

                Button("Skip") {
                    onResolve([])
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }
}

#Preview {
    @Previewable @State var container = try! SageModelContainer.make(for: .previewEmpty)

    NavigationStack {
        ExpenseBackupSettingsSection()
    }
    .environmentInjection(container: container)
}
