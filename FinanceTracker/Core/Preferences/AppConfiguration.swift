import Foundation
import CoreFoundation
import SwiftUI
import WidgetKit
import SageKit


// Handles preserving settings for Sage, including wants/needs/savings percentages, smart tagging preferences, appearance, and more.
// Exist as a local storage only, but settings are persisted in iCloud via the PreferenceSyncService, if enabled.
@MainActor @Observable
class AppConfiguration {
    private typealias Key = PreferenceSyncService.Key
    
    private let isPreview: Bool
    private let isUITesting: Bool
    let supportsCloudSync: Bool
    private let defaults: UserDefaults
    private let preferenceSync: PreferenceSyncService
    
    // Locks for cloud sync
    private var isApplyingRemote = false
    private var isRestoringValue = false

    var ledgerCurrencyCode: String {
        didSet {
            guard !isRestoringValue else { return }
            guard LedgerCurrency.validatedCode(ledgerCurrencyCode) != nil else {
                isRestoringValue = true
                ledgerCurrencyCode = oldValue
                isRestoringValue = false
                return
            }
            persist(ledgerCurrencyCode, key: .ledgerCurrency)
            if !isPreview { WidgetCenter.shared.reloadAllTimelines() }
        }
    }
    private(set) var hasCompletedSetupOnAnotherDevice = false
    private(set) var cloudSyncStatus: PreferenceSyncService.Status = .stopped

    func recheckPreferences() { preferenceSync.recheck() }

    static var isBillRemindersEnabled: Bool {
        SagePreferences.defaults.bool(forKey: Keys.billRemindersEnabled)
    }

    // Deliberately excluded from PreferenceSyncService.Key and all cloud snapshots.
    var dashboardWidgetOrder: [DashboardWidgetID] = DashboardWidgetID.defaultOrder {
        didSet {
            if !isPreview {
                defaults.set(dashboardWidgetOrder.map(\.rawValue), forKey: Keys.dashboardWidgetOrder)
            }
        }
    }

    var selectedAppearance: Appearance = .system {
        didSet { persist(selectedAppearance.rawValue, key: .appearance) }
    }
    
    var totalMonthlyIncome: Int = 0 {
        didSet {
            guard !isRestoringValue else { return }
            guard totalMonthlyIncome >= 0 else {
                isRestoringValue = true
                totalMonthlyIncome = oldValue
                isRestoringValue = false
                return
            }
            persist(totalMonthlyIncome, key: .totalMonthlyIncome)
        }
    }
    
    var needsPercent: Double = 0.5 {
        didSet {
            guard !isRestoringValue else { return }
            guard needsPercent.isFinite, (0...1).contains(needsPercent) else {
                isRestoringValue = true
                needsPercent = oldValue
                isRestoringValue = false
                return
            }
            persist(needsPercent, key: .needsPercent)
        }
    }
    
    var wantsPercent: Double = 0.3 {
        didSet {
            guard !isRestoringValue else { return }
            guard wantsPercent.isFinite, (0...1).contains(wantsPercent) else {
                isRestoringValue = true
                wantsPercent = oldValue
                isRestoringValue = false
                return
            }
            persist(wantsPercent, key: .wantsPercent)
        }
    }
    
    var savingsPercent: Double = 0.2 {
        didSet {
            guard !isRestoringValue else { return }
            guard savingsPercent.isFinite, (0...1).contains(savingsPercent) else {
                isRestoringValue = true
                savingsPercent = oldValue
                isRestoringValue = false
                return
            }
            persist(savingsPercent, key: .savingsPercent)
        }
    }
    
    var smartTaggingMode: SmartTaggingMode = .history {
        didSet { persist(smartTaggingMode.rawValue, key: .smartTaggingMode) }
    }

