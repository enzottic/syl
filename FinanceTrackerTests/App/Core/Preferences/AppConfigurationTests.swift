import Foundation
import Observation
import SageKit
import SwiftUI
import Testing

@Suite("App configuration integration", .serialized)
@MainActor
struct AppConfigurationTests {
    private typealias Key = PreferenceSyncService.Key

    @Test
    func previewUsesSampleValuesAndDoesNotPersistEditsOrReset() throws {
        let storedValues = UserDefaults.standard.dictionaryRepresentation() as NSDictionary
        let config = AppConfiguration.preview

        #expect(config.dashboardWidgetOrder == DashboardWidgetID.defaultOrder)
        #expect(config.selectedAppearance == .system)
        #expect(config.totalMonthlyIncome == 5_000)
        #expect(config.needsPercent == 0.5)
        #expect(config.wantsPercent == 0.3)
        #expect(config.savingsPercent == 0.2)
        #expect(config.smartTaggingMode == .none)
        #expect(config.needsColor == Color("NeedColor"))
        #expect(config.wantsColor == Color("WantColor"))
        #expect(config.savingsColor == Color("SavingColor"))
        #expect(!config.billRemindersEnabled)
        #expect(config.billReminderDaysBefore == 1)
        #expect(config.hideBillReminderDetails)
        #expect(config.billReminderTimeMinutes == 540)
        #expect(!config.dailyExpenseReminderEnabled)
        #expect(config.dailyExpenseReminderTimeMinutes == 1200)
        #expect(config.ledgerCurrencyCode == "USD")
        #expect(!config.isCloudSyncEnabled)
        #expect(config.cloudSyncStatus == .stopped)
        #expect(storedValues.isEqual(to: UserDefaults.standard.dictionaryRepresentation()))

        config.totalMonthlyIncome = 9000
        config.selectedAppearance = .dark
        config.smartTaggingMode = .both
        config.updateNeeds(0.6)
        config.updateWants(0.2)
        config.dashboardWidgetOrder.reverse()
        config.needsColor = .red
        config.wantsColor = .green
        config.savingsColor = .blue
        config.billRemindersEnabled = true
        config.billReminderDaysBefore = 7
        config.hideBillReminderDetails = false
        config.billReminderTimeMinutes = 0
        config.dailyExpenseReminderEnabled = true
        config.dailyExpenseReminderTimeMinutes = 1439
        config.updateCloudSyncEnabled(true)
        config.recheckPreferences()
        config.markSetupComplete()
        config.ledgerCurrencyCode = "EUR"
        #expect(config.ledgerCurrencyCode == "EUR")
        #expect(config.cloudSyncStatus == .stopped)
        #expect(storedValues.isEqual(to: UserDefaults.standard.dictionaryRepresentation()))

        let freshPreview = AppConfiguration.preview
        #expect(freshPreview.totalMonthlyIncome == 5_000)
        #expect(freshPreview.ledgerCurrencyCode == "USD")
        config.resetAllSettings()
        #expect(config.totalMonthlyIncome == 0)
        #expect(config.smartTaggingMode == .history)
        #expect(config.ledgerCurrencyCode == "USD")
        #expect(storedValues.isEqual(to: UserDefaults.standard.dictionaryRepresentation()))
    }

    @Test
    func uiTestingLoadsLocalSettingsWithoutPreviewValuesOrCloudAccess() throws {
        let fixture = try Fixture(enabled: true)
        fixture.defaults.set(3200, forKey: Key.totalMonthlyIncome.storageKey)
        fixture.defaults.set("Dark", forKey: Key.appearance.storageKey)
        let config = AppConfiguration(
            defaults: fixture.defaults,
            isUITesting: true,
            supportsCloudSync: true,
            makeCloudStore: {
                Issue.record("UI tests must never acquire an iCloud store")
                return fixture.cloud
            }
        )

        #expect(config.totalMonthlyIncome == 3200)
        #expect(config.selectedAppearance == .dark)
        #expect(config.smartTaggingMode == .history)
        #expect(config.ledgerCurrencyCode == "USD")
        #expect(!config.isCloudSyncEnabled)
        config.totalMonthlyIncome = 4200
        #expect(fixture.defaults.integer(forKey: Key.totalMonthlyIncome.storageKey) == 4200)
        config.updateCloudSyncEnabled(true)
        config.recheckPreferences()
        config.ledgerCurrencyCode = "GBP"
        #expect(fixture.defaults.string(forKey: LedgerCurrency.storageKey) == "GBP")
        let reopened = AppConfiguration(defaults: fixture.defaults, isUITesting: true)
        #expect(reopened.ledgerCurrencyCode == "GBP")
        config.resetAllSettings()
        #expect(config.ledgerCurrencyCode == "USD")
        #expect(fixture.defaults.object(forKey: LedgerCurrency.storageKey) == nil)
        #expect(fixture.cloud.operations.isEmpty)
        #expect(config.cloudSyncStatus == .stopped)
    }

    @Test
    func dashboardOrderPersistsLocallyAndIgnoresCloudChanges() async throws {
        let fixture = try Fixture(enabled: true, currency: "USD")
        fixture.cloud.values[Key.ledgerCurrency.storageKey] = "USD"
        let config = fixture.config
        #expect(fixture.defaults.stringArray(forKey: "dashboardWidgetOrder") == DashboardWidgetID.defaultOrder.map(\.rawValue))
        let order = Array(DashboardWidgetID.defaultOrder(isPad: false).reversed())
        fixture.cloud.operations.removeAll()
        config.dashboardWidgetOrder = order
        #expect(fixture.cloud.operations.isEmpty)
        #expect(fixture.defaults.stringArray(forKey: "dashboardWidgetOrder") == order.map(\.rawValue))
        #expect(fixture.makeConfiguration().dashboardWidgetOrder == order)

        fixture.cloud.values["dashboardWidgetOrder"] = ["needs", "savings"]
        fixture.post(keys: ["dashboardWidgetOrder"])
        await drainNotifications()
        #expect(config.dashboardWidgetOrder == order)
        #expect(!fixture.cloud.writtenKeys.contains("dashboardWidgetOrder"))

        let otherDevice = try Fixture()
        #expect(otherDevice.config.dashboardWidgetOrder == DashboardWidgetID.defaultOrder)
        otherDevice.defaults.set([], forKey: "dashboardWidgetOrder")
        #expect(otherDevice.makeConfiguration().dashboardWidgetOrder == DashboardWidgetID.defaultOrder)
        #expect(otherDevice.defaults.stringArray(forKey: "dashboardWidgetOrder") == DashboardWidgetID.defaultOrder.map(\.rawValue))
        config.dashboardWidgetOrder = DashboardWidgetID.defaultOrder
        #expect(fixture.makeConfiguration().dashboardWidgetOrder == DashboardWidgetID.defaultOrder)
        #expect(!fixture.cloud.writtenKeys.contains("dashboardWidgetOrder"))

        config.dashboardWidgetOrder = order
        config.resetAllSettings()
        #expect(config.dashboardWidgetOrder == DashboardWidgetID.defaultOrder)
        #expect(fixture.defaults.stringArray(forKey: "dashboardWidgetOrder") == DashboardWidgetID.defaultOrder.map(\.rawValue))
    }

