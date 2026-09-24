import XCTest

@MainActor
final class NewAddExpenseFlowUITests: XCTestCase {
    private let timeout: TimeInterval = 20

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testNotesTagsAndRecurrenceSurviveEveryBackStepAndPersist() {
        let app = launchExpenses()
        let wizard = ExpenseWizardUITestSupport(app: app)
        let expenseName = "Weekly wizard expense"
        let note = "First line of the note\nSecond line survives navigation"
        let tagName = "Wizard tag"
        wizard.open()
        wizard.enterName(expenseName)
        wizard.advance(to: wizard.amount)
        wizard.enterAmountDigits("2468")
        wizard.advance(to: app.buttons["expense-category-wants"])
        wizard.tap(app.buttons["expense-category-wants"])
        XCTAssertEqual(app.buttons["expense-category-wants"].value as? String, "Selected")
        wizard.advance(to: wizard.datePicker)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: timeout))
        let dateValue = wizard.selectedDate.value as? String
        XCTAssertNotNil(dateValue)
        let recurring = app.switches["expense-recurring-toggle"]
        wizard.reveal(recurring)
        XCTAssertEqual(recurring.value as? String, "0")
        XCTAssertFalse(app.buttons["expense-frequency-picker"].exists)
        recurring.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(recurring.value as? String, "1")
        let frequency = app.buttons["expense-frequency-picker"]
        wizard.reveal(frequency)
        wizard.tap(frequency)
        wizard.tap(app.buttons["Weekly"])
        assertFrequency("Weekly", picker: frequency)
        screenshot("Wizard - weekly recurrence", in: app)

        wizard.advance(to: wizard.note)
        let addTag = app.buttons.containing(.staticText, identifier: "Add new tag").firstMatch
        wizard.reveal(addTag)
        wizard.tap(addTag)
        let tagField = app.textFields["Tag Name"]
        wizard.tap(tagField)
        app.typeText(tagName)
        wizard.tap(app.buttons["Add Tag"])
        XCTAssertTrue(tagField.waitForNonExistence(timeout: timeout))
        let tag = app.buttons["Tag: \(tagName)"]
        wizard.reveal(tag)
        XCTAssertEqual(tag.value as? String, "Selected")
        XCTAssertTrue(tag.isSelected)
        wizard.reveal(wizard.note)
        wizard.tap(wizard.note)
        app.typeText(note)
        XCTAssertEqual(wizard.note.value as? String, note)
        screenshot("Wizard - multiline note and selected tag", in: app)

        wizard.goBack(to: wizard.datePicker)
        XCTAssertEqual(wizard.selectedDate.value as? String, dateValue)
        wizard.reveal(recurring)
        XCTAssertEqual(recurring.value as? String, "1")
        wizard.reveal(frequency)
        assertFrequency("Weekly", picker: frequency)
        wizard.goBack(to: app.buttons["expense-category-wants"])
        XCTAssertEqual(app.buttons["expense-category-wants"].value as? String, "Selected")
        wizard.goBack(to: wizard.amount)
        wizard.assertAmount(24.68)
        wizard.goBack(to: wizard.name)
        XCTAssertEqual(wizard.name.value as? String, expenseName)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertFalse(wizard.back.exists)
        screenshot("Wizard - back to preserved name", in: app)

        wizard.advance(to: wizard.amount)
        wizard.assertAmount(24.68)
        wizard.advance(to: app.buttons["expense-category-wants"])
        XCTAssertEqual(app.buttons["expense-category-wants"].value as? String, "Selected")
        wizard.advance(to: wizard.datePicker)
        XCTAssertEqual(wizard.selectedDate.value as? String, dateValue)
        wizard.reveal(recurring)
        XCTAssertEqual(recurring.value as? String, "1")
        wizard.reveal(frequency)
        assertFrequency("Weekly", picker: frequency)
        wizard.advance(to: wizard.note)
        XCTAssertEqual(wizard.note.value as? String, note)
        XCTAssertEqual(tag.value as? String, "Selected")
        wizard.saveAndWaitForDismissal()

        // Reopen the persisted expense in the original full edit form.
        wizard.tap(expenseRow(expenseName, in: app))
        XCTAssertTrue(wizard.name.waitForExistence(timeout: timeout))
        XCTAssertEqual(wizard.name.value as? String, expenseName)
        wizard.assertAmount(24.68, editing: true)
        XCTAssertEqual(app.buttons["expense-category-wants"].value as? String, "Selected")
        wizard.reveal(wizard.note)
        XCTAssertEqual(wizard.note.value as? String, note)
        XCTAssertEqual(app.buttons["Date"].value as? String, dateValue)
        wizard.reveal(tag)
        XCTAssertEqual(tag.value as? String, "Selected")
        XCTAssertTrue(tag.isSelected)
        XCTAssertFalse(wizard.next.exists, "Existing expenses must still use the full edit form.")
        wizard.tap(app.buttons["back-expense-button"])

        // A selected switch is not proof that a recurring rule was saved.
        wizard.tap(app.tabBars.buttons["Settings"])
        wizard.tap(app.buttons["Recurring Expenses"])
        wizard.tap(app.staticTexts[expenseName])
        XCTAssertTrue(wizard.name.waitForExistence(timeout: timeout))
        XCTAssertEqual(wizard.name.value as? String, expenseName)
        wizard.assertAmount(24.68, editing: true)
        XCTAssertEqual(app.buttons["expense-category-wants"].value as? String, "Selected")
        wizard.reveal(wizard.note)
        XCTAssertEqual(wizard.note.value as? String, note)
        XCTAssertEqual(app.buttons["Date"].value as? String, dateValue)
        wizard.reveal(tag)
        XCTAssertEqual(tag.value as? String, "Selected")
        let savedFrequency = app.buttons["recurring-frequency-picker"]
        wizard.reveal(savedFrequency)
        assertFrequency("Weekly", picker: savedFrequency)
        screenshot("Wizard - persisted recurring rule", in: app)
    }

    func testSwipingAwayDiscardsBlankAndPopulatedDrafts() {
        let app = launchExpenses()
        let wizard = ExpenseWizardUITestSupport(app: app)
        wizard.open()
        XCTAssertFalse(app.buttons["cancel-expense-button"].exists)
        wizard.dismissBySwipe()

        wizard.open()
        wizard.enterName("Discarded wizard expense")
        wizard.advance(to: wizard.amount)
        wizard.enterAmountDigits("9876")
        wizard.advance(to: app.buttons["expense-category-wants"])
        wizard.tap(app.buttons["expense-category-wants"])
        wizard.advance(to: wizard.datePicker)
        let recurring = app.switches["expense-recurring-toggle"]
        wizard.reveal(recurring)
        recurring.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let frequency = app.buttons["expense-frequency-picker"]
        wizard.reveal(frequency)
        wizard.tap(frequency)
        wizard.tap(app.buttons["Weekly"])
        XCTAssertEqual(recurring.value as? String, "1")
        assertFrequency("Weekly", picker: frequency)
        wizard.advance(to: wizard.note)
        wizard.tap(wizard.note)
        app.typeText("Unsaved note\nKeep both lines")
        XCTAssertTrue(wizard.save.isHittable)
        wizard.goBack(to: wizard.datePicker)
        wizard.goBack(to: app.buttons["expense-category-wants"])
        XCTAssertEqual(app.buttons["expense-category-wants"].value as? String, "Selected")
        wizard.goBack(to: wizard.amount)
        wizard.assertAmount(98.76)
        wizard.goBack(to: wizard.name)
        XCTAssertEqual(wizard.name.value as? String, "Discarded wizard expense")
        wizard.dismissBySwipe()
        XCTAssertFalse(expenseRow("Discarded wizard expense", in: app).exists)
        XCTAssertTrue(app.staticTexts["No expenses for this month"].waitForExistence(timeout: timeout))

        wizard.open()
        XCTAssertEqual(wizard.name.value as? String, wizard.name.placeholderValue)
        wizard.enterName("Fresh draft")
        wizard.advance(to: wizard.amount)
        wizard.assertAmount(0)
        wizard.enterAmountDigits("100")
        wizard.advance(to: app.buttons["expense-category-needs"])
        XCTAssertEqual(app.buttons["expense-category-needs"].value as? String, "Selected")
        wizard.advance(to: wizard.datePicker)
        wizard.reveal(recurring)
        XCTAssertEqual(recurring.value as? String, "0")
        XCTAssertFalse(frequency.exists)
        wizard.advance(to: wizard.note)
        XCTAssertEqual(wizard.note.value as? String, wizard.note.placeholderValue)
        wizard.goBack(to: wizard.datePicker)
        wizard.goBack(to: app.buttons["expense-category-needs"])
        wizard.goBack(to: wizard.amount)
        wizard.goBack(to: wizard.name)
        wizard.dismissBySwipe()
        wizard.tap(app.tabBars.buttons["Settings"])
        wizard.tap(app.buttons["Recurring Expenses"])
        XCTAssertTrue(app.staticTexts["No Recurring Expense Rules"].waitForExistence(timeout: timeout),
                      "Dismissal must not persist a recurring rule or expense.")
    }

    func testKeyboardFooterFramesAndDateRoundTripWithAnimations() {
        // Use normal system animations. No launch flag disables motion or shortens transitions.
        let app = launchExpenses()
        let wizard = ExpenseWizardUITestSupport(app: app)
        wizard.open()
        let restingFooter = wizard.assertFooter(keyboardVisible: false, hasBack: false)
        screenshot("Wizard motion 01 - name resting", in: app)
        wizard.enterName("Keyboard footer roundtrip")
        let focusedFooter = wizard.assertFooter(keyboardVisible: true, hasBack: false)
        XCTAssertLessThan(focusedFooter.maxY, restingFooter.maxY - 100)
        screenshot("Wizard motion 02 - name keyboard", in: app)
        wizard.advance(to: wizard.amount)
        let amountFooter = wizard.assertFooter(keyboardVisible: false)
        XCTAssertEqual(amountFooter.maxY, restingFooter.maxY, accuracy: 3)
        wizard.enterAmountDigits("1234")
        screenshot("Wizard motion 03 - inline keypad", in: app)
        wizard.advance(to: app.buttons["expense-category-needs"])
        wizard.assertFooter(keyboardVisible: false)
        screenshot("Wizard motion 04 - category", in: app)
        wizard.advance(to: wizard.datePicker)
        let dateFooter = wizard.assertFooter(keyboardVisible: false)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(wizard.datePicker.frame))
        XCTAssertLessThanOrEqual(wizard.datePicker.frame.maxY, wizard.next.frame.minY)
        screenshot("Wizard motion 05 - date", in: app)

        let today = Calendar.current.component(.day, from: .now)
        let selectedDay = today == 15 ? 14 : 15
        wizard.selectDayInDisplayedMonth(selectedDay)
        let dateValue = wizard.selectedDate.value as? String
        XCTAssertNotNil(dateValue)
        wizard.advance(to: wizard.note)
        let detailsFooter = wizard.assertFooter(keyboardVisible: false, final: true)
        XCTAssertEqual(detailsFooter.maxY, dateFooter.maxY, accuracy: 3)
        wizard.tap(wizard.note)
        app.typeText("Keyboard stays open\nFooter stays reachable")
        let noteFooter = wizard.assertFooter(keyboardVisible: true, final: true)
        XCTAssertLessThan(noteFooter.maxY, detailsFooter.maxY - 100)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(wizard.note.frame))
        XCTAssertLessThanOrEqual(wizard.note.frame.maxY, wizard.save.frame.minY)
        screenshot("Wizard motion 06 - multiline note keyboard", in: app)
        for pass in 1...2 {
            wizard.goBack(to: wizard.datePicker)
            let returnedDateFooter = wizard.assertFooter(keyboardVisible: false)
            XCTAssertEqual(returnedDateFooter.maxY, dateFooter.maxY, accuracy: 3)
            XCTAssertEqual(wizard.selectedDate.value as? String, dateValue)
            XCTAssertTrue(app.windows.firstMatch.frame.contains(wizard.datePicker.frame))
            screenshot("Wizard motion roundtrip \(pass) - date restored", in: app)
            wizard.advance(to: wizard.note)
            XCTAssertEqual(wizard.note.value as? String, "Keyboard stays open\nFooter stays reachable")
            let returnedFooter = wizard.assertFooter(keyboardVisible: false, final: true)
            XCTAssertEqual(returnedFooter.maxY, detailsFooter.maxY, accuracy: 3)
            wizard.tap(wizard.note)
            app.typeText("!")
            wizard.assertFooter(keyboardVisible: true, final: true)
            screenshot("Wizard motion roundtrip \(pass) - keyboard reopened", in: app)
            app.typeText(XCUIKeyboardKey.delete.rawValue)
        }
        wizard.saveAndWaitForDismissal()
        wizard.tap(expenseRow("Keyboard footer roundtrip", in: app))
        XCTAssertTrue(wizard.name.waitForExistence(timeout: timeout))
        wizard.assertAmount(12.34, editing: true)
        wizard.reveal(wizard.note)
        XCTAssertEqual(wizard.note.value as? String, "Keyboard stays open\nFooter stays reachable")
        XCTAssertEqual(app.buttons["Date"].value as? String, dateValue)
    }

    private func launchExpenses() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SAGE_UI_TESTING"] = "1"
        app.launchEnvironment["SAGE_UI_TEST_ONBOARDING"] = "0"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        ExpenseWizardUITestSupport(app: app).tap(app.tabBars.buttons["Expenses"])
        return app
    }

    private func expenseRow(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["expense-row-\(name)"].firstMatch
    }

    private func assertFrequency(_ frequency: String, picker: XCUIElement) {
        XCTAssertTrue(picker.waitForExistence(timeout: timeout))
        XCTAssertTrue(picker.label.contains(frequency) || (picker.value as? String) == frequency,
                      "Frequency must expose its current selection: \(picker.debugDescription)")
    }

    private func screenshot(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
