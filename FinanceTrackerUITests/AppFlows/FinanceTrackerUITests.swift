import XCTest

@MainActor
final class FinanceTrackerUITests: XCTestCase {
    private let timeout: TimeInterval = 20

    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    func testCompletesOnboarding() {
        let app = launchApp(showsOnboarding: true)

        let welcomeTitle = app.staticTexts["onboarding-welcome-title"]
        XCTAssertTrue(
            welcomeTitle.waitForExistence(timeout: timeout),
            "The welcome page did not appear for a clean onboarding launch."
        )

        tap("onboarding-get-started-button", in: app)

        let incomeField = app.textFields["onboarding-income-field"]
        XCTAssertTrue(incomeField.waitForExistence(timeout: timeout), "The income field did not appear.")
        XCTAssertTrue(scrollToVisibility(of: incomeField, in: app))
        incomeField.tap()
        incomeField.typeText("5000")

        tap("onboarding-keyboard-done-button", in: app)

        tap("onboarding-budget-continue-button", in: app)
        tap("onboarding-allocation-continue-button", in: app)
        tap("onboarding-sync-continue-button", in: app)
        tap("onboarding-tags-continue-button", in: app)

        let recurringReminder = app.switches["onboarding-recurring-reminders-toggle"]
        let dailyReminder = app.switches["onboarding-daily-reminder-toggle"]
        XCTAssertTrue(recurringReminder.waitForExistence(timeout: timeout))
        XCTAssertTrue(scrollToVisibility(of: recurringReminder, in: app))
        XCTAssertEqual(recurringReminder.value as? String, "0", "Recurring reminders must default to off.")
        XCTAssertTrue(dailyReminder.waitForExistence(timeout: timeout))
        XCTAssertTrue(scrollToVisibility(of: dailyReminder, in: app))
        XCTAssertEqual(dailyReminder.value as? String, "0", "Daily reminders must default to off.")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Onboarding reminders - defaults off"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        tap("onboarding-reminders-continue-button", in: app)

        let planTotal = app.staticTexts["onboarding-plan-total"]
        XCTAssertTrue(planTotal.waitForExistence(timeout: timeout))
        XCTAssertTrue(scrollToVisibility(of: planTotal, in: app))
        let expectedTotal = Double(5000).formatted(
            .currency(code: Locale.current.currency?.identifier ?? "USD").precision(.fractionLength(0))
        )
        XCTAssertEqual(planTotal.label, expectedTotal, "Income should be interpreted as whole currency units.")
        tap("onboarding-start-tracking-button", in: app)

        XCTAssertTrue(
            app.tabBars.buttons["Expenses"].waitForExistence(timeout: timeout),
            "The main tabs did not appear after onboarding completed."
        )
        assertReminderSettings(recurringEnabled: false, dailyEnabled: false, in: app)
    }

    func testOnboardingReminderChoicesAreIndependentAndRetainedWhenGoingBack() {
        let app = launchApp(showsOnboarding: true)
        tap("onboarding-get-started-button", in: app)
        let incomeField = app.textFields["onboarding-income-field"]
        XCTAssertTrue(incomeField.waitForExistence(timeout: timeout))
        XCTAssertTrue(scrollToVisibility(of: incomeField, in: app))
        incomeField.tap()
        incomeField.typeText("5000")
        tap("onboarding-keyboard-done-button", in: app)
        tap("onboarding-budget-continue-button", in: app)
        tap("onboarding-allocation-continue-button", in: app)
        tap("onboarding-sync-continue-button", in: app)
        tap("onboarding-tags-continue-button", in: app)

        let recurringReminder = app.switches["onboarding-recurring-reminders-toggle"]
        let dailyReminder = app.switches["onboarding-daily-reminder-toggle"]
        XCTAssertTrue(recurringReminder.waitForExistence(timeout: timeout))
        XCTAssertTrue(scrollToVisibility(of: recurringReminder, in: app))
        recurringReminder.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(recurringReminder.value as? String, "1")
        XCTAssertTrue(dailyReminder.waitForExistence(timeout: timeout))
        XCTAssertTrue(scrollToVisibility(of: dailyReminder, in: app))
        XCTAssertEqual(dailyReminder.value as? String, "0", "Enabling recurring reminders must not enable daily reminders.")
        dailyReminder.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(dailyReminder.value as? String, "1")
        XCTAssertEqual(recurringReminder.value as? String, "1", "Enabling daily reminders must not change recurring reminders.")
        XCTAssertTrue(app.buttons["onboarding-reminders-continue-button"].isHittable,
                      "Enabling reminders must leave the user on the reminders page.")

        tap("onboarding-reminders-continue-button", in: app)
        XCTAssertTrue(app.buttons["onboarding-start-tracking-button"].waitForExistence(timeout: timeout))
        tap("onboarding-back-button", in: app)
        XCTAssertTrue(recurringReminder.waitForExistence(timeout: timeout))
        XCTAssertTrue(scrollToVisibility(of: recurringReminder, in: app))
        XCTAssertEqual(recurringReminder.value as? String, "1", "Recurring reminder selection must survive returning from the summary.")
        XCTAssertTrue(dailyReminder.waitForExistence(timeout: timeout))
        XCTAssertEqual(dailyReminder.value as? String, "1", "Daily reminder selection must survive returning from the summary.")
        recurringReminder.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(recurringReminder.value as? String, "0")
        XCTAssertEqual(dailyReminder.value as? String, "1", "Turning recurring reminders off must leave daily reminders enabled.")

        tap("onboarding-back-button", in: app)
        XCTAssertTrue(app.buttons["onboarding-tags-continue-button"].waitForExistence(timeout: timeout))
        tap("onboarding-tags-continue-button", in: app)
        XCTAssertTrue(recurringReminder.waitForExistence(timeout: timeout))
        XCTAssertEqual(recurringReminder.value as? String, "0", "Turning a reminder off must survive returning from an earlier step.")
        XCTAssertTrue(dailyReminder.waitForExistence(timeout: timeout))
        XCTAssertEqual(dailyReminder.value as? String, "1", "The other reminder must remain enabled after going back.")
        tap("onboarding-reminders-continue-button", in: app)
        tap("onboarding-start-tracking-button", in: app)
        XCTAssertTrue(app.tabBars.buttons["Expenses"].waitForExistence(timeout: timeout))
        assertReminderSettings(recurringEnabled: false, dailyEnabled: true, in: app)
    }