    @Test
    func localOnlyConfigurationRejectsOptInWithoutCloudAccessOrChangingConsent() async throws {
        let fixture = try Fixture(enabled: true, currency: "USD")
        fixture.defaults.set(true, forKey: LedgerCurrency.storageKey + ".conflict")
        let config = fixture.makeConfiguration(supportsCloudSync: false)
        #expect(!config.isCloudSyncEnabled)
        #expect(!config.updateCloudSyncEnabled(true))
        #expect(config.updateCloudSyncEnabled(false))
        config.selectedAppearance = .dark
        config.totalMonthlyIncome = 4200
        config.markSetupComplete()
        config.resetRemoteSetup()
        config.recheckPreferences()
        config.ledgerCurrencyCode = "EUR"
        #expect(LedgerCurrency.persistedCode(defaults: fixture.defaults) == "EUR")
        fixture.post(reason: NSUbiquitousKeyValueStoreAccountChange)
        await drainNotifications()
        #expect(fixture.defaults.bool(forKey: SageModelContainer.cloudKitPreferenceKey))
        #expect(fixture.defaults.integer(forKey: "totalMonthlyIncome") == 4200)
        config.resetAllSettings()
        #expect(!fixture.defaults.bool(forKey: SageModelContainer.cloudKitPreferenceKey))
        #expect(!fixture.makeConfiguration(supportsCloudSync: false).isCloudSyncEnabled)
        #expect(fixture.acquisitions == 0)
        #expect(fixture.cloud.operations.isEmpty)
        #expect(config.cloudSyncStatus == .stopped)
    }

    #if DEBUG
    @Test
    func devDefaultsIgnoreProductionConsentAndResetPreservesProductionState() throws {
        let fixture = try Fixture(enabled: true, currency: "USD")
        fixture.defaults.set(true, forKey: "isCloudSyncEnabled")
        fixture.defaults.set(true, forKey: "activeCloudSyncEnabled")
        fixture.defaults.set("EUR", forKey: "ledgerCurrencyCode")
        let config = AppConfiguration(defaults: fixture.defaults,
                                      makeCloudStore: {
            Issue.record("Dev configuration must never acquire an iCloud store")
            return fixture.cloud
        })
        #expect(!config.supportsCloudSync)
        #expect(!config.isCloudSyncEnabled)
        #expect(!config.updateCloudSyncEnabled(true))
        #expect(config.ledgerCurrencyCode == "USD")
        config.resetAllSettings()
        #expect(fixture.defaults.bool(forKey: "isCloudSyncEnabled"))
        #expect(fixture.defaults.bool(forKey: "activeCloudSyncEnabled"))
        #expect(fixture.defaults.string(forKey: "ledgerCurrencyCode") == "EUR")
        #expect(SageModelContainer.cloudKitPreferenceKey != "isCloudSyncEnabled")
        #expect(!SageModelContainer.isCloudKitEnabled)
        #expect(fixture.cloud.operations.isEmpty)
    }
    #endif

    @Test
    func disabledConfigurationNeverAcquiresCloudForInitializationEditsCurrencyOrReset() throws {
        let fixture = try Fixture()
        fixture.cloud.values = [SageModelContainer.cloudKitPreferenceKey: true, "appearance": "Dark"]
        let config = fixture.config
        #expect(!config.isCloudSyncEnabled)
        #expect(config.selectedAppearance == .system)
        #expect(fixture.acquisitions == 0)
        #expect(fixture.cloud.operations.isEmpty)

        config.selectedAppearance = .light
        config.totalMonthlyIncome = 4200
        config.needsPercent = 0.6
        config.wantsPercent = 0.25
        config.savingsPercent = 0.15
        config.updateNeeds(0.55)
        config.updateWants(0.2)
        config.smartTaggingMode = .both
        config.needsColor = .red
        config.wantsColor = .green
        config.savingsColor = .blue
        config.billRemindersEnabled = true
        config.billReminderTimeMinutes = 1125
        config.dailyExpenseReminderEnabled = true
        config.dailyExpenseReminderTimeMinutes = 1260
        config.markSetupComplete()
        config.resetRemoteSetup()
        #expect(config.updateCloudSyncEnabled(false))
        config.recheckPreferences()
        config.ledgerCurrencyCode = "USD"
        #expect(LedgerCurrency.persistedCode(defaults: fixture.defaults) == "USD")
        #expect(fixture.defaults.integer(forKey: "totalMonthlyIncome") == 4200)
        #expect(fixture.defaults.string(forKey: "appearance") == "Light")
        #expect(fixture.defaults.bool(forKey: "billRemindersEnabled"))
        #expect(fixture.defaults.integer(forKey: "billReminderTimeMinutes") == 1125)
        #expect(fixture.defaults.bool(forKey: "dailyExpenseReminderEnabled"))
        #expect(fixture.defaults.integer(forKey: "dailyExpenseReminderTimeMinutes") == 1260)
        #expect(fixture.acquisitions == 0)
        #expect(fixture.cloud.operations.isEmpty)

        config.resetAllSettings()
        #expect(config.totalMonthlyIncome == 0)
        #expect(config.selectedAppearance == .system)
        #expect(config.smartTaggingMode == .history)
        #expect(!config.billRemindersEnabled)
        #expect(config.billReminderTimeMinutes == 540)
        #expect(!config.dailyExpenseReminderEnabled)
        #expect(config.dailyExpenseReminderTimeMinutes == 1200)
        #expect(config.ledgerCurrencyCode == LedgerCurrency.suggestedCode())
        #expect(LedgerCurrency.persistedCode(defaults: fixture.defaults) == nil)
        #expect(!fixture.defaults.bool(forKey: SageModelContainer.cloudKitPreferenceKey))
        #expect(fixture.defaults.object(forKey: "totalMonthlyIncome") == nil)
        #expect(fixture.acquisitions == 0)
        #expect(fixture.cloud.operations.isEmpty)
    }

