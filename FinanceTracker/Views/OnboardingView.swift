//
//  OnboardingView.swift
//  FinanceTracker
//
//  Created by Enzo on 10/21/25.
//

import SwiftUI
import WidgetKit
import SwiftData
import SageKit
import UserNotifications

struct OnboardingView: View {
    @Environment(AppConfiguration.self) var config
    @Environment(\.modelContext) private var modelContext
    @Environment(\.categoryColors) private var categoryColors
    @Environment(\.recurringReminders) private var reminders
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .largeTitle) private var incomeFontSize = 64

    @AppStorage("hasOpenedAppOnce") var hasOpenedAppOnce = false

    @State private var currentStep: OnboardingStep = .welcome
    @State private var incomeText = ""
    @State private var incomeHeaderHeight: CGFloat?
    @State private var incomeFrequency: IncomeFrequency = .monthly
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedCurrencyCode = LedgerCurrency.suggestedCode()
    @State private var didLoadCurrency = false
    @State private var needsPercent: Double = 50
    @State private var wantsPercent: Double = 30
    @State private var cloudSyncEnabled = false
    @State private var tagTemplates = ExpenseTag.suggestedTags
    @State private var selectedTagNames: Set<String> = Set(ExpenseTag.suggestedTags.map(\.name))
    @State private var recurringRemindersEnabled = false
    @State private var dailyReminderEnabled = false
    @State private var requestingNotificationPermission = false
    @State private var notificationPermissionMessage: String?
    @State private var completionErrorMessage: String?
    @FocusState private var incomeFocused: Bool
    @AccessibilityFocusState private var headingFocused: Bool

    private let onCompletion: (() -> Void)?
    private var currencyCode: String { selectedCurrencyCode }

    enum OnboardingStep: Int, CaseIterable, Hashable {
        case welcome, budget, allocation, sync, tags, reminders, complete

        var buttonIdentifier: String {
            switch self {
            case .welcome: "onboarding-get-started-button"
            case .budget: "onboarding-budget-continue-button"
            case .allocation: "onboarding-allocation-continue-button"
            case .sync: "onboarding-sync-continue-button"
            case .tags: "onboarding-tags-continue-button"
            case .reminders: "onboarding-reminders-continue-button"
            case .complete: "onboarding-start-tracking-button"
            }
        }
    }

    private var savingsPercent: Double { round(max(0, 100 - needsPercent - wantsPercent)) }
    private var monthlyIncome: Int? {
        Int(incomeText).map { incomeFrequency.monthlyIncome(for: $0) }
    }
    private var income: Double { Double(monthlyIncome ?? 0) }
    private var showsMonthlyEquivalent: Bool {
        incomeFrequency != .monthly && (monthlyIncome ?? 0) > 0
    }

    init(step: OnboardingStep = .welcome, onCompletion: (() -> Void)? = nil) {
        _currentStep = State(initialValue: step)
        self.onCompletion = onCompletion
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    if currentStep == .budget {
                        budgetPage
                    } else {
                        ScrollView {
                            pageContent
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .defaultScrollAnchor(.center, for: .alignment)
                        .scrollBounceBehavior(.basedOnSize)
                        .id(currentStep)
                    }
                }
                .frame(maxWidth: 520, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 0) {
                    primaryAction
                    // Keep actions outside the scroll viewport so they cannot cover the income strip.
                    if incomeFocused {
                        HStack {
                            Spacer()
                            Button("Done") { incomeFocused = false }
                                .buttonStyle(.glass)
                                .accessibilityIdentifier("onboarding-keyboard-done-button")
                        }
                        .frame(maxWidth: 520)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                    }
                }
            }
            .background {
                ZStack(alignment: .topTrailing) {
                    Color.sageBackground
                    if !reduceTransparency {
                        Ellipse()
                            .fill(Color.sage.opacity(0.24))
                            .frame(width: 360, height: 420)
                            .blur(radius: 85)
                            .offset(x: 120, y: -150)
                    }
                }
                .ignoresSafeArea()
            }
            .toolbar(.hidden, for: .navigationBar)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: currentStep)
            .task(id: currentStep) { headingFocused = true }
            .alert("Could not finish setup", isPresented: Binding(
                get: { completionErrorMessage != nil },
                set: { if !$0 { completionErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(completionErrorMessage ?? "Check available storage and try again.")
            }
            .alert("Notifications are off", isPresented: Binding(
                get: { notificationPermissionMessage != nil },
                set: { if !$0 { notificationPermissionMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(notificationPermissionMessage ?? "")
            }
        }
        .fontDesign(.rounded)
        .tint(.sage)
        .onAppear {
            guard !didLoadCurrency else { return }
            didLoadCurrency = true
            recurringRemindersEnabled = config.billRemindersEnabled
            dailyReminderEnabled = config.dailyExpenseReminderEnabled
            if !UITestConfiguration.isEnabled {
                selectedCurrencyCode = config.ledgerCurrencyCode
            }
        }
    }

    private var primaryAction: some View {
        HStack(spacing: 12) {
            if currentStep != .welcome {
                Button {
                    move(to: OnboardingStep(rawValue: currentStep.rawValue - 1) ?? .welcome)
                } label: {
                    Text("Back")
                        .font(.headline)
                        .frame(minWidth: 52, minHeight: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.roundedRectangle(radius: 22))
                .accessibilityIdentifier("onboarding-back-button")
            }
            Button {
                if currentStep == .complete {
                    completeOnboarding()
                } else if let next = OnboardingStep(rawValue: currentStep.rawValue + 1) {
                    move(to: next)
                }
            } label: {
                Text(requestingNotificationPermission ? "Requesting permission..." : currentStep == .welcome ? "Get Started" : currentStep == .complete ? "Start Tracking" : "Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(Color(red: 0.10, green: 0.17, blue: 0.07))
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.roundedRectangle(radius: 22))
            .tint(.sage)
            .disabled(currentStep == .budget && (monthlyIncome ?? 0) <= 0)
            .accessibilityIdentifier(currentStep.buttonIdentifier)
        }
        .disabled(requestingNotificationPermission)
        .frame(maxWidth: 520)
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                colors: [Color.sageBackground.opacity(0), .sageBackground, .sageBackground],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch currentStep {
        case .welcome: welcomePage
        case .budget: budgetPage
        case .allocation: allocationPage
        case .sync: syncPage
        case .tags: tagsPage
        case .reminders: remindersPage
        case .complete: completePage
        }
    }

    private func heading(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.custom("MomoTrustDisplay-Regular", size: 32, relativeTo: .largeTitle))
                .fontDesign(nil)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
                .accessibilityIdentifier(currentStep == .welcome ? "onboarding-welcome-title" : "onboarding-step-title")
            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(currentStep == .welcome ? "onboarding-welcome-subtitle" : "onboarding-step-subtitle")
            }
        }
    }

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 28) {
            Image("LaunchIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)
                .accessibilityHidden(true)
            heading("welcome to syl", subtitle: "A simple personal expense tracking app")
        }
    }

    private var budgetPage: some View {
        VStack(spacing: 28) {
            // Only the introduction yields space to the keyboard. The entire income
            // card, including its reserved footer, stays above the navigation row.
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    heading("your income", subtitle: "Enter your take-home pay. We'll work out your monthly budget.")

                    VStack(alignment: .leading, spacing: 12) {
                        Text("How often are you paid?")
                            .font(.headline)
                        if dynamicTypeSize.isAccessibilitySize {
                            incomeFrequencyPicker.pickerStyle(.menu)
                        } else {
                            incomeFrequencyPicker.pickerStyle(.segmented)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    incomeHeaderHeight = height
                }
            }
            .defaultScrollAnchor(.bottom)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: incomeHeaderHeight)
            .layoutPriority(-1)

            incomeCard
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: .infinity)
    }

    private var incomeCard: some View {
        VStack(spacing: -24) {
            VStack(spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("Take-home pay")
                            .font(.headline)
                        Spacer()
                        currencyPicker
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Take-home pay")
                            .font(.headline)
                        currencyPicker
                    }
                }

                TextField("0", text: $incomeText)
                    .font(.system(size: incomeFontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .focused($incomeFocused)
                    .tint(.sage)
                    .accessibilityLabel("Take-home income")
                    .accessibilityHint("Enter your income in whole currency units, \(incomeFrequency.periodDescription)")
                    .accessibilityIdentifier("onboarding-income-field")
                    .onChange(of: incomeText) { _, newValue in
                        incomeText = String(newValue.filter { $0.isASCII && $0.isNumber }.prefix(8))
                    }
                Text(incomeFrequency.periodDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 24)
            .background(Color.cardBackground, in: .rect(cornerRadius: 24))
            .zIndex(1)

            LabeledContent {
                Group {
                    if showsMonthlyEquivalent {
                        Text(income, format: .currency(code: currencyCode).precision(.fractionLength(0)))
                            .accessibilityIdentifier("onboarding-monthly-equivalent")
                    } else {
                        Text(" ").accessibilityHidden(true)
                    }
                }
                .font(.subheadline.bold())
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            } label: {
                Text("Monthly equivalent")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityHint(incomeFrequency.calculationDescription)
            .padding(.horizontal, 16)
            .padding(.top, 36)
            .padding(.bottom, 12)
            .background(Color.sage.opacity(0.12), in: .rect(cornerRadius: 20))
            .padding(.horizontal, 12)
            // Reserve the strip's space so entering the first digit cannot move the card.
            .visualEffect { content, geometry in
                content.offset(y: showsMonthlyEquivalent || reduceMotion ? 0 : -geometry.size.height)
            }
            .opacity(showsMonthlyEquivalent ? 1 : 0)
            .accessibilityElement(children: .contain)
            .accessibilityHidden(!showsMonthlyEquivalent)
            .allowsHitTesting(showsMonthlyEquivalent)
        }
        .clipped()
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.78), value: showsMonthlyEquivalent)
    }

    private var incomeFrequencyPicker: some View {
        Picker("Pay frequency", selection: $incomeFrequency) {
            ForEach(IncomeFrequency.allCases) { frequency in
                Text(frequency.rawValue).tag(frequency)
            }
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier("onboarding-income-frequency-picker")
    }

    private var currencyPicker: some View {
        Picker("Currency", selection: $selectedCurrencyCode) {
            ForEach(LedgerCurrency.supportedCodes, id: \.self) { code in
                Text("\(code) - \(Locale.current.localizedString(forCurrencyCode: code) ?? code)")
                    .tag(code)
                    .accessibilityIdentifier("onboarding-currency-\(code)")
            }
        } currentValueLabel: {
            Text(currencyCode)
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(minHeight: 44)
        .accessibilityIdentifier("onboarding-currency-picker")
        .accessibilityValue(currencyCode)
        .onChange(of: selectedCurrencyCode) { incomeFocused = false }
    }

    private var allocationPage: some View {
        VStack(alignment: .leading, spacing: 28) {
            heading("set your budget", subtitle: "Drag the dividers to adjust your budget.")

            VStack(alignment: .leading, spacing: 24) {
                BudgetAllocationBar(needsPercent: $needsPercent, wantsPercent: $wantsPercent)
                BudgetSummaryRow(title: "Needs (\((needsPercent / 100).formatted(.percent.precision(.fractionLength(0)))))", amount: income * needsPercent / 100, currencyCode: currencyCode, color: categoryColors.needs, icon: "house.fill")
                BudgetSummaryRow(title: "Wants (\((wantsPercent / 100).formatted(.percent.precision(.fractionLength(0)))))", amount: income * wantsPercent / 100, currencyCode: currencyCode, color: categoryColors.wants, icon: "cart.fill")
                BudgetSummaryRow(title: "Savings (\((savingsPercent / 100).formatted(.percent.precision(.fractionLength(0)))))", amount: income * savingsPercent / 100, currencyCode: currencyCode, color: categoryColors.savings, icon: "banknote.fill")
            }
        }
    }

    private var syncPage: some View {
        VStack(alignment: .leading, spacing: 28) {
            heading("sync your expenses", subtitle: "Keep expenses up to date across your devices.")

            HStack(spacing: 24) {
                Image(systemName: "iphone")
                Image(systemName: "icloud")
                    .foregroundStyle(.sage)
                Image(systemName: "ipad.landscape")
            }
            .font(.system(size: 40, weight: .light))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 16) {
                Toggle("Enable iCloud Sync", isOn: $cloudSyncEnabled)
                    .font(.headline)
                    .tint(.sage)
                    .accessibilityIdentifier("onboarding-sync-toggle")
                    .disabled(!config.supportsCloudSync)
                Text(!config.supportsCloudSync ? "iCloud sync is unavailable in this dev build." : cloudSyncEnabled ? "Preference sync starts when you finish setup. Fully close and reopen Syl to enable expense sync." : "Preferences stay on this device. If expense sync was previously enabled, fully close and reopen Syl to turn it off.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardBackground, in: .rect(cornerRadius: 24))
        }
    }

    private var tagsPage: some View {
        VStack(alignment: .leading, spacing: 28) {
            heading("choose your tags", subtitle: "Organize your expenses. You can add more later.")

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("\(selectedTagNames.count) selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("onboarding-tags-count")
                    Spacer()
                    Button(selectedTagNames.count == tagTemplates.count ? "Clear" : "Select all") {
                        selectedTagNames = selectedTagNames.count == tagTemplates.count ? [] : Set(tagTemplates.map(\.name))
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("onboarding-select-all-tags-button")
                }
                TagFlowGrid(tags: tagTemplates, selectedTagNames: $selectedTagNames)
            }
        }
    }

    private var remindersPage: some View {
        VStack(alignment: .leading, spacing: 28) {
            heading("enable reminders?", subtitle: "Get reminded when recurring expenses are due, and a daily reminder to add expenses from the day.")

            VStack(alignment: .leading, spacing: 24) {
                Toggle(isOn: Binding(
                    get: { recurringRemindersEnabled },
                    set: {
                        recurringRemindersEnabled = $0
                        if $0 { requestNotificationPermission() }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recurring expenses")
                            .font(.headline)
                        Text("Get a reminder before recurring expenses are due.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("onboarding-recurring-reminders-toggle")

                Divider()

                Toggle(isOn: Binding(
                    get: { dailyReminderEnabled },
                    set: {
                        dailyReminderEnabled = $0
                        if $0 { requestNotificationPermission() }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Daily reminder")
                            .font(.headline)
                        Text("Remember to add your expenses at the end of the day.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("onboarding-daily-reminder-toggle")
            }
            .disabled(requestingNotificationPermission)
            .padding(24)
            .background(Color.cardBackground, in: .rect(cornerRadius: 24))

        }
    }

    private var completePage: some View {
        VStack(alignment: .leading, spacing: 28) {
            heading("your budget is ready", subtitle: "Here's your monthly breakdown.")
            budgetCard
        }
    }

    private var allocationBar: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                categoryColors.needs.frame(width: geometry.size.width * needsPercent / 100)
                categoryColors.wants.frame(width: geometry.size.width * wantsPercent / 100)
                categoryColors.savings.frame(width: geometry.size.width * savingsPercent / 100)
            }
        }
        .frame(height: 10)
        .clipShape(.capsule)
        .accessibilityHidden(true)
    }

    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(income, format: .currency(code: currencyCode).precision(.fractionLength(0)))
                .font(.largeTitle.bold())
                .monospacedDigit()
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding-plan-total")
            allocationBar
            BudgetSummaryRow(title: "Needs", amount: income * needsPercent / 100, currencyCode: currencyCode, color: categoryColors.needs, icon: "house.fill")
            BudgetSummaryRow(title: "Wants", amount: income * wantsPercent / 100, currencyCode: currencyCode, color: categoryColors.wants, icon: "cart.fill")
            BudgetSummaryRow(title: "Savings", amount: income * savingsPercent / 100, currencyCode: currencyCode, color: categoryColors.savings, icon: "banknote.fill")
        }
        .padding(24)
        .background(Color.cardBackground, in: .rect(cornerRadius: 24))
    }

    private func move(to step: OnboardingStep) {
        incomeFocused = false
        headingFocused = false
        currentStep = step
    }

    private func requestNotificationPermission() {
        guard !requestingNotificationPermission, reminders != nil else { return }
        requestingNotificationPermission = true
        Task { @MainActor in
            defer {
                requestingNotificationPermission = false
            }
            let center = UNUserNotificationCenter.current()
            do {
                if await center.notificationSettings().authorizationStatus == .notDetermined {
                    _ = try await center.requestAuthorization(options: [.alert, .sound])
                }
                if await center.notificationSettings().authorizationStatus == .denied {
                    notificationPermissionMessage = "You can finish setup without notifications. Your reminder choices will be saved, but delivery is blocked until you allow notifications in iOS Settings."
                }
            } catch {
                notificationPermissionMessage = "Syl could not request notification permission. You can finish setup and try again from Settings. \(error.localizedDescription)"
            }
        }
    }

    private func completeOnboarding() {
        guard (monthlyIncome ?? 0) > 0 else { return }
        guard config.updateCloudSyncEnabled(cloudSyncEnabled) else {
            completionErrorMessage = "Syl could not save your sync preference. Try again."
            return
        }
        do {
            for tag in tagTemplates where selectedTagNames.contains(tag.name) {
                modelContext.insert(tag)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            completionErrorMessage = "Syl could not finish setup. \(error.localizedDescription)"
            return
        }

        config.ledgerCurrencyCode = currencyCode
        config.totalMonthlyIncome = monthlyIncome ?? 0
        config.needsPercent = needsPercent / 100
        config.wantsPercent = wantsPercent / 100
        config.savingsPercent = savingsPercent / 100
        config.billRemindersEnabled = recurringRemindersEnabled
        config.dailyExpenseReminderEnabled = dailyReminderEnabled
        reminders?.refresh()
        config.markSetupComplete()
        WhatsNewStore.markCurrentVersionSeen()
        WidgetCenter.shared.reloadAllTimelines()

        withAnimation(reduceMotion ? nil : .default) {
            hasOpenedAppOnce = true
            onCompletion?()
        }
    }
}

struct TagFlowGrid: View {
    let tags: [ExpenseTag]
    @Binding var selectedTagNames: Set<String>

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(stride(from: 0, to: tags.count, by: 2)), id: \.self) { index in
                HStack(spacing: 12) {
                    tagButton(tags[index])
                    if index + 1 < tags.count {
                        tagButton(tags[index + 1])
                    }
                }
            }
        }
    }

    private func tagButton(_ tag: ExpenseTag) -> some View {
        let isSelected = selectedTagNames.contains(tag.name)
        return Button {
            if isSelected {
                selectedTagNames.remove(tag.name)
            } else {
                selectedTagNames.insert(tag.name)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tag.symbolName ?? "tag")
                    .accessibilityHidden(true)
                Text(tag.name)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.primary)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(isSelected ? Color.sage.opacity(0.2) : Color.cardBackground, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.sage : Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding-tag-\(tag.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    var tint: Color = .sage

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct BudgetSummaryRow: View {
    let title: LocalizedStringKey
    let amount: Double
    let currencyCode: String
    let color: Color
    let icon: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Label(title, systemImage: icon)
                Spacer(minLength: 12)
                Text(amount, format: .currency(code: currencyCode))
                    .fontWeight(.semibold)
                    .fixedSize()
            }
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                Text(amount, format: .currency(code: currencyCode))
                    .fontWeight(.semibold)
            }
        }
        .font(.body)
        .monospacedDigit()
        .textSelection(.enabled)
        .labelStyle(OnboardingCategoryLabelStyle(color: color))
        .accessibilityElement(children: .combine)
    }
}

private struct OnboardingCategoryLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12), in: .rect(cornerRadius: 8))
            configuration.title
        }
    }
}

struct WelcomeViewPreviews: PreviewProvider {
    static var previews: some View {
        ForEach(OnboardingView.OnboardingStep.allCases, id: \.self) { step in
            OnboardingView(step: step)
                .environmentInjection(empty: true)
                .previewDisplayName(String(describing: step))
        }
    }
}