    func testOnboardingPayFrequencyUpdatesMonthlyBudget() {
        let app = launchApp(showsOnboarding: true, launchArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        tap("onboarding-get-started-button", in: app)
        let field = app.textFields["onboarding-income-field"]
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        tap(field, named: "income")
        field.typeText("2400")
        tap("onboarding-keyboard-done-button", in: app)

        let picker = app.segmentedControls["onboarding-income-frequency-picker"]
        let equivalent = app.staticTexts["onboarding-monthly-equivalent"]
        XCTAssertFalse(equivalent.exists, "Monthly input does not need a conversion strip.")
        tap(picker.buttons["Biweekly"], named: "Biweekly")
        XCTAssertEqual(equivalent.label, "$5,200")
        tap(picker.buttons["Weekly"], named: "Weekly")
        XCTAssertEqual(equivalent.label, "$10,400")
        tap(picker.buttons["Biweekly"], named: "Biweekly")
        tap("onboarding-budget-continue-button", in: app)
        tap("onboarding-back-button", in: app)
        XCTAssertEqual(field.value as? String, "2400")
        XCTAssertTrue(picker.buttons["Biweekly"].isSelected)
        XCTAssertEqual(equivalent.label, "$5,200")
        tap("onboarding-budget-continue-button", in: app)
        tap("onboarding-allocation-continue-button", in: app)
        tap("onboarding-sync-continue-button", in: app)
        tap("onboarding-tags-continue-button", in: app)
        tap("onboarding-reminders-continue-button", in: app)
        XCTAssertEqual(app.staticTexts["onboarding-plan-total"].label, "$5,200")
    }

    func testOnboardingConversionStripAppearsAboveKeyboard() {
        let app = launchApp(showsOnboarding: true)
        tap("onboarding-get-started-button", in: app)
        let picker = app.segmentedControls["onboarding-income-frequency-picker"]
        let equivalent = app.staticTexts["onboarding-monthly-equivalent"]
        tap(picker.buttons["Biweekly"], named: "Biweekly")
        XCTAssertFalse(equivalent.exists)
        let field = app.textFields["onboarding-income-field"]
        field.tap()
        // Do not tap the field again or scroll while typing; that can conceal a layout bug.
        app.typeText("2400")
        XCTAssertTrue(equivalent.waitForExistence(timeout: timeout))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Income strip with keyboard"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let visible = NSPredicate { _, _ in
            let keyboard = app.keyboards.firstMatch.frame
            return keyboard.minY < app.frame.maxY
                && equivalent.isHittable
                && equivalent.frame.maxY < app.buttons["onboarding-budget-continue-button"].frame.minY - 16
                && equivalent.frame.maxY < keyboard.minY
        }
        expectation(for: visible, evaluatedWith: app)
        waitForExpectations(timeout: timeout)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        XCTAssertTrue(equivalent.waitForNonExistence(timeout: timeout))
    }