    @Test
    func billReminderSettingsPersistReloadAndResetWithoutCloudWrites() async throws {
        let fixture = try Fixture(enabled: true, currency: "USD")
        fixture.cloud.values[Key.ledgerCurrency.storageKey] = "USD"
        fixture.cloud.values["billReminderTimeMinutes"] = 0
        let config = fixture.config
        #expect(config.cloudSyncStatus == .running)
        #expect(config.billReminderDaysBefore == 1)
        #expect(config.billReminderTimeMinutes == 540)
        #expect(config.hideBillReminderDetails)
        #expect(!config.billRemindersEnabled)
        fixture.cloud.operations.removeAll()

        config.billReminderDaysBefore = 7
        config.billReminderTimeMinutes = 1125
        config.hideBillReminderDetails = false
        config.billRemindersEnabled = true
        #expect(fixture.defaults.integer(forKey: "billReminderDaysBefore") == 7)
        #expect(fixture.defaults.integer(forKey: "billReminderTimeMinutes") == 1125)
        #expect(fixture.defaults.object(forKey: "hideBillReminderDetails") as? Bool == false)
        #expect(fixture.defaults.bool(forKey: "billRemindersEnabled"))
        #expect(fixture.cloud.operations.isEmpty)

        fixture.cloud.values["billReminderTimeMinutes"] = 1439
        fixture.post(keys: ["billReminderTimeMinutes"])
        await drainNotifications()
        #expect(config.billReminderTimeMinutes == 1125)
        #expect(fixture.defaults.integer(forKey: "billReminderTimeMinutes") == 1125)
        #expect(!fixture.cloud.operations.contains(.read("billReminderTimeMinutes")))

        let reopened = fixture.makeConfiguration()
        #expect(reopened.billReminderDaysBefore == 7)
        #expect(reopened.billReminderTimeMinutes == 1125)
        #expect(!reopened.hideBillReminderDetails)
        #expect(reopened.billRemindersEnabled)
        #expect(fixture.cloud.writtenKeys.isEmpty)

        reopened.resetAllSettings()
        #expect(reopened.billReminderDaysBefore == 1)
        #expect(reopened.billReminderTimeMinutes == 540)
        #expect(reopened.hideBillReminderDetails)
        #expect(!reopened.billRemindersEnabled)
        let reset = fixture.makeConfiguration()
        #expect(reset.billReminderDaysBefore == 1)
        #expect(reset.billReminderTimeMinutes == 540)
        #expect(reset.hideBillReminderDetails)
        #expect(!reset.billRemindersEnabled)
        #expect(fixture.cloud.writtenKeys.isEmpty)
        #expect(fixture.cloud.values["billReminderTimeMinutes"] as? Int == 1439)
    }

    @Test
    func dailyExpenseReminderSettingsPersistReloadAndResetWithoutCloudAccess() async throws {
        let fixture = try Fixture(enabled: true, currency: "USD")
        fixture.cloud.values[Key.ledgerCurrency.storageKey] = "USD"
        fixture.cloud.values["dailyExpenseReminderEnabled"] = true
        fixture.cloud.values["dailyExpenseReminderTimeMinutes"] = 0
        let config = fixture.config
        #expect(config.cloudSyncStatus == .running)
        #expect(!config.dailyExpenseReminderEnabled)
        #expect(config.dailyExpenseReminderTimeMinutes == 1200)
        #expect(!fixture.cloud.operations.contains(.read("dailyExpenseReminderEnabled")))
        #expect(!fixture.cloud.operations.contains(.read("dailyExpenseReminderTimeMinutes")))
        fixture.cloud.operations.removeAll()

        config.dailyExpenseReminderEnabled = true
        config.dailyExpenseReminderTimeMinutes = 1260
        #expect(fixture.defaults.bool(forKey: "dailyExpenseReminderEnabled"))
        #expect(fixture.defaults.integer(forKey: "dailyExpenseReminderTimeMinutes") == 1260)
        #expect(fixture.cloud.operations.isEmpty)

        fixture.cloud.values["dailyExpenseReminderEnabled"] = false
        fixture.cloud.values["dailyExpenseReminderTimeMinutes"] = 1439
        fixture.post(keys: ["dailyExpenseReminderEnabled", "dailyExpenseReminderTimeMinutes"])
        await drainNotifications()
        #expect(config.dailyExpenseReminderEnabled)
        #expect(config.dailyExpenseReminderTimeMinutes == 1260)
        #expect(fixture.defaults.bool(forKey: "dailyExpenseReminderEnabled"))
        #expect(fixture.defaults.integer(forKey: "dailyExpenseReminderTimeMinutes") == 1260)

        let reopened = fixture.makeConfiguration()
        #expect(reopened.dailyExpenseReminderEnabled)
        #expect(reopened.dailyExpenseReminderTimeMinutes == 1260)
        #expect(fixture.cloud.writtenKeys.isEmpty)

        reopened.resetAllSettings()
        #expect(!reopened.dailyExpenseReminderEnabled)
        #expect(reopened.dailyExpenseReminderTimeMinutes == 1200)
        #expect(fixture.defaults.object(forKey: "dailyExpenseReminderEnabled") == nil)
        #expect(fixture.defaults.object(forKey: "dailyExpenseReminderTimeMinutes") == nil)
        let reset = fixture.makeConfiguration()
        #expect(!reset.dailyExpenseReminderEnabled)
        #expect(reset.dailyExpenseReminderTimeMinutes == 1200)
        #expect(fixture.cloud.writtenKeys.isEmpty)
        for key in ["dailyExpenseReminderEnabled", "dailyExpenseReminderTimeMinutes"] {
            #expect(!fixture.cloud.operations.contains(.read(key)))
            #expect(!fixture.cloud.operations.contains(.remove(key)))
        }
        #expect(fixture.cloud.values["dailyExpenseReminderEnabled"] as? Bool == false)
        #expect(fixture.cloud.values["dailyExpenseReminderTimeMinutes"] as? Int == 1439)
    }

    @Test(arguments: [0, 1439])
    func dailyExpenseReminderTimeBoundariesPersistAndReload(minutes: Int) throws {
        let fixture = try Fixture()
        fixture.config.dailyExpenseReminderTimeMinutes = minutes
        #expect(fixture.config.dailyExpenseReminderTimeMinutes == minutes)
        #expect(fixture.defaults.object(forKey: "dailyExpenseReminderTimeMinutes") as? Int == minutes)
        #expect(fixture.makeConfiguration().dailyExpenseReminderTimeMinutes == minutes)
        #expect(fixture.acquisitions == 0)
        #expect(fixture.cloud.operations.isEmpty)
    }