    private(set) var isCloudSyncEnabled: Bool = false {
        didSet {
            guard supportsCloudSync, !isPreview, !isUITesting else { return }
            defaults.set(isCloudSyncEnabled, forKey: Keys.isCloudSyncEnabled)
            if isCloudSyncEnabled {
                preferenceSync.start()
            } else {
                preferenceSync.stop()
                hasCompletedSetupOnAnotherDevice = false
            }
        }
    }

    /// Reports local consent persistence, not iCloud availability or server confirmation.
    @discardableResult
    func updateCloudSyncEnabled(_ enabled: Bool) -> Bool {
        guard supportsCloudSync else { return !enabled }
        isCloudSyncEnabled = enabled
        guard !isPreview, !isUITesting else { return true }
        return defaults.bool(forKey: Keys.isCloudSyncEnabled) == enabled
    }

    var needsColor: Color = Color("NeedColor") {
        didSet {
            guard !isPreview else { return }
            defaults.setSageColor(needsColor, forKey: Keys.needsColor)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    
    var wantsColor: Color = Color("WantColor") {
        didSet {
            guard !isPreview else { return }
            defaults.setSageColor(wantsColor, forKey: Keys.wantsColor)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    
    var savingsColor: Color = Color("SavingColor") {
        didSet {
            guard !isPreview else { return }
            defaults.setSageColor(savingsColor, forKey: Keys.savingsColor)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    
    var billRemindersEnabled: Bool = false {
        didSet {
            guard !isPreview else { return }
            defaults.set(billRemindersEnabled, forKey: Keys.billRemindersEnabled)
        }
    }

    var billReminderDaysBefore: Int = 1 {
        didSet {
            guard !isRestoringValue else { return }
            guard (1...7).contains(billReminderDaysBefore) else {
                isRestoringValue = true
                billReminderDaysBefore = oldValue
                isRestoringValue = false
                return
            }
            if !isPreview { defaults.set(billReminderDaysBefore, forKey: Keys.billReminderDaysBefore) }
        }
    }

    var hideBillReminderDetails: Bool = true {
        didSet {
            if !isPreview { defaults.set(hideBillReminderDetails, forKey: Keys.hideBillReminderDetails) }
        }
    }

    var billReminderTimeMinutes: Int = 540 {
        didSet {
            guard !isRestoringValue else { return }
            guard (0..<1440).contains(billReminderTimeMinutes) else {
                isRestoringValue = true
                billReminderTimeMinutes = oldValue
                isRestoringValue = false
                return
            }
            if !isPreview { defaults.set(billReminderTimeMinutes, forKey: Keys.billReminderTimeMinutes) }
        }
    }

    var dailyExpenseReminderEnabled: Bool = false {
        didSet {
            if !isPreview { defaults.set(dailyExpenseReminderEnabled, forKey: Keys.dailyExpenseReminderEnabled) }
        }
    }

    var dailyExpenseReminderTimeMinutes: Int = 1200 {
        didSet {
            guard !isRestoringValue else { return }
            guard (0..<1440).contains(dailyExpenseReminderTimeMinutes) else {
                isRestoringValue = true
                dailyExpenseReminderTimeMinutes = oldValue
                isRestoringValue = false
                return
            }
            if !isPreview { defaults.set(dailyExpenseReminderTimeMinutes, forKey: Keys.dailyExpenseReminderTimeMinutes) }
        }
    }

    func resetAllSettings() {
        preferenceSync.reset() // Removal is authorized only before disabling consent.
        isCloudSyncEnabled = false
        selectedAppearance = .system
        totalMonthlyIncome = 0
        needsPercent = 0.5
        wantsPercent = 0.3
        savingsPercent = 0.2
        smartTaggingMode = .history
        needsColor = Color("NeedColor")
        wantsColor = Color("WantColor")
        savingsColor = Color("SavingColor")
        billRemindersEnabled = false
        billReminderDaysBefore = 1
        hideBillReminderDetails = true
        billReminderTimeMinutes = 540
        dailyExpenseReminderEnabled = false
        dailyExpenseReminderTimeMinutes = 1200
        dashboardWidgetOrder = DashboardWidgetID.defaultOrder
        ledgerCurrencyCode = isPreview || isUITesting ? "USD" : LedgerCurrency.suggestedCode()
        hasCompletedSetupOnAnotherDevice = false
        
        guard !isPreview else { return }
        
        LedgerCurrency.reset(defaults: defaults)
        let localKeys = Key.allCases.filter { $0 != .ledgerCurrency }.map(\.storageKey) + [
            Keys.isCloudSyncEnabled, Keys.needsColor, Keys.wantsColor, Keys.savingsColor, Keys.billRemindersEnabled,
            Keys.billReminderDaysBefore, Keys.hideBillReminderDetails,
            Keys.billReminderTimeMinutes, Keys.dailyExpenseReminderEnabled, Keys.dailyExpenseReminderTimeMinutes,
        ]
        
        for key in localKeys { defaults.removeObject(forKey: key) }
        
        if supportsCloudSync, !isUITesting { defaults.set(false, forKey: Keys.isCloudSyncEnabled) }
        WidgetCenter.shared.reloadAllTimelines()
    }

    convenience init() {
        if UITestConfiguration.isEnabled {
            self.init(defaults: SagePreferences.defaults, isUITesting: true)
        } else if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            self.init(preview: ())
        } else {
            self.init(defaults: SagePreferences.defaults)
        }
    }

    static var preview: AppConfiguration {
        AppConfiguration(preview: ())
    }

    private init(preview: Void) {
        isPreview = true
        isUITesting = false
        supportsCloudSync = SageModelContainer.supportsCloudSync
        defaults = .standard
        preferenceSync = PreferenceSyncService(hasConsent: { false })

        _ledgerCurrencyCode = "USD"
        _totalMonthlyIncome = 5_000
        _smartTaggingMode = .none
    }

    init(
        defaults: UserDefaults,
        isUITesting: Bool = false,
        supportsCloudSync: Bool = SageModelContainer.supportsCloudSync,
        makeCloudStore: (() -> any CloudPreferenceStore)? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.isPreview = false
        self.isUITesting = isUITesting
        self.supportsCloudSync = supportsCloudSync
        self.defaults = defaults
        preferenceSync = PreferenceSyncService(
            hasConsent: { supportsCloudSync && !isUITesting && defaults.bool(forKey: Keys.isCloudSyncEnabled) },
            makeStore: makeCloudStore,
            notificationCenter: notificationCenter
        )
        
        // Initialize @Observable storage directly so loading never invokes persistence observers.
        _ledgerCurrencyCode = LedgerCurrency.persistedCode(defaults: defaults)
            ?? (isUITesting ? "USD" : LedgerCurrency.suggestedCode())
        
        _isCloudSyncEnabled = supportsCloudSync && !isUITesting && defaults.bool(forKey: Keys.isCloudSyncEnabled)

        _dashboardWidgetOrder = DashboardWidgetID.resolvedOrder(
            defaults.stringArray(forKey: Keys.dashboardWidgetOrder) ?? []
        )
        
        if let raw = defaults.string(forKey: Key.appearance.storageKey), let appearance = Appearance(rawValue: raw) {
            _selectedAppearance = appearance
        }
        
        if let number = Self.number(defaults.object(forKey: Key.totalMonthlyIncome.storageKey)),
           number >= 0, let income = Int(exactly: number) {
            _totalMonthlyIncome = income
        }
        
        let needs = Self.number(defaults.object(forKey: Key.needsPercent.storageKey)) ?? _needsPercent
        let wants = Self.number(defaults.object(forKey: Key.wantsPercent.storageKey)) ?? _wantsPercent
        let savings = Self.number(defaults.object(forKey: Key.savingsPercent.storageKey)) ?? _savingsPercent
        if [needs, wants, savings].allSatisfy({ (0...1).contains($0) }),
           abs(needs + wants + savings - 1) < 0.000001 {
            _needsPercent = needs
            _wantsPercent = wants
            _savingsPercent = savings
        }
        
        if let raw = defaults.string(forKey: Key.smartTaggingMode.storageKey), let mode = SmartTaggingMode(rawValue: raw) {
            _smartTaggingMode = mode
        }
        
        _needsColor = defaults.sageColor(forKey: Keys.needsColor) ?? _needsColor
        _wantsColor = defaults.sageColor(forKey: Keys.wantsColor) ?? _wantsColor
        _savingsColor = defaults.sageColor(forKey: Keys.savingsColor) ?? _savingsColor
        
        _billRemindersEnabled = defaults.bool(forKey: Keys.billRemindersEnabled)
        
        let reminderDays = defaults.integer(forKey: Keys.billReminderDaysBefore)
        if (1...7).contains(reminderDays) { _billReminderDaysBefore = reminderDays }
        
        _hideBillReminderDetails = defaults.object(forKey: Keys.hideBillReminderDetails) as? Bool ?? _hideBillReminderDetails
        
        if let minutes = defaults.object(forKey: Keys.billReminderTimeMinutes) as? Int, (0..<1440).contains(minutes) {
            _billReminderTimeMinutes = minutes
        }
        
        _dailyExpenseReminderEnabled = defaults.bool(forKey: Keys.dailyExpenseReminderEnabled)
        
        if let minutes = defaults.object(forKey: Keys.dailyExpenseReminderTimeMinutes) as? Int, (0..<1440).contains(minutes) {
            _dailyExpenseReminderTimeMinutes = minutes
        }

        // All observable fields must exist before a synchronous startup snapshot is delivered.
        preferenceSync.onChange = { [weak self] in self?.applyRemote($0) }
        preferenceSync.onStatusChange = { [weak self] status in
            guard let self else { return }
            if status == .accountChanged { self.updateCloudSyncEnabled(false) }
            self.cloudSyncStatus = status
        }
        
        if isCloudSyncEnabled { preferenceSync.start() }
        
        // Keep widget-facing defaults populated without sending fallback values to iCloud.
        defaults.set(dashboardWidgetOrder.map(\.rawValue), forKey: Keys.dashboardWidgetOrder)
        let localValues: [Key: Any] = [
            .ledgerCurrency: ledgerCurrencyCode,
            .appearance: selectedAppearance.rawValue, .totalMonthlyIncome: totalMonthlyIncome,
            .needsPercent: needsPercent, .wantsPercent: wantsPercent, .savingsPercent: savingsPercent,
            .smartTaggingMode: smartTaggingMode.rawValue,
        ]
        for (key, value) in localValues { defaults.set(value, forKey: key.storageKey) }
        defaults.setSageColor(needsColor, forKey: Keys.needsColor)
        defaults.setSageColor(wantsColor, forKey: Keys.wantsColor)
        defaults.setSageColor(savingsColor, forKey: Keys.savingsColor)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    func markSetupComplete() { preferenceSync.markSetupComplete() }

    func resetRemoteSetup() {
        preferenceSync.publish([.hasCompletedSetup: false])
        hasCompletedSetupOnAnotherDevice = false
    }
}

// Wants/Needs updating clamping logic
extension AppConfiguration {
    func updateNeeds(_ newNeeds: Double) {
        guard newNeeds.isFinite else { return }
        let needs = min(max(newNeeds, 0), 1)
        let wants = needs + wantsPercent > 1
            ? min(round((1 - needs) / 0.05) * 0.05, 1 - needs) : wantsPercent
        needsPercent = needs
        wantsPercent = wants
        savingsPercent = max(1 - needs - wants, 0)
        if !isPreview { WidgetCenter.shared.reloadAllTimelines() }
    }

    func updateWants(_ newWants: Double) {
        guard newWants.isFinite else { return }
        let wants = min(max(newWants, 0), 1)
        let needs = needsPercent + wants > 1
            ? min(round((1 - wants) / 0.05) * 0.05, 1 - wants) : needsPercent
        needsPercent = needs
        wantsPercent = wants
        savingsPercent = max(1 - needs - wants, 0)
        if !isPreview { WidgetCenter.shared.reloadAllTimelines() }
    }
}

// Sync helper functions
extension AppConfiguration {
    
    // Persist locally before publishing.
    private func persist(_ value: Any, key: Key) {
        guard !isPreview else { return }
        
        defaults.set(value, forKey: key.storageKey)
        
        // If we're applying a change from elsewhere already, then skip publishing
        guard !isApplyingRemote else { return }
        
        var values = [key: value]
        if Key.allocation.contains(key) {
            guard abs(needsPercent + wantsPercent + savingsPercent - 1) < 0.000001 else { return }
            values = [.needsPercent: needsPercent, .wantsPercent: wantsPercent, .savingsPercent: savingsPercent]
        }
        
        preferenceSync.publish(values)
    }

    // Apply changes from remote to the local config
    private func applyRemote(_ snapshot: PreferenceSyncService.Snapshot) {
        isApplyingRemote = true
        defer { isApplyingRemote = false }
        if let code = LedgerCurrency.validatedCode(snapshot[.ledgerCurrency] as? String) {
            ledgerCurrencyCode = code
        }
        if let raw = snapshot[.appearance] as? String, let value = Appearance(rawValue: raw) {
            selectedAppearance = value
        }
        if let raw = snapshot[.smartTaggingMode] as? String, let value = SmartTaggingMode(rawValue: raw) {
            smartTaggingMode = value
        }
        if snapshot.keys.contains(.hasCompletedSetup) {
            let value = snapshot[.hasCompletedSetup] as? NSNumber
            hasCompletedSetupOnAnotherDevice = value.map { CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue } ?? false
        }
        if let number = Self.number(snapshot[.totalMonthlyIncome]), number >= 0, let income = Int(exactly: number) {
            totalMonthlyIncome = income
        }
        if let needs = Self.number(snapshot[.needsPercent]), let wants = Self.number(snapshot[.wantsPercent]),
           let savings = Self.number(snapshot[.savingsPercent]),
           [needs, wants, savings].allSatisfy({ (0...1).contains($0) }),
           abs(needs + wants + savings - 1) < 0.000001 {
            needsPercent = needs
            wantsPercent = wants
            savingsPercent = savings
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// Computed properties
extension AppConfiguration {
    var categoryColors: CategoryColors {
        CategoryColors(needs: needsColor, wants: wantsColor, savings: savingsColor)
    }
    
    var needsBudget: Double { Double(totalMonthlyIncome) * needsPercent }
    var wantsBudget: Double { Double(totalMonthlyIncome) * wantsPercent }
    var savingsBudget: Double { Double(totalMonthlyIncome) * savingsPercent }
}

// Enums
extension AppConfiguration {
    enum Keys {
        static let dashboardWidgetOrder = "dashboardWidgetOrder"
        static let isCloudSyncEnabled = SageModelContainer.cloudKitPreferenceKey
        static let needsColor = "categoryColorNeeds"
        static let wantsColor = "categoryColorWants"
        static let savingsColor = "categoryColorSavings"
        static let billRemindersEnabled = "billRemindersEnabled"
        static let billReminderDaysBefore = "billReminderDaysBefore"
        static let hideBillReminderDetails = "hideBillReminderDetails"
        static let billReminderTimeMinutes = "billReminderTimeMinutes"
        static let dailyExpenseReminderEnabled = "dailyExpenseReminderEnabled"
        static let dailyExpenseReminderTimeMinutes = "dailyExpenseReminderTimeMinutes"
    }
    
    enum Appearance: String, CaseIterable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"

        var colorScheme: ColorScheme? {
            switch self {
            case .light: return .light
            case .dark: return .dark
            case .system: return nil
            }
        }
    }

    enum SmartTaggingMode: String, CaseIterable {
        case history = "History"
        case ai = "AI"
        case both = "History + AI"
        case none = "None"
    }
}