    func testOnboardingIncomeKeyboardStaysOpenAndCanBeReopened() {
        let app = launchApp(showsOnboarding: true)
        tap("onboarding-get-started-button", in: app)

        let incomeField = app.textFields["onboarding-income-field"]
        XCTAssertTrue(incomeField.waitForExistence(timeout: timeout))
        incomeField.tap()

        // Type through the app, not the field, so lost focus cannot be recovered.
        // A hardware keyboard leaves an off-screen keypad preview in the AX tree.
        let keyboard = app.keyboards.firstMatch
        let done = app.descendants(matching: .any)["onboarding-keyboard-done-button"].firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: timeout))
        app.typeText("5")
        XCTAssertEqual(incomeField.value as? String, "5")
        app.typeText("0")
        XCTAssertEqual(incomeField.value as? String, "50")
        XCTAssertTrue(keyboard.exists)
        XCTAssertTrue(done.isHittable)

        tap("onboarding-keyboard-done-button", in: app)
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: timeout))
        incomeField.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: timeout))
        app.typeText("0")
        XCTAssertEqual(incomeField.value as? String, "500")
        XCTAssertTrue(done.isHittable)

        tap("onboarding-budget-continue-button", in: app)
        XCTAssertTrue(app.buttons["onboarding-allocation-continue-button"].waitForExistence(timeout: timeout))
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: timeout))
        tap("onboarding-back-button", in: app)
        XCTAssertEqual(incomeField.value as? String, "500")
    }

    func testOnboardingCurrencyDefaultsToRegionAndCanBeChangedWithIncome() {
        let app = XCUIApplication()
        app.launchEnvironment["SAGE_UI_TESTING"] = "1"
        app.launchEnvironment["SAGE_UI_TEST_ONBOARDING"] = "1"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_GB"]
        app.launch()
        XCTAssertTrue(app.staticTexts["onboarding-welcome-title"].waitForExistence(timeout: timeout))
        XCTAssertFalse(app.buttons["confirm-ledger-currency-button"].exists)
        tap("onboarding-get-started-button", in: app)

        let picker = app.buttons["onboarding-currency-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: timeout))
        XCTAssertEqual(picker.value as? String, "GBP")
        let incomeField = app.textFields["onboarding-income-field"]
        incomeField.tap()
        incomeField.typeText("5000")
        tap("onboarding-keyboard-done-button", in: app)
        XCTAssertTrue(scrollToVisibility(of: picker, in: app))
        picker.tap()
        tap("onboarding-currency-EUR", in: app)
        XCTAssertEqual(picker.value as? String, "EUR")
        tap("onboarding-budget-continue-button", in: app)
        tap("onboarding-back-button", in: app)
        XCTAssertEqual(picker.value as? String, "EUR")
        XCTAssertEqual(incomeField.value as? String, "5000")
        tap("onboarding-budget-continue-button", in: app)
        tap("onboarding-allocation-continue-button", in: app)
        tap("onboarding-sync-continue-button", in: app)
        tap("onboarding-tags-continue-button", in: app)
        tap("onboarding-reminders-continue-button", in: app)
        let total = app.staticTexts["onboarding-plan-total"]
        XCTAssertTrue(total.waitForExistence(timeout: timeout))
        XCTAssertEqual(total.label, Double(5000).formatted(.currency(code: "EUR").locale(Locale(identifier: "en_GB")).precision(.fractionLength(0))))
    }

    func testOnboardingValidatesIncomeAndRetainsStateWhenGoingBack() {
        let app = launchApp(showsOnboarding: true)
        tap("onboarding-get-started-button", in: app)

        let incomeField = app.textFields["onboarding-income-field"]
        let budgetContinue = app.buttons["onboarding-budget-continue-button"]
        XCTAssertTrue(incomeField.waitForExistence(timeout: timeout))
        XCTAssertTrue(budgetContinue.waitForExistence(timeout: timeout))
        XCTAssertFalse(budgetContinue.isEnabled, "Empty income must not allow continuing.")
        XCTAssertTrue(scrollToVisibility(of: incomeField, in: app))
        incomeField.tap()
        incomeField.typeText("0")
        XCTAssertFalse(budgetContinue.isEnabled, "Zero income must not allow continuing.")
        incomeField.clearAndTypeText("5000")
        XCTAssertTrue(budgetContinue.isEnabled)
        incomeField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        XCTAssertFalse(budgetContinue.isEnabled, "Clearing valid income must disable continuing again.")
        incomeField.typeText("5000")
        tap("onboarding-keyboard-done-button", in: app)
        tap("onboarding-budget-continue-button", in: app)
        tap("onboarding-allocation-continue-button", in: app)

        let syncToggle = app.switches["onboarding-sync-toggle"]
        XCTAssertTrue(syncToggle.waitForExistence(timeout: timeout))
        XCTAssertTrue(scrollToVisibility(of: syncToggle, in: app))
        XCTAssertEqual(syncToggle.value as? String, "0")
        #if DEBUG
        let expectedSyncValue = "0"
        XCTAssertFalse(syncToggle.isEnabled, "Dev builds must remain local-only.")
        #else
        let expectedSyncValue = "1"
        tap(syncToggle, named: "onboarding-sync-toggle")
        XCTAssertEqual(syncToggle.value as? String, "1")
        #endif
        tap("onboarding-sync-continue-button", in: app)

        let shoppingTag = app.buttons["onboarding-tag-Shopping"]
        XCTAssertTrue(shoppingTag.waitForExistence(timeout: timeout))
        XCTAssertTrue(scrollToVisibility(of: shoppingTag, in: app))
        XCTAssertTrue(shoppingTag.isSelected, "Suggested tags are selected by default.")
        tap(shoppingTag, named: "onboarding-tag-Shopping")
        XCTAssertFalse(shoppingTag.isSelected)
        tap("onboarding-tags-continue-button", in: app)
        tap("onboarding-reminders-continue-button", in: app)
        XCTAssertTrue(app.buttons["onboarding-start-tracking-button"].waitForExistence(timeout: timeout))

        tap("onboarding-back-button", in: app)
        XCTAssertTrue(app.buttons["onboarding-reminders-continue-button"].waitForExistence(timeout: timeout))
        tap("onboarding-back-button", in: app)
        XCTAssertTrue(shoppingTag.waitForExistence(timeout: timeout))
        XCTAssertFalse(shoppingTag.isSelected, "Tag deselection must survive returning from the summary.")
        tap("onboarding-back-button", in: app)
        XCTAssertTrue(syncToggle.waitForExistence(timeout: timeout))
        XCTAssertEqual(syncToggle.value as? String, expectedSyncValue, "Sync selection must survive going back.")
        tap("onboarding-back-button", in: app)
        XCTAssertTrue(app.buttons["onboarding-allocation-continue-button"].waitForExistence(timeout: timeout))
        tap("onboarding-back-button", in: app)
        XCTAssertTrue(incomeField.waitForExistence(timeout: timeout))
        XCTAssertEqual(incomeField.value as? String, "5000")
        XCTAssertTrue(budgetContinue.isEnabled)

        tap("onboarding-budget-continue-button", in: app)
        tap("onboarding-allocation-continue-button", in: app)
        XCTAssertTrue(syncToggle.waitForExistence(timeout: timeout))
        XCTAssertEqual(syncToggle.value as? String, expectedSyncValue)
        tap("onboarding-sync-continue-button", in: app)
        XCTAssertTrue(app.buttons["onboarding-tags-continue-button"].waitForExistence(timeout: timeout),
                      "Continue did not leave the sync step.")
        XCTAssertTrue(shoppingTag.waitForExistence(timeout: timeout))
        XCTAssertFalse(shoppingTag.isSelected, "Tag deselection must also survive returning from earlier steps.")
    }

    func testOnboardingAllocationDividersSnapAndRetainBreakdown() {
        let app = launchApp(showsOnboarding: true)
        tap("onboarding-get-started-button", in: app)
        let incomeField = app.textFields["onboarding-income-field"]
        XCTAssertTrue(incomeField.waitForExistence(timeout: timeout))
        incomeField.tap()
        incomeField.typeText("5000")
        tap("onboarding-keyboard-done-button", in: app)
        tap("onboarding-budget-continue-button", in: app)

        let bar = app.descendants(matching: .any)["onboarding-allocation-bar"].firstMatch
        let needs = app.descendants(matching: .any)["onboarding-needs-divider"].firstMatch
        let savings = app.descendants(matching: .any)["onboarding-savings-divider"].firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: timeout))

        func assertBreakdown(_ needsValue: Int, _ wantsValue: Int, _ savingsValue: Int) {
            XCTAssertEqual(needs.value as? String, "Needs \(needsValue)%, Wants \(wantsValue)%")
            XCTAssertEqual(savings.value as? String, "Wants \(wantsValue)%, Savings \(savingsValue)%")
        }

        func drag(_ divider: XCUIElement, by percentage: Double) {
            let start = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = start.withOffset(CGVector(dx: bar.frame.width * percentage / 100, dy: 0))
            start.press(forDuration: 0.1, thenDragTo: end)
        }

        assertBreakdown(50, 30, 20)
        let initial = XCTAttachment(screenshot: app.screenshot())
        initial.name = "Allocation - labeled bar"
        initial.lifetime = .keepAlways
        add(initial)

        drag(needs, by: 13)
        assertBreakdown(65, 15, 20)
        drag(savings, by: -8)
        assertBreakdown(65, 5, 30)
        drag(needs, by: 15)
        assertBreakdown(70, 0, 30)
        // Both handles must remain draggable even when the middle segment is collapsed.
        drag(savings, by: 10)
        assertBreakdown(70, 10, 20)
        drag(needs, by: -80)
        assertBreakdown(0, 80, 20)
        drag(needs, by: 35)
        assertBreakdown(35, 45, 20)
        drag(savings, by: 25)
        assertBreakdown(35, 65, 0)
        drag(savings, by: -20)
        assertBreakdown(35, 45, 20)

        tap("onboarding-allocation-continue-button", in: app)
        tap("onboarding-back-button", in: app)
        XCTAssertTrue(bar.waitForExistence(timeout: timeout))
        assertBreakdown(35, 45, 20)
        tap("onboarding-allocation-continue-button", in: app)
        tap("onboarding-sync-continue-button", in: app)
        tap("onboarding-tags-continue-button", in: app)
        tap("onboarding-reminders-continue-button", in: app)
        XCTAssertTrue(app.staticTexts["onboarding-plan-total"].waitForExistence(timeout: timeout))
        let summary = XCTAttachment(screenshot: app.screenshot())
        summary.name = "Allocation - adjusted summary"
        summary.lifetime = .keepAlways
        add(summary)
    }

    func testOnboardingSupportsLargestAccessibilityTextSize() {
        let app = XCUIApplication()
        app.launchEnvironment["SAGE_UI_TESTING"] = "1"
        app.launchEnvironment["SAGE_UI_TEST_ONBOARDING"] = "1"
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        let welcomeTitle = app.staticTexts["onboarding-welcome-title"]
        XCTAssertTrue(welcomeTitle.waitForExistence(timeout: timeout))

        let incomeField = app.textFields["onboarding-income-field"]
        let pages: [(String, XCUIElement)] = [
            ("onboarding-get-started-button", welcomeTitle),
            ("onboarding-budget-continue-button", incomeField),
            ("onboarding-allocation-continue-button", app.descendants(matching: .any)["onboarding-needs-divider"].firstMatch),
            ("onboarding-sync-continue-button", app.switches["onboarding-sync-toggle"]),
            ("onboarding-tags-continue-button", app.staticTexts["onboarding-tags-count"]),
            ("onboarding-reminders-continue-button", app.switches["onboarding-recurring-reminders-toggle"]),
            ("onboarding-start-tracking-button", app.staticTexts["onboarding-plan-total"])
        ]
        for (identifier, content) in pages {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: timeout))
            XCTAssertTrue(content.waitForExistence(timeout: timeout))
            XCTAssertTrue(scrollToVisibility(of: content, in: app))
            if identifier == "onboarding-budget-continue-button" {
                tap(incomeField, named: "onboarding-income-field")
                incomeField.typeText("5000")
                tap("onboarding-keyboard-done-button", in: app)
            }
            if identifier == "onboarding-reminders-continue-button" {
                let dailyReminder = app.switches["onboarding-daily-reminder-toggle"]
                XCTAssertTrue(dailyReminder.waitForExistence(timeout: timeout))
                XCTAssertTrue(scrollToVisibility(of: dailyReminder, in: app))
            }
            XCTAssertTrue(app.windows.firstMatch.frame.contains(button.frame))
            if identifier != "onboarding-get-started-button" {
                let back = app.buttons["onboarding-back-button"]
                XCTAssertTrue(back.isHittable)
                XCTAssertEqual(back.frame.midY, button.frame.midY, accuracy: 2, "Back belongs beside Continue.")
            }
            XCTAssertTrue(button.isEnabled, "The primary action on \(identifier) must be enabled.")
            XCTAssertTrue(button.waitForHittability(timeout: timeout), "The primary action on \(identifier) must remain reachable.")

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Largest text - \(identifier)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            button.tap()
        }

        XCTAssertTrue(app.tabBars.buttons["Expenses"].waitForExistence(timeout: timeout))
    }

    func testNewExpenseTapToFocusAndRetainsMinorUnitAmount() {
        let app = launchApp()
        openExpenses(in: app)
        openNewExpense(in: app)
        let wizard = ExpenseWizardUITestSupport(app: app)
        let nameField = wizard.name
        let keyboard = app.keyboards.firstMatch
        XCTAssertFalse(keyboard.exists)
        XCTAssertEqual(nameField.value as? String, nameField.placeholderValue)
        captureScreenshot("New expense - blank name without keyboard", in: app)
        wizard.enterName("Minor Unit Expense")
        wizard.advance(to: wizard.amount)
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: timeout))
        wizard.assertAmount(0)
        XCTAssertFalse(app.buttons["."].exists, "The inline keypad must accept minor-unit digits only.")
        wizard.enterAmountDigits("123")
        wizard.assertAmount(1.23)
        captureScreenshot("New expense - inline amount entry", in: app)
        tap("Delete last digit", in: app)
        wizard.assertAmount(0.12)
        wizard.goBack(to: nameField)
        XCTAssertEqual(nameField.value as? String, "Minor Unit Expense")
        XCTAssertFalse(keyboard.exists)
        wizard.advance(to: wizard.amount)
        wizard.assertAmount(0.12)
        wizard.enterAmountDigits("3")
        wizard.assertAmount(1.23)
        tap("Clear amount", in: app)
        wizard.assertAmount(0)
        wizard.enterAmountDigits("123")
        wizard.advanceFromAmountToDetails()
        wizard.saveAndWaitForDismissal()

        tap(expenseRow(named: "Minor Unit Expense", in: app), named: "Saved minor unit expense")
        XCTAssertTrue(nameField.waitForExistence(timeout: timeout))
        XCTAssertEqual(nameField.value as? String, "Minor Unit Expense")
        assertExpenseAmount(1.23, in: app)
    }

    func testNewExpenseReturnNextOpensInlineAmountKeypad() {
        let app = launchApp()
        openExpenses(in: app)
        openNewExpense(in: app)
        let wizard = ExpenseWizardUITestSupport(app: app)
        wizard.enterName("Return Next Expense")
        tap(app.keyboards.buttons["next"], named: "Keyboard return Next")
        XCTAssertTrue(wizard.amount.waitForExistence(timeout: timeout))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: timeout))
        XCTAssertFalse(app.buttons["."].exists)
        wizard.enterAmountDigits("1234")
        wizard.assertAmount(12.34)
        wizard.goBack(to: wizard.name)
        XCTAssertEqual(app.textFields["expense-name-field"].value as? String, "Return Next Expense")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
    }

    func testExpenseNameSuggestionPrefillsAndAllowsAmountEditing() {
        let app = launchApp(seedExpense: "Coffee Shop")
        openExpenses(in: app)
        openNewExpense(in: app)
        let wizard = ExpenseWizardUITestSupport(app: app)
        let nameField = app.textFields["expense-name-field"]
        let keyboard = app.keyboards.firstMatch
        let suggestions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "past-expense-suggestion-")).firstMatch
        wizard.enterName("Coff")
        XCTAssertTrue(suggestions.waitForExistence(timeout: timeout))
        let coffeeSuggestion = app.buttons["past-expense-suggestion-Coffee Shop"]
        captureScreenshot("New expense - name suggestions", in: app)
        XCTAssertTrue(coffeeSuggestion.waitForHittability(timeout: timeout), app.debugDescription)
        tap(coffeeSuggestion, named: "Coffee Shop suggestion")

        XCTAssertEqual(nameField.value as? String, "Coffee Shop")
        XCTAssertTrue(suggestions.waitForNonExistence(timeout: timeout), "Selecting a suggestion must hide the popup.")
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: timeout))
        XCTAssertTrue(nameField.isHittable, "Selecting history must stay on the name page.")
        XCTAssertFalse(wizard.amount.exists)
        captureScreenshot("New expense - suggestion stays on name", in: app)
        wizard.advance(to: wizard.amount)
        wizard.assertAmount(42.50)
        XCTAssertFalse(suggestions.exists)
        tap("Delete last digit", in: app)
        wizard.assertAmount(4.25)
        wizard.enterAmountDigits("5")
        wizard.assertAmount(42.55)
        wizard.advance(to: app.buttons["expense-category-wants"])
        XCTAssertEqual(app.buttons["expense-category-wants"].value as? String, "Selected")

        // Give the new expense a unique name so reopening cannot select the seed.
        wizard.goBack(to: wizard.amount)
        wizard.goBack(to: nameField)
        nameField.clearAndTypeText("Coffee Shop Visit")
        wizard.advance(to: wizard.amount)
        XCTAssertTrue(suggestions.waitForNonExistence(timeout: timeout))
        wizard.assertAmount(42.55)
        wizard.advanceFromAmountToDetails()
        wizard.saveAndWaitForDismissal()
        tap(expenseRow(named: "Coffee Shop Visit", in: app), named: "Saved suggested expense")
        XCTAssertTrue(nameField.waitForExistence(timeout: timeout))
        XCTAssertEqual(nameField.value as? String, "Coffee Shop Visit")
        assertExpenseAmount(42.55, in: app)
        XCTAssertEqual(app.buttons["expense-category-wants"].value as? String, "Selected")
    }

    func testRefundAmountPersistsAfterSavingAndReopening() {
        let app = launchApp()
        openExpenses(in: app)
        openNewExpense(in: app)
        let wizard = ExpenseWizardUITestSupport(app: app)
        let nameField = app.textFields["expense-name-field"]
        wizard.enterName("Returned Purchase")
        wizard.advance(to: wizard.amount)
        wizard.enterAmountDigits("1234")
        wizard.assertAmount(12.34)
        tap("expense-amount-type", in: app)
        tap("Refund", in: app)
        XCTAssertEqual(app.buttons["expense-amount-type"].value as? String, "Refund")
        wizard.assertAmount(-12.34)
        wizard.advance(to: app.buttons["expense-category-needs"])
        wizard.goBack(to: wizard.amount)
        wizard.assertAmount(-12.34)
        XCTAssertEqual(app.buttons["expense-amount-type"].value as? String, "Refund")
        wizard.advance(to: app.buttons["expense-category-needs"])
        wizard.advance(to: wizard.datePicker)
        let recurring = app.switches["expense-recurring-toggle"]
        wizard.reveal(recurring)
        recurring.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(recurring.value as? String, "0", "Refunds must not enable recurrence.")
        XCTAssertFalse(app.buttons["expense-frequency-picker"].exists)
        XCTAssertEqual(recurring.value as? String, "0")
        wizard.advance(to: wizard.note)
        wizard.saveAndWaitForDismissal()

        tap(expenseRow(named: "Returned Purchase", in: app), named: "Saved refund")
        XCTAssertTrue(nameField.waitForExistence(timeout: timeout))
        XCTAssertEqual(nameField.value as? String, "Returned Purchase")
        assertExpenseAmount(-12.34, in: app)
        XCTAssertEqual(app.buttons["expense-amount-type"].value as? String, "Refund")
    }

    func testNewExpenseSupportsLongNameAtLargestAccessibilityTextSize() {
        let app = launchApp(launchArguments: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ])
        openExpenses(in: app)
        openNewExpense(in: app)
        let wizard = ExpenseWizardUITestSupport(app: app)
        let nameField = app.textFields["expense-name-field"]
        let amountField = wizard.amount
        let keyboard = app.keyboards.firstMatch
        let longName = "Weekly groceries and household supplies for the entire family"
        XCTAssertFalse(keyboard.exists)
        captureScreenshot("New expense largest text - blank name", in: app)
        wizard.enterName(longName)
        XCTAssertEqual(nameField.value as? String, longName)
        wizard.assertFooter(keyboardVisible: true, hasBack: false)
        captureScreenshot("New expense largest text - long name", in: app)
        tap(app.keyboards.buttons["next"], named: "Keyboard return Next")
        wizard.enterAmountDigits("123456")
        wizard.assertAmount(1234.56)
        XCTAssertTrue(scrollToVisibility(of: amountField, in: app))
        XCTAssertTrue(amountField.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(amountField.frame))
        captureScreenshot("New expense largest text - amount entry", in: app)
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: timeout))
        for identifier in ["expense-category-wants", "expense-date-picker", "expense-note-field"] {
            let control = app.descendants(matching: .any)[identifier].firstMatch
            wizard.advance(to: control)
            XCTAssertTrue(scrollToVisibility(of: control, in: app), "Every wizard page must remain reachable at largest text size.")
            let footer = identifier == "expense-note-field" ? wizard.save : wizard.next
            XCTAssertTrue(scrollToVisibility(of: footer, in: app))
            wizard.assertFooter(keyboardVisible: false, final: identifier == "expense-note-field")
            captureScreenshot("New expense largest text - \(identifier)", in: app)
            if identifier == "expense-date-picker" {
                let recurring = app.switches["expense-recurring-toggle"]
                XCTAssertTrue(scrollToVisibility(of: recurring, in: app))
                XCTAssertEqual(recurring.value as? String, "0")
                captureScreenshot("New expense largest text - recurrence", in: app)
            }
        }
        wizard.saveAndWaitForDismissal()
        tap(expenseRow(named: longName, in: app), named: "Saved long-name expense")
        XCTAssertTrue(nameField.waitForExistence(timeout: timeout))
        XCTAssertEqual(nameField.value as? String, longName)
        assertExpenseAmount(1234.56, in: app)
    }

    func testRecurringScheduleEditRequiresConfirmationAndPersists() {
        let app = launchApp(seedCalendar: true)
        tap(app.tabBars.buttons["Settings"], named: "Settings")
        tap("Recurring Expenses", in: app)
        tap(app.staticTexts["Calendar Subscription"],
            named: "Calendar Subscription")
        let frequency = app.descendants(matching: .any)["recurring-frequency-picker"].firstMatch
        XCTAssertTrue(scrollToVisibility(of: frequency, in: app))
        frequency.tap()
        tap("Weekly", in: app)
        tap("Save", in: app)
        let confirmation = app.buttons["Update Future Schedule"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: timeout))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Schedule edit confirmation"
        attachment.lifetime = .keepAlways
        add(attachment)
        confirmation.tap()
        let row = app.staticTexts["Calendar Subscription"]
        XCTAssertTrue(row.waitForExistence(timeout: timeout))
        row.tap()
        XCTAssertTrue(scrollToVisibility(of: frequency, in: app))
        XCTAssertTrue(frequency.label.contains("Weekly"))
        XCTAssertFalse(app.buttons["Time Zone"].exists)
        XCTAssertFalse(app.switches["Use Fixed Schedule"].exists)
        tap("Cancel", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: timeout))
    }

    func testRecurringReminderSettings() {
        let app = launchApp()
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: timeout))
        settings.tap()
        app.buttons["Notifications"].tap()
        let enabled = app.switches["bill-reminders-toggle"]
        let privacy = app.switches["bill-reminder-privacy"]
        let days = app.buttons["bill-reminder-days"]
        let time = app.datePickers["bill-reminder-time"]
        XCTAssertTrue(enabled.waitForExistence(timeout: timeout))
        XCTAssertEqual(enabled.value as? String, "0")
        XCTAssertFalse(privacy.exists)
        XCTAssertFalse(days.exists)
        XCTAssertFalse(time.exists)
        // SwiftUI exposes the entire row as a switch; its center is empty space.
        XCTAssertTrue(enabled.waitForHittability(timeout: timeout))
        enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(enabled.value as? String, "1")
        XCTAssertTrue(days.waitForExistence(timeout: timeout))
        XCTAssertTrue(days.isEnabled)
        XCTAssertTrue(time.exists)
        XCTAssertEqual(privacy.value as? String, "1")
        XCTAssertEqual(days.value as? String, "1 day before")
        days.tap()
        XCTAssertFalse(app.buttons["8 days before"].exists)
        app.buttons["7 days before"].tap()
        XCTAssertEqual(days.value as? String, "7 days before")
        XCTAssertTrue(privacy.waitForHittability(timeout: timeout))
        privacy.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(privacy.value as? String, "0")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Recurring reminder settings"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(enabled.waitForHittability(timeout: timeout))
        enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(days.waitForNonExistence(timeout: timeout))
        XCTAssertFalse(time.exists)
        XCTAssertFalse(privacy.exists)
    }

    func testNotificationsSettingsShowsDailyTimeOnlyWhenEnabled() {
        let app = launchApp()
        tap(app.tabBars.buttons["Settings"], named: "Settings")
        XCTAssertFalse(app.buttons["Daily Reminder"].exists)
        tap("Notifications", in: app)
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: timeout))

        let recurring = app.switches["bill-reminders-toggle"]
        let daily = app.switches["daily-expense-reminder-toggle"]
        let time = app.datePickers["daily-expense-reminder-time"]
        XCTAssertTrue(recurring.exists)
        XCTAssertEqual(recurring.value as? String, "0")
        XCTAssertTrue(scrollToVisibility(of: daily, in: app))
        XCTAssertEqual(daily.value as? String, "0")
        XCTAssertFalse(time.exists)
        captureScreenshot("Notifications - daily reminder off", in: app)

        daily.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(time.waitForExistence(timeout: timeout))
        XCTAssertTrue(scrollToVisibility(of: time, in: app))
        XCTAssertTrue(time.isEnabled)
        XCTAssertEqual(recurring.value as? String, "0", "Enabling daily reminders must not enable recurring reminders.")
        captureScreenshot("Notifications - daily reminder on", in: app)

        XCTAssertTrue(scrollToVisibility(of: daily, in: app))
        daily.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(time.waitForNonExistence(timeout: timeout))
    }

    func testShowAllRestoresMonthAndClearsDetail() {
        let app = launchApp(seedExpense: "Navigation Expense")
        let showAll = app.buttons["show-all-expenses-button"]
        XCTAssertTrue(scrollToVisibility(of: showAll, in: app))
        showAll.tap()
        XCTAssertTrue(app.tabBars.buttons["Expenses"].isSelected)
        let row = expenseRow(named: "Navigation Expense", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: timeout))

        tap("Previous Month", in: app)
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(scrollToVisibility(of: showAll, in: app))
        showAll.tap()
        XCTAssertTrue(row.waitForExistence(timeout: timeout))

        row.tap()
        XCTAssertTrue(app.textFields["expense-name-field"].waitForExistence(timeout: timeout))
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(scrollToVisibility(of: showAll, in: app))
        showAll.tap()
        XCTAssertTrue(row.waitForExistence(timeout: timeout))
        XCTAssertFalse(app.textFields["expense-name-field"].exists)
    }

    func testExpenseCalendarShowsDailySpendingAndChangesMonth() {
        let app = launchApp(seedExpense: "Calendar Expense")
        let calendar = Calendar.current
        let now = Date.now
        let dayNumber = calendar.component(.day, from: now)
        let today = app.descendants(matching: .any)["expense-calendar-day-\(dayNumber)"].firstMatch
        XCTAssertTrue(scrollToVisibility(of: today, in: app))
        XCTAssertEqual(today.value as? String, "\(42.50.formatted(.currency(code: "USD"))) spent, Today")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Expense calendar - current month"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        XCTAssertTrue(app.staticTexts["Expense Calendar"].exists)
        tap("Previous Month", in: app)
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: now)!
        let firstDay = app.descendants(matching: .any)["expense-calendar-day-1"].firstMatch
        let monthStart = calendar.dateInterval(of: .month, for: previousMonth)!.start
        XCTAssertEqual(firstDay.label, monthStart.formatted(date: .complete, time: .omitted))
        XCTAssertEqual(firstDay.value as? String, "\(Double(0).formatted(.currency(code: "USD"))) spent")
        tap("Next Month", in: app)
        XCTAssertEqual(today.value as? String, "\(42.50.formatted(.currency(code: "USD"))) spent, Today")
        XCTAssertFalse(app.buttons["Next Month"].isEnabled)

        openExpenses(in: app)
        addExpense(named: "Another Calendar Expense", amount: "12.34", in: app)
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(scrollToVisibility(of: today, in: app))
        XCTAssertEqual(today.value as? String, "\(54.84.formatted(.currency(code: "USD"))) spent, Today")
    }

    func testCalendarPopupListsRecordedExpensesAndDismissesOutside() {
        let app = launchApp(seedExpense: "Calendar Expense", seedCalendar: true)
        let day = Calendar.current.component(.day, from: .now)
        let today = app.buttons["expense-calendar-day-\(day)"]
        XCTAssertTrue(scrollToVisibility(of: today, in: app))
        today.tap()

        let total = app.staticTexts["expense-calendar-day-total"]
        XCTAssertTrue(total.waitForExistence(timeout: timeout))
        XCTAssertEqual(total.label, "\(Double(50).formatted(.currency(code: "USD"))) spent this day")
        XCTAssertTrue(app.otherElements["expense-calendar-day-details"].staticTexts["Calendar Expense"].isHittable)
        XCTAssertTrue(app.otherElements["expense-calendar-day-details"].staticTexts["Calendar Coffee"].isHittable)
        // A tap inside the popup must leave it open.
        total.tap()
        XCTAssertTrue(total.exists)
        app.tabBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(total.waitForNonExistence(timeout: timeout))
        XCTAssertTrue(app.tabBars.buttons["Home"].isSelected)
        today.tap()
        XCTAssertTrue(total.waitForExistence(timeout: timeout))
    }

    func testCalendarPopupShowsEmptyPastDay() {
        let app = launchApp()
        let today = app.buttons["expense-calendar-day-\(Calendar.current.component(.day, from: .now))"]
        XCTAssertTrue(scrollToVisibility(of: today, in: app))
        tap("Previous Month", in: app)
        let firstDay = app.buttons["expense-calendar-day-1"]
        XCTAssertTrue(scrollToVisibility(of: firstDay, in: app))
        firstDay.tap()
        XCTAssertTrue(app.staticTexts["No expenses recorded for this day."].waitForExistence(timeout: timeout))
        XCTAssertEqual(app.staticTexts["expense-calendar-day-total"].label,
                       "\(Double(0).formatted(.currency(code: "USD"))) spent this day")
    }

    func testCalendarShowsFutureRecurringAmountsAndUpcomingPopup() throws {
        let calendar = Calendar.current
        let now = Date.now
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        try XCTSkipUnless(calendar.isDate(now, equalTo: tomorrow, toGranularity: .month),
                          "The dashboard only displays current and past months; run before the last day of the month.")
        let app = launchApp(seedCalendar: true)
        let tomorrowCell = app.buttons["expense-calendar-day-\(calendar.component(.day, from: tomorrow))"]
        XCTAssertTrue(scrollToVisibility(of: tomorrowCell, in: app))
        XCTAssertEqual(tomorrowCell.value as? String, "\(Double(15).formatted(.currency(code: "USD"))) upcoming")
        tomorrowCell.tap()
        let total = app.staticTexts["expense-calendar-day-total"]
        XCTAssertTrue(total.waitForExistence(timeout: timeout))
        XCTAssertEqual(total.label, "\(Double(15).formatted(.currency(code: "USD"))) expected this day")
        let details = app.otherElements["expense-calendar-day-details"]
        XCTAssertTrue(details.staticTexts["Calendar Subscription"].isHittable)
        XCTAssertFalse(details.staticTexts["Expired Subscription"].exists)
        app.tabBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(total.waitForNonExistence(timeout: timeout))
    }

    func testIPhoneStaysPortraitWhenDeviceRotates() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchApp()
        openExpenses(in: app)
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(app.tabBars.buttons["Expenses"].waitForExistence(timeout: timeout))
            let frame = app.windows.firstMatch.frame
            XCTAssertLessThan(frame.width, frame.height)
            XCTAssertTrue(app.tabBars.buttons["Expenses"].isHittable)
        }
    }

    func testEditsExpense() {
        let app = launchApp(seedExpense: "Expense to Edit")
        openExpenses(in: app)

        let originalRow = expenseRow(named: "Expense to Edit", in: app)
        XCTAssertTrue(originalRow.waitForExistence(timeout: timeout), "The seeded expense did not appear.")
        originalRow.tap()

        let nameField = app.textFields["expense-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: timeout), "The edit form did not appear.")
        nameField.clearAndTypeText("Edited Expense")
        tap("save-expense-changes-button", in: app)

        XCTAssertTrue(
            app.staticTexts["Edited Expense"].waitForExistence(timeout: timeout),
            "The edited expense name did not appear in the list."
        )
    }

    func testDuplicatesExpense() {
        let app = launchApp(seedExpense: "Expense to Duplicate")
        openExpenses(in: app)

        let originalRow = expenseRow(named: "Expense to Duplicate", in: app)
        XCTAssertTrue(originalRow.waitForExistence(timeout: timeout), "The seeded expense did not appear.")
        originalRow.swipeLeft()
        tap("duplicate-expense-action", in: app)

        let nameField = app.textFields["expense-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: timeout), "The duplicate form did not appear.")
        XCTAssertEqual(nameField.value as? String, "Expense to Duplicate")
        let wizard = ExpenseWizardUITestSupport(app: app)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        wizard.advance(to: wizard.amount)
        wizard.assertAmount(42.50)
        wizard.advance(to: app.buttons["expense-category-wants"])
        XCTAssertEqual(app.buttons["expense-category-wants"].value as? String, "Selected")
        wizard.advance(to: wizard.datePicker)
        wizard.advance(to: wizard.note)
        wizard.saveAndWaitForDismissal()

        let duplicate = app.descendants(matching: .any)
            .matching(identifier: "expense-row-Expense to Duplicate")
            .element(boundBy: 1)
        XCTAssertTrue(duplicate.waitForExistence(timeout: timeout), "The duplicate expense did not appear.")
        tap(duplicate, named: "Saved duplicate")
        XCTAssertTrue(nameField.waitForExistence(timeout: timeout))
        XCTAssertEqual(nameField.value as? String, "Expense to Duplicate")
        assertExpenseAmount(42.50, in: app)
        XCTAssertEqual(app.buttons["expense-category-wants"].value as? String, "Selected")
    }

    func testSearchesExpenses() {
        let app = launchApp(seedExpense: "Search Needle")
        openExpenses(in: app)

        // Swipe down so that the search bar is visible. Sometimes it gets hidden above the first expense in the list.
        app.swipeDown()

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: timeout), "The expense search field did not appear.")

        searchField.tap()
        searchField.typeText("Needle")

        XCTAssertTrue(
            expenseRow(named: "Search Needle", in: app).waitForExistence(timeout: timeout),
            "The matching expense did not appear in search results."
        )
        searchField.typeText(" missing")
        XCTAssertTrue(app.staticTexts["No matching expenses"].waitForExistence(timeout: timeout))
        XCTAssertTrue(expenseRow(named: "Search Needle", in: app).waitForNonExistence(timeout: timeout))
        searchField.buttons["Clear text"].tap()
        XCTAssertTrue(expenseRow(named: "Search Needle", in: app).waitForExistence(timeout: timeout))
    }

    func testSearchLoadsOlderResultsAndResetsForNewQuery() {
        let app = XCUIApplication()
        app.launchEnvironment["SAGE_UI_TESTING"] = "1"
        app.launchEnvironment["SAGE_UI_TEST_ONBOARDING"] = "0"
        app.launchEnvironment["SAGE_UI_TEST_SEED_SEARCH"] = "1"
        app.launch()
        let searchTab = app.tabBars.buttons["Search"]
        XCTAssertTrue(searchTab.waitForExistence(timeout: timeout))
        searchTab.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        field.tap()
        field.typeText("Needle")

        let results = app.collectionViews.firstMatch
        XCTAssertTrue(results.waitForExistence(timeout: timeout))
        dismissSearchKeyboard(in: app)
        let more = app.buttons["search-load-more"]
        for _ in 0..<40 {
            if more.exists && more.isHittable { break }
            results.swipeUp()
        }
        XCTAssertTrue(more.isHittable)
        more.tap()
        let older = expenseRow(named: "Search Needle 100", in: app)
        for _ in 0..<5 {
            if older.exists && older.isHittable { break }
            results.swipeUp()
        }
        XCTAssertTrue(older.isHittable, "The oldest match should become reachable after loading more.")
        XCTAssertFalse(more.exists, "The final page should not offer more results.")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Search - oldest result after loading more"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        field.tap()
        field.typeText(" 100")
        XCTAssertTrue(older.waitForExistence(timeout: timeout))
        field.buttons["Clear text"].tap()
        field.typeText("Needle")
        dismissSearchKeyboard(in: app)
        for _ in 0..<40 {
            if more.exists && more.isHittable { break }
            results.swipeUp()
        }
        XCTAssertTrue(more.isHittable, "Changing the query must reset pagination to 100 results.")
    }

    func testDeletesExpense() {
        let app = launchApp(seedExpense: "Expense to Delete")
        openExpenses(in: app)

        let row = expenseRow(named: "Expense to Delete", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: timeout), "The seeded expense did not appear.")
        row.swipeLeft()
        tap("delete-expense-action", in: app)
        tap("confirm-delete-expense-button", in: app)

        XCTAssertTrue(
            row.waitForNonExistence(timeout: timeout),
            "The deleted expense remained in the expense list."
        )
    }

    func testDeletesDashboardExpense() {
        let app = launchApp(showsOnboarding: false, seedExpense: "Dashboard Expense to Delete")

        app.swipeUp()
        app.swipeUp()
        
        let row = expenseRow(named: "Dashboard Expense to Delete", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: timeout), "The dashboard expense did not appear.")
        
        revealDeleteAction(for: row)
        tap("delete-expense-action", in: app)
        tap("confirm-delete-expense-button", in: app)

        XCTAssertTrue(
            row.waitForNonExistence(timeout: timeout),
            "The deleted expense remained on the dashboard."
        )
    }

    private func launchApp(showsOnboarding: Bool = false, seedExpense: String? = nil, seedCalendar: Bool = false, launchArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SAGE_UI_TESTING"] = "1"
        app.launchEnvironment["SAGE_UI_TEST_ONBOARDING"] = showsOnboarding ? "1" : "0"
        if let seedExpense {
            app.launchEnvironment["SAGE_UI_TEST_SEED_EXPENSE"] = seedExpense
        }
        app.launchEnvironment["SAGE_UI_TEST_SEED_CALENDAR"] = seedCalendar ? "1" : "0"
        app.launchArguments += launchArguments
        app.launch()
        return app
    }

    private func openExpenses(in app: XCUIApplication) {
        let expensesTab = app.tabBars.buttons["Expenses"]
        XCTAssertTrue(expensesTab.waitForExistence(timeout: timeout), "The Expenses tab did not appear.")
        expensesTab.tap()
    }

    private func assertReminderSettings(recurringEnabled: Bool, dailyEnabled: Bool, in app: XCUIApplication) {
        tap(app.tabBars.buttons["Settings"], named: "Settings tab")
        tap("Notifications", in: app)
        for (identifier, enabled) in [
            ("bill-reminders-toggle", recurringEnabled),
            ("daily-expense-reminder-toggle", dailyEnabled)
        ] {
            let toggle = app.switches[identifier]
            XCTAssertTrue(toggle.waitForExistence(timeout: timeout))
            XCTAssertTrue(scrollToVisibility(of: toggle, in: app))
            XCTAssertEqual(toggle.value as? String, enabled ? "1" : "0", "Start Tracking must save the onboarding choice for \(identifier).")
        }
        tap(app.navigationBars.buttons.firstMatch, named: "Back to Settings")
    }

    private func openNewExpense(in app: XCUIApplication) {
        ExpenseWizardUITestSupport(app: app).open()
    }

    private func addExpense(named name: String, amount: String, in app: XCUIApplication) {
        openNewExpense(in: app)
        let wizard = ExpenseWizardUITestSupport(app: app)
        wizard.enterName(name)
        wizard.advance(to: wizard.amount)
        // Callers supply whole currency values; the new field accepts minor-unit digits.
        guard let value = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) else {
            XCTFail("Invalid expense amount: \(amount)")
            return
        }
        wizard.enterAmountDigits(NSDecimalNumber(decimal: value * 100).stringValue)
        wizard.assertAmount(NSDecimalNumber(decimal: value).doubleValue)
        wizard.advanceFromAmountToDetails()
        wizard.saveAndWaitForDismissal()
    }

    private func assertExpenseAmount(_ amount: Double, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        ExpenseWizardUITestSupport(app: app).assertAmount(amount, editing: true, file: file, line: line)
    }

    private func captureScreenshot(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func expenseRow(named name: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "expense-row-\(name)").firstMatch
    }

    private func dismissSearchKeyboard(in app: XCUIApplication) {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }
        let search = keyboard.buttons
            .matching(NSPredicate(format: "label ==[c] %@", "search"))
            .firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: timeout), "The keyboard Search button did not appear.")
        search.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: timeout), "The search keyboard did not dismiss.")
    }

    private func scrollToVisibility(of element: XCUIElement, in app: XCUIApplication) -> Bool {
        let window = app.windows.firstMatch
        for _ in 0..<10 {
            // Lazy list rows do not exist in the accessibility tree until scrolled into view.
            if element.exists {
                let frame = element.frame
                if window.exists,
                   !frame.isNull,
                   !frame.isEmpty,
                   window.frame.contains(frame),
                   element.isHittable {
                    return true
                }
            }
            app.swipeUp()
        }
        XCTFail("The element did not become visible.\n\(app.debugDescription)")
        return false
    }

    private func revealDeleteAction(for row: XCUIElement) {
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        let end = row.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    private func tap(_ identifier: String, in app: XCUIApplication) {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        tap(element, named: identifier)
    }

    private func tap(_ element: XCUIElement, named identifier: String) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "The element '\(identifier)' did not appear.")
        XCTAssertTrue(
            element.waitForHittability(timeout: timeout),
            "The element '\(identifier)' was not hittable."
        )
        element.tap()
    }
}

private extension XCUIElement {
    func waitForHittability(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    func clearAndTypeText(_ text: String) {
        let currentText = value as? String ?? ""
        coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentText.count))
        typeText(text)
    }
}