    @Test(arguments: [Int.min, -1, 1440, Int.max])
    func invalidDailyExpenseReminderTimesRetainAssignmentsAndFallBackWhenPersisted(minutes: Int) throws {
        let fixture = try Fixture()
        let config = fixture.config
        config.dailyExpenseReminderTimeMinutes = 1260
        config.dailyExpenseReminderTimeMinutes = minutes
        #expect(config.dailyExpenseReminderTimeMinutes == 1260)
        #expect(fixture.defaults.integer(forKey: "dailyExpenseReminderTimeMinutes") == 1260)
        #expect(fixture.makeConfiguration().dailyExpenseReminderTimeMinutes == 1260)

        fixture.defaults.set(minutes, forKey: "dailyExpenseReminderTimeMinutes")
        #expect(fixture.makeConfiguration().dailyExpenseReminderTimeMinutes == 1200)
        #expect(fixture.acquisitions == 0)
        #expect(fixture.cloud.operations.isEmpty)
    }

    @Test(arguments: [0, 1439])
    func billReminderTimeBoundariesPersistAndReload(minutes: Int) throws {
        let fixture = try Fixture()
        fixture.config.billReminderTimeMinutes = minutes
        #expect(fixture.config.billReminderTimeMinutes == minutes)
        #expect(fixture.defaults.object(forKey: "billReminderTimeMinutes") as? Int == minutes)
        #expect(fixture.makeConfiguration().billReminderTimeMinutes == minutes)
        #expect(fixture.acquisitions == 0)
        #expect(fixture.cloud.operations.isEmpty)
    }

    @Test(arguments: [Int.min, -1, 1440, Int.max])
    func invalidBillReminderTimesRetainAssignmentsAndFallBackWhenPersisted(minutes: Int) throws {
        let fixture = try Fixture()
        let config = fixture.config
        config.billReminderTimeMinutes = 1125
        config.billReminderTimeMinutes = minutes
        #expect(config.billReminderTimeMinutes == 1125)
        #expect(fixture.defaults.integer(forKey: "billReminderTimeMinutes") == 1125)
        #expect(fixture.makeConfiguration().billReminderTimeMinutes == 1125)

        fixture.defaults.set(minutes, forKey: "billReminderTimeMinutes")
        #expect(fixture.makeConfiguration().billReminderTimeMinutes == 540)
        #expect(fixture.acquisitions == 0)
        #expect(fixture.cloud.operations.isEmpty)
    }

    @Test
    func billReminderTimeChangesNotifyObservers() async throws {
        let fixture = try Fixture()
        let config = fixture.config
        await confirmation("Reminder time change is observable") { changed in
            withObservationTracking {
                _ = config.billReminderTimeMinutes
            } onChange: {
                changed()
            }
            config.billReminderTimeMinutes = 1125
        }
    }

    @Test
    func billReminderDaysAcceptOneThroughSevenAndRejectInvalidAssignments() throws {
        let fixture = try Fixture()
        let config = fixture.config
        for days in 1...7 {
            config.billReminderDaysBefore = days
            #expect(config.billReminderDaysBefore == days)
            #expect(fixture.defaults.integer(forKey: "billReminderDaysBefore") == days)
        }

        config.billReminderDaysBefore = 4
        for days in [Int.min, -1, 0, 8, Int.max] {
            config.billReminderDaysBefore = days
            #expect(config.billReminderDaysBefore == 4)
            #expect(fixture.defaults.integer(forKey: "billReminderDaysBefore") == 4)
        }
        #expect(fixture.makeConfiguration().billReminderDaysBefore == 4)
        #expect(fixture.acquisitions == 0)
        #expect(fixture.cloud.operations.isEmpty)
    }

    @Test(arguments: [Int.min, -1, 0, 8, Int.max])
    func invalidPersistedBillReminderDaysFallBackToOne(days: Int) throws {
        let fixture = try Fixture()
        fixture.defaults.set(days, forKey: "billReminderDaysBefore")
        #expect(fixture.makeConfiguration().billReminderDaysBefore == 1)
        #expect(fixture.acquisitions == 0)
        #expect(fixture.cloud.operations.isEmpty)
    }

    @Test
    func startupAndRemoteChangesPersistValidatedValuesWithoutEchoingOldLocalData() async throws {
        let fixture = try Fixture(enabled: true, currency: "USD")
        fixture.defaults.set("Light", forKey: "appearance")
        fixture.defaults.set(1200, forKey: "totalMonthlyIncome")
        fixture.cloud.values = [
            Key.ledgerCurrency.storageKey: "USD", "appearance": "Dark", "totalMonthlyIncome": 7300,
            "needsPercent": 0.6, "wantsPercent": 0.25, "savingsPercent": 0.15,
            "smartTaggingMode": "AI", "hasCompletedSetup": true,
            SageModelContainer.cloudKitPreferenceKey: false,
        ]
        let config = fixture.config
        #expect(config.selectedAppearance == .dark)
        #expect(config.totalMonthlyIncome == 7300)
        #expect(config.smartTaggingMode == .ai)
        #expect(config.hasCompletedSetupOnAnotherDevice)
        #expect(config.isCloudSyncEnabled)
        #expect(config.cloudSyncStatus == .running)
        fixture.expectAllocation(0.6, 0.25, 0.15)
        #expect(fixture.defaults.string(forKey: "appearance") == "Dark")
        #expect(fixture.defaults.integer(forKey: "totalMonthlyIncome") == 7300)
        #expect(fixture.defaults.string(forKey: "smartTaggingMode") == "AI")
        #expect(fixture.cloud.writtenKeys.isEmpty)
        #expect(!fixture.cloud.operations.contains(.read(SageModelContainer.cloudKitPreferenceKey)))

        fixture.cloud.operations.removeAll()
        fixture.cloud.values["appearance"] = "Light"
        fixture.cloud.values["totalMonthlyIncome"] = 8400
        fixture.cloud.values["needsPercent"] = 0.45
        fixture.cloud.values["wantsPercent"] = 0.35
        fixture.cloud.values["savingsPercent"] = 0.2
        // A single changed allocation key must pull and apply the complete remote triple.
        fixture.post(keys: ["appearance", "totalMonthlyIncome", "needsPercent"])
        await drainNotifications()
        #expect(config.selectedAppearance == .light)
        #expect(config.totalMonthlyIncome == 8400)
        #expect(fixture.defaults.integer(forKey: "totalMonthlyIncome") == 8400)
        fixture.expectAllocation(0.45, 0.35, 0.2)
        #expect(fixture.cloud.writtenKeys.isEmpty)
        #expect(!fixture.cloud.operations.contains(.synchronize))
    }

    @Test
    func delayedInitialSyncDoesNotUploadFallbackOrOldPreferences() async throws {
        let fixture = try Fixture(enabled: true, currency: "USD")
        fixture.defaults.set("Light", forKey: "appearance")
        fixture.defaults.set(1200, forKey: "totalMonthlyIncome")
        fixture.cloud.synchronizationResult = false
        let config = fixture.config
        #expect(config.cloudSyncStatus == .synchronizationUnavailable)
        #expect(config.ledgerCurrencyCode == "USD")
        #expect(fixture.cloud.writtenKeys.isEmpty)
        fixture.cloud.operations.removeAll()
        fixture.cloud.values = [Key.ledgerCurrency.storageKey: "EUR", "totalMonthlyIncome": 9900, "appearance": "Dark"]
        fixture.post(reason: NSUbiquitousKeyValueStoreInitialSyncChange)
        await drainNotifications()
        #expect(config.selectedAppearance == .dark)
        #expect(config.totalMonthlyIncome == 9900)
        #expect(config.ledgerCurrencyCode == "EUR")
        #expect(LedgerCurrency.persistedCode(defaults: fixture.defaults) == "EUR")
        #expect(fixture.cloud.writtenKeys.isEmpty)
    }

    @Test
    func malformedLocalDefaultsFallBackToSafeValuesWithoutCloudAccess() throws {
        let fixture = try Fixture()
        let invalidIncomes: [Any] = [true, -1, 1.25, Double.nan, Double.infinity, Double.greatestFiniteMagnitude, "500"]
        for income in invalidIncomes {
            fixture.defaults.set(income, forKey: "totalMonthlyIncome")
            fixture.defaults.set("unknown", forKey: "appearance")
            fixture.defaults.set("unknown", forKey: "smartTaggingMode")
            fixture.defaults.set(0.8, forKey: "needsPercent")
            fixture.defaults.set(0.7, forKey: "wantsPercent")
            fixture.defaults.set(0.2, forKey: "savingsPercent")
            let config = fixture.makeConfiguration()
            #expect(config.totalMonthlyIncome == 0)
            #expect(config.selectedAppearance == .system)
            #expect(config.smartTaggingMode == .history)
            #expect(config.needsPercent == 0.5)
            #expect(config.wantsPercent == 0.3)
            #expect(config.savingsPercent == 0.2)
            #expect(fixture.defaults.integer(forKey: "totalMonthlyIncome") == 0)
        }
        #expect(fixture.acquisitions == 0)
        #expect(fixture.cloud.operations.isEmpty)
    }

    @Test
    func invalidRemoteIncomeAndNonBooleanSetupFlagsAreRejected() throws {
        let fixture = try Fixture(enabled: true, currency: "USD")
        fixture.defaults.set(3200, forKey: "totalMonthlyIncome")
        fixture.cloud.values[Key.ledgerCurrency.storageKey] = "USD"
        let config = fixture.config
        let invalidIncomes: [Any] = [true, false, -1, 1.25, Double.nan, Double.infinity, -Double.infinity,
                                    Double.greatestFiniteMagnitude, "500", [500]]
        for income in invalidIncomes {
            fixture.cloud.values["totalMonthlyIncome"] = income
            fixture.cloud.values["appearance"] = "invalid"
            fixture.cloud.values["smartTaggingMode"] = "invalid"
            config.recheckPreferences()
            #expect(config.totalMonthlyIncome == 3200)
            #expect(fixture.defaults.integer(forKey: "totalMonthlyIncome") == 3200)
            #expect(config.selectedAppearance == .system)
            #expect(config.smartTaggingMode == .history)
        }
        for flag in [1, "true", 1.0] as [Any] {
            fixture.cloud.values["hasCompletedSetup"] = flag
            config.recheckPreferences()
            #expect(!config.hasCompletedSetupOnAnotherDevice)
        }
        #expect(fixture.cloud.writtenKeys.isEmpty)
    }

    @Test
    func invalidOrIncompleteRemoteAllocationsAreRejectedAsAWhole() throws {
        let fixture = try Fixture(enabled: true, currency: "USD")
        fixture.cloud.values[Key.ledgerCurrency.storageKey] = "USD"
        let config = fixture.config
        let invalidAllocations: [[Any?]] = [
            [0.8, 0.3, 0.2], [-0.1, 0.9, 0.2], [1.1, 0.0, -0.1],
            [Double.nan, 0.3, 0.2], [0.5, Double.infinity, 0.2],
            [true, 0.0, 0.0], [0.5, "0.3", 0.2], [0.6, nil, 0.4],
        ]
        for allocation in invalidAllocations {
            fixture.cloud.values["needsPercent"] = allocation[0]
            fixture.cloud.values["wantsPercent"] = allocation[1]
            fixture.cloud.values["savingsPercent"] = allocation[2]
            config.recheckPreferences()
            fixture.expectAllocation(0.5, 0.3, 0.2)
        }
        #expect(fixture.cloud.writtenKeys.isEmpty)
    }

    @Test
    func localValidationRejectsInvalidNumbersAndOnlyPublishesCoherentAllocation() throws {
        let fixture = try Fixture(enabled: true, currency: "USD")
        fixture.cloud.values[Key.ledgerCurrency.storageKey] = "USD"
        let config = fixture.config
        config.totalMonthlyIncome = 3200
        fixture.cloud.operations.removeAll()
        config.totalMonthlyIncome = -1
        for invalid in [Double.nan, .infinity, -.infinity, -0.1, 1.1] {
            config.needsPercent = invalid
            config.wantsPercent = invalid
            config.savingsPercent = invalid
        }
        config.updateNeeds(.nan)
        config.updateWants(.infinity)
        #expect(config.totalMonthlyIncome == 3200)
        #expect(fixture.defaults.integer(forKey: "totalMonthlyIncome") == 3200)
        fixture.expectAllocation(0.5, 0.3, 0.2)
        #expect(fixture.cloud.operations.isEmpty)

        config.needsPercent = 0.6
        config.wantsPercent = 0.25
        #expect(fixture.cloud.writtenKeys.isEmpty)
        config.savingsPercent = 0.15
        #expect(Set(fixture.cloud.writtenKeys) == Set(Key.allocation.map(\.storageKey)))
        #expect(fixture.cloud.writtenKeys.count == 3)
        #expect(fixture.cloud.values["needsPercent"] as? Double == 0.6)
        #expect(fixture.cloud.values["wantsPercent"] as? Double == 0.25)
        #expect(fixture.cloud.values["savingsPercent"] as? Double == 0.15)
        fixture.expectAllocation(0.6, 0.25, 0.15)
    }

    @Test(arguments: [nil, "invalid", "EUR"] as [String?])
    func remoteIncomeAndAllocationApplyIndependentlyOfCurrency(remote: String?) throws {
        let fixture = try Fixture(enabled: true, currency: "USD")
        fixture.defaults.set(3200, forKey: "totalMonthlyIncome")
        fixture.cloud.values = ["totalMonthlyIncome": 9900, "needsPercent": 0.6, "wantsPercent": 0.2, "savingsPercent": 0.2]
        fixture.cloud.values[Key.ledgerCurrency.storageKey] = remote
        let config = fixture.config
        #expect(config.totalMonthlyIncome == 9900)
        fixture.expectAllocation(0.6, 0.2, 0.2)
        let expectedCurrency = remote == "EUR" ? "EUR" : "USD"
        #expect(config.ledgerCurrencyCode == expectedCurrency)
        #expect(LedgerCurrency.persistedCode(defaults: fixture.defaults) == expectedCurrency)
        #expect(fixture.cloud.writtenKeys.isEmpty)
    }

    @Test
    func legacyConflictFlagsDoNotBlockRemoteAdoptionOrLocalEditsAcrossReinitialization() throws {
        let fixture = try Fixture(enabled: true, currency: "USD")
        fixture.defaults.set(true, forKey: LedgerCurrency.storageKey + ".conflict")
        fixture.defaults.set(3200, forKey: "totalMonthlyIncome")
        fixture.cloud.values = [Key.ledgerCurrency.storageKey: "EUR", "totalMonthlyIncome": 9900]
        let config = fixture.config
        #expect(config.ledgerCurrencyCode == "EUR")
        #expect(config.totalMonthlyIncome == 9900)
        #expect(fixture.cloud.writtenKeys.isEmpty)
        #expect(config.updateCloudSyncEnabled(false))
        fixture.cloud.operations.removeAll()
        config.recheckPreferences()
        let reopened = fixture.makeConfiguration()
        #expect(reopened.ledgerCurrencyCode == "EUR")
        #expect(!reopened.isCloudSyncEnabled)
        reopened.ledgerCurrencyCode = "JPY"
        reopened.totalMonthlyIncome = 4100
        #expect(reopened.ledgerCurrencyCode == "JPY")
        #expect(LedgerCurrency.persistedCode(defaults: fixture.defaults) == "JPY")
        #expect(fixture.defaults.integer(forKey: "totalMonthlyIncome") == 4100)
        #expect(fixture.acquisitions == 1)
        #expect(fixture.cloud.operations.isEmpty)
        #expect(fixture.defaults.bool(forKey: LedgerCurrency.storageKey + ".conflict"))
    }

    @Test
    func wantsThirtyFivePercentReachesAnotherClientAfterPartialDelivery() async throws {
        let phone = try Fixture(enabled: true, currency: "USD")
        let tablet = try Fixture(enabled: true, currency: "USD")
        let original: [String: Any] = [
            Key.ledgerCurrency.storageKey: "USD",
            "needsPercent": 0.5, "wantsPercent": 0.3, "savingsPercent": 0.2,
        ]
        phone.cloud.values = original
        tablet.cloud.values = original
        let sender = phone.config
        _ = tablet.config
        phone.cloud.operations.removeAll()
        tablet.cloud.operations.removeAll()

        sender.updateWants(0.35)
        phone.expectAllocation(0.5, 0.35, 0.15)
        #expect(Set(phone.cloud.writtenKeys) == Set(Key.allocation.map(\.storageKey)))

        // KVS keys can arrive separately; never apply an inconsistent intermediate budget.
        tablet.cloud.values["wantsPercent"] = phone.cloud.values["wantsPercent"]
        tablet.post(keys: ["wantsPercent"])
        await drainNotifications()
        tablet.expectAllocation(0.5, 0.3, 0.2)
        tablet.cloud.values["savingsPercent"] = phone.cloud.values["savingsPercent"]
        tablet.post(keys: ["savingsPercent"])
        await drainNotifications()
        tablet.expectAllocation(0.5, 0.35, 0.15)
        #expect(tablet.cloud.writtenKeys.isEmpty)

        tablet.config.updateCloudSyncEnabled(false)
        tablet.cloud.operations.removeAll()
        sender.updateWants(0.4)
        for key in Key.allocation { tablet.cloud.values[key.storageKey] = phone.cloud.values[key.storageKey] }
        tablet.post(keys: Key.allocation.map(\.storageKey))
        await drainNotifications()
        tablet.expectAllocation(0.5, 0.35, 0.15)
        #expect(tablet.cloud.operations.isEmpty)
    }

    @Test
    func enablingSyncDoesNotUploadLocalCurrencyAndIncomeNeedsNoCurrencyHandshake() throws {
        let fixture = try Fixture()
        let config = fixture.config
        config.ledgerCurrencyCode = "USD"
        #expect(fixture.acquisitions == 0)
        #expect(config.updateCloudSyncEnabled(true))
        #expect(fixture.cloud.writtenKeys.isEmpty)
        config.totalMonthlyIncome = 1200
        #expect(fixture.cloud.writtenKeys == ["totalMonthlyIncome"])
        #expect(fixture.cloud.values[Key.ledgerCurrency.storageKey] == nil)
        config.ledgerCurrencyCode = "EUR"
        config.totalMonthlyIncome = 2400
        #expect(fixture.cloud.values["totalMonthlyIncome"] as? Int == 2400)
        #expect(fixture.cloud.values[Key.ledgerCurrency.storageKey] as? String == "EUR")
    }

    @Test
    func reenableUsesRemoteValuesRatherThanUploadingOfflineEdits() throws {
        let fixture = try Fixture(enabled: true, currency: "USD")
        fixture.cloud.values = [Key.ledgerCurrency.storageKey: "USD", "appearance": "Dark", "totalMonthlyIncome": 7000]
        let config = fixture.config
        config.updateCloudSyncEnabled(false)
        fixture.cloud.operations.removeAll()
        config.selectedAppearance = .light
        config.totalMonthlyIncome = 1200
        config.updateNeeds(0.7)
        #expect(fixture.cloud.operations.isEmpty)
        fixture.cloud.values["totalMonthlyIncome"] = 8500
        fixture.cloud.values["needsPercent"] = 0.4
        fixture.cloud.values["wantsPercent"] = 0.3
        fixture.cloud.values["savingsPercent"] = 0.3
        #expect(config.updateCloudSyncEnabled(true))
        #expect(config.selectedAppearance == .dark)
        #expect(config.totalMonthlyIncome == 8500)
        #expect(fixture.defaults.integer(forKey: "totalMonthlyIncome") == 8500)
        fixture.expectAllocation(0.4, 0.3, 0.3)
        #expect(fixture.acquisitions == 2)
        #expect(fixture.cloud.writtenKeys.isEmpty)
    }

    @Test
    func queuedCallbacksAreIgnoredAfterOptOutIncludingReset() async throws {
        let fixture = try Fixture(enabled: true, currency: "USD")
        fixture.cloud.values = [Key.ledgerCurrency.storageKey: "USD", "appearance": "Light"]
        let config = fixture.config
        fixture.cloud.values["appearance"] = "Dark"
        fixture.post(keys: ["appearance"])
        fixture.post(reason: NSUbiquitousKeyValueStoreAccountChange)
        config.updateCloudSyncEnabled(false)
        fixture.cloud.operations.removeAll()
        await drainNotifications()
        #expect(config.selectedAppearance == .light)
        #expect(config.cloudSyncStatus == .stopped)
        #expect(!config.hasCompletedSetupOnAnotherDevice)
        config.totalMonthlyIncome = 1200
        config.markSetupComplete()
        config.recheckPreferences()
        config.resetAllSettings()
        fixture.post()
        await drainNotifications()
        #expect(fixture.cloud.operations.isEmpty)
        #expect(fixture.acquisitions == 1)
    }

    @Test
    func accountChangePersistsOptOutAndNeverPublishesOldPreferences() async throws {
        let fixture = try Fixture(enabled: true, currency: "USD")
        fixture.cloud.values = [Key.ledgerCurrency.storageKey: "USD", "appearance": "Dark"]
        let config = fixture.config
        fixture.cloud.operations.removeAll()
        fixture.post(reason: NSUbiquitousKeyValueStoreAccountChange)
        await drainNotifications()
        #expect(!config.isCloudSyncEnabled)
        #expect(!fixture.defaults.bool(forKey: SageModelContainer.cloudKitPreferenceKey))
        #expect(config.cloudSyncStatus == .accountChanged)
        config.selectedAppearance = .light
        config.recheckPreferences()
        #expect(fixture.cloud.operations.isEmpty)
        #expect(!fixture.makeConfiguration().isCloudSyncEnabled)
        #expect(fixture.acquisitions == 1)
    }

    @Test
    func optInAdoptsRemoteCurrencyAndAllowsAnExplicitReplacement() throws {
        let fixture = try Fixture()
        let config = fixture.config
        config.totalMonthlyIncome = 3200
        fixture.cloud.values = [Key.ledgerCurrency.storageKey: "EUR", "totalMonthlyIncome": 9900, "hasCompletedSetup": true]
        #expect(config.updateCloudSyncEnabled(true))
        #expect(config.hasCompletedSetupOnAnotherDevice)
        #expect(config.totalMonthlyIncome == 9900)
        #expect(config.ledgerCurrencyCode == "EUR")
        #expect(LedgerCurrency.persistedCode(defaults: fixture.defaults) == "EUR")
        #expect(fixture.cloud.writtenKeys.isEmpty)
        config.ledgerCurrencyCode = "USD"
        #expect(config.totalMonthlyIncome == 9900)
        #expect(LedgerCurrency.persistedCode(defaults: fixture.defaults) == "USD")
        #expect(fixture.cloud.writtenKeys == [Key.ledgerCurrency.storageKey])
    }

    @Test
    func persistedConsentRevocationBlocksAnAlreadyActiveConfiguration() async throws {
        let fixture = try Fixture(enabled: true, currency: "USD")
        fixture.cloud.values = [Key.ledgerCurrency.storageKey: "USD", "appearance": "Light"]
        let config = fixture.config
        fixture.post(keys: ["appearance"])
        fixture.defaults.set(false, forKey: SageModelContainer.cloudKitPreferenceKey)
        fixture.cloud.operations.removeAll()
        config.selectedAppearance = .dark
        config.totalMonthlyIncome = 1200
        config.updateNeeds(0.6)
        config.markSetupComplete()
        config.recheckPreferences()
        await drainNotifications()
        #expect(config.selectedAppearance == .dark)
        #expect(config.cloudSyncStatus == .stopped)
        config.resetAllSettings()
        #expect(fixture.cloud.operations.isEmpty)
        #expect(fixture.acquisitions == 1)
    }

    @Test
    func currencyNotificationAdoptsDenominationWithoutReadingOrChangingAmounts() async throws {
        let fixture = try Fixture(enabled: true, currency: "USD")
        fixture.defaults.set(3200, forKey: "totalMonthlyIncome")
        fixture.cloud.values = [Key.ledgerCurrency.storageKey: "EUR", "totalMonthlyIncome": 9900,
                                "needsPercent": 0.6, "wantsPercent": 0.2, "savingsPercent": 0.2]
        let config = fixture.config
        #expect(config.ledgerCurrencyCode == "EUR")
        #expect(config.totalMonthlyIncome == 9900)
        fixture.cloud.operations.removeAll()
        fixture.cloud.values["totalMonthlyIncome"] = 1234
        fixture.cloud.values[Key.ledgerCurrency.storageKey] = "USD"
        fixture.post(keys: [Key.ledgerCurrency.storageKey])
        await drainNotifications()
        #expect(config.ledgerCurrencyCode == "USD")
        #expect(LedgerCurrency.persistedCode(defaults: fixture.defaults) == "USD")
        #expect(config.totalMonthlyIncome == 9900)
        #expect(fixture.defaults.integer(forKey: "totalMonthlyIncome") == 9900)
        fixture.expectAllocation(0.6, 0.2, 0.2)
        #expect(fixture.cloud.writtenKeys.isEmpty)
        #expect(fixture.cloud.operations == [.read(Key.ledgerCurrency.storageKey)])
    }

    @Test
    func currencyReplacementIsObservableAndPreservesIncomeAndBudgets() async throws {
        let fixture = try Fixture(enabled: true, currency: "USD")
        let config = fixture.config
        config.totalMonthlyIncome = 3200
        config.updateNeeds(0.6)
        let budgets = [config.needsBudget, config.wantsBudget, config.savingsBudget]
        fixture.cloud.operations.removeAll()

        await confirmation("Currency change is observable") { changed in
            withObservationTracking {
                _ = config.ledgerCurrencyCode
            } onChange: {
                changed()
            }
            config.ledgerCurrencyCode = "JPY"
        }

        #expect(config.ledgerCurrencyCode == "JPY")
        #expect(config.totalMonthlyIncome == 3200)
        #expect([config.needsBudget, config.wantsBudget, config.savingsBudget] == budgets)
        #expect(LedgerCurrency.persistedCode(defaults: fixture.defaults) == "JPY")
        #expect(fixture.cloud.operations == [.write(Key.ledgerCurrency.storageKey)])
        #expect(fixture.makeConfiguration().ledgerCurrencyCode == "JPY")
    }

    @Test(arguments: ["", "usd", "ZZZ", " USD "])
    func invalidCurrencyAssignmentsRetainTheSavedValueAndInvalidDefaultsUseSuggestion(code: String) throws {
        let fixture = try Fixture(enabled: true, currency: "EUR")
        let config = fixture.config
        fixture.cloud.operations.removeAll()
        config.ledgerCurrencyCode = code
        #expect(config.ledgerCurrencyCode == "EUR")
        #expect(LedgerCurrency.persistedCode(defaults: fixture.defaults) == "EUR")
        #expect(fixture.cloud.operations.isEmpty)

        fixture.defaults.set(code, forKey: LedgerCurrency.storageKey)
        #expect(fixture.makeConfiguration().ledgerCurrencyCode == LedgerCurrency.suggestedCode())
        #expect(fixture.cloud.writtenKeys.isEmpty)
    }

    @Test
    func invalidOrRemovedRemoteCurrencyRetainsTheLocalDenominationWithoutEcho() async throws {
        let fixture = try Fixture(enabled: true, currency: "GBP")
        let config = fixture.config
        let invalidValues: [Any?] = [nil, "", "usd", "ZZZ", " USD ", 123, true, ["EUR"]]
        for value in invalidValues {
            fixture.cloud.values[Key.ledgerCurrency.storageKey] = value
            fixture.cloud.operations.removeAll()
            fixture.post(keys: [Key.ledgerCurrency.storageKey])
            await drainNotifications()
            #expect(config.ledgerCurrencyCode == "GBP")
            #expect(LedgerCurrency.persistedCode(defaults: fixture.defaults) == "GBP")
            #expect(fixture.cloud.operations == [.read(Key.ledgerCurrency.storageKey)])
        }
    }

    @Test
    func startupSuggestionIsPersistedLocallyButNotPublishedUntilEdited() throws {
        let fixture = try Fixture(enabled: true)
        let config = fixture.config
        #expect(config.ledgerCurrencyCode == LedgerCurrency.suggestedCode())
        #expect(LedgerCurrency.persistedCode(defaults: fixture.defaults) == config.ledgerCurrencyCode)
        #expect(fixture.cloud.writtenKeys.isEmpty)
        config.ledgerCurrencyCode = "GBP"
        #expect(LedgerCurrency.persistedCode(defaults: fixture.defaults) == "GBP")
        #expect(fixture.cloud.writtenKeys == [Key.ledgerCurrency.storageKey])
    }

    @Test
    func currencyUsesTheInjectedStoreForPersistenceAndReload() throws {
        let fixture = try Fixture()
        let config = AppConfiguration(defaults: fixture.defaults)
        config.ledgerCurrencyCode = "EUR"
        #expect(fixture.defaults.string(forKey: LedgerCurrency.storageKey) == "EUR")
        let reopened = AppConfiguration(defaults: fixture.defaults)
        #expect(reopened.ledgerCurrencyCode == "EUR")
    }

    @Test
    func enabledResetDeletesCloudPreferencesBeforePersistingOptOutWithoutPublishingDefaults() throws {
        let fixture = try Fixture(enabled: true, currency: "USD")
        fixture.cloud.values = [Key.ledgerCurrency.storageKey: "USD", "appearance": "Dark", "totalMonthlyIncome": 7000]
        let config = fixture.config
        fixture.cloud.operations.removeAll()
        fixture.cloud.onRemove = {
            #expect(fixture.defaults.bool(forKey: SageModelContainer.cloudKitPreferenceKey))
        }
        defer { fixture.cloud.onRemove = nil }
        config.resetAllSettings()
        #expect(Set(fixture.cloud.operations) == Set(Key.allCases.map { .remove($0.storageKey) } + [.synchronize]))
        #expect(fixture.cloud.operations.last == .synchronize)
        #expect(fixture.cloud.writtenKeys.isEmpty)
        #expect(!config.isCloudSyncEnabled)
        #expect(!fixture.defaults.bool(forKey: SageModelContainer.cloudKitPreferenceKey))
        #expect(config.cloudSyncStatus == .stopped)
        #expect(config.ledgerCurrencyCode == LedgerCurrency.suggestedCode())
        #expect(config.totalMonthlyIncome == 0)
    }

    private func drainNotifications() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @MainActor
    private final class Fixture {
        let localSuite = "AppConfigurationTests.local.\(UUID().uuidString)"
        let defaults: UserDefaults
        let cloud = CloudSpy()
        let notifications = NotificationCenter()
        var acquisitions = 0
        lazy var config = makeConfiguration()

        init(enabled: Bool = false, currency: String? = nil) throws {
            defaults = try #require(UserDefaults(suiteName: localSuite))
            defaults.set(enabled, forKey: SageModelContainer.cloudKitPreferenceKey)
            if let currency { try LedgerCurrency.setCode(currency, defaults: defaults) }
        }

        deinit {
            defaults.removePersistentDomain(forName: localSuite)
        }

        func makeConfiguration(supportsCloudSync: Bool = true) -> AppConfiguration {
            AppConfiguration(defaults: defaults, supportsCloudSync: supportsCloudSync, makeCloudStore: { [unowned self] in
                acquisitions += 1
                return cloud
            }, notificationCenter: notifications)
        }

        func post(reason: Int = NSUbiquitousKeyValueStoreServerChange, keys: [String]? = nil) {
            var info: [String: Any] = [NSUbiquitousKeyValueStoreChangeReasonKey: reason]
            info[NSUbiquitousKeyValueStoreChangedKeysKey] = keys
            notifications.post(name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, userInfo: info)
        }

        func expectAllocation(_ needs: Double, _ wants: Double, _ savings: Double, sourceLocation: SourceLocation = #_sourceLocation) {
            #expect(abs(config.needsPercent - needs) < 0.000001, sourceLocation: sourceLocation)
            #expect(abs(config.wantsPercent - wants) < 0.000001, sourceLocation: sourceLocation)
            #expect(abs(config.savingsPercent - savings) < 0.000001, sourceLocation: sourceLocation)
            #expect(abs(defaults.double(forKey: "needsPercent") - needs) < 0.000001, sourceLocation: sourceLocation)
            #expect(abs(defaults.double(forKey: "wantsPercent") - wants) < 0.000001, sourceLocation: sourceLocation)
            #expect(abs(defaults.double(forKey: "savingsPercent") - savings) < 0.000001, sourceLocation: sourceLocation)
        }
    }

    private final class CloudSpy: NSObject, CloudPreferenceStore {
        enum Operation: Hashable {
            case read(String), write(String), remove(String), synchronize
        }
        var values: [String: Any] = [:]
        var operations: [Operation] = []
        var synchronizationResult = true
        var onRemove: (() -> Void)?
        var writtenKeys: [String] {
            operations.compactMap { if case .write(let key) = $0 { key } else { nil } }
        }

        func object(forKey key: String) -> Any? {
            operations.append(.read(key))
            return values[key]
        }

        func set(_ value: Any?, forKey key: String) {
            operations.append(.write(key))
            values[key] = value
        }

        func removeObject(forKey key: String) {
            onRemove?()
            operations.append(.remove(key))
            values.removeValue(forKey: key)
        }

        func synchronize() -> Bool {
            operations.append(.synchronize)
            return synchronizationResult
        }
    }
}
