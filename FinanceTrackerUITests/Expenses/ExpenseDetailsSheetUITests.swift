import XCTest

@MainActor
final class ExpenseDetailsSheetUITests: XCTestCase {
    func testCalendarKeepsFooterVisibleAndPreservesSelectedDate() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SAGE_UI_TESTING"] = "1"
        app.launchEnvironment["SAGE_UI_TEST_ONBOARDING"] = "0"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let wizard = ExpenseWizardUITestSupport(app: app)
        wizard.tap(app.tabBars.buttons["Expenses"])
        wizard.open()
        wizard.enterName("Calendar layout")
        wizard.advance(to: wizard.amount)
        wizard.enterAmountDigits("500")
        wizard.advance(to: app.buttons["expense-category-needs"])
        wizard.advance(to: wizard.datePicker)
        let footer = wizard.assertFooter(keyboardVisible: false)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(wizard.datePicker.frame))
        XCTAssertLessThanOrEqual(wizard.datePicker.frame.maxY, wizard.next.frame.minY)

        let originalDate = wizard.selectedDate.value as? String
        XCTAssertNotNil(originalDate)
        let calendarFrame = wizard.datePicker.frame
        wizard.browseCalendarMonth(forward: true)
        XCTAssertEqual(wizard.selectedDate.value as? String, originalDate,
                       "Browsing months must not change the expense date.")
        XCTAssertEqual(wizard.assertFooter(keyboardVisible: false).maxY, footer.maxY, accuracy: 3)
        XCTAssertEqual(wizard.datePicker.frame.minY, calendarFrame.minY, accuracy: 3)
        wizard.selectDayInDisplayedMonth(15, monthOffset: 1)
        XCTAssertNotEqual(wizard.selectedDate.value as? String, originalDate)
        XCTAssertEqual(wizard.assertFooter(keyboardVisible: false).maxY, footer.maxY, accuracy: 3)
        wizard.browseCalendarMonth(forward: false)
        let today = Calendar.current.component(.day, from: .now)
        wizard.selectDayInDisplayedMonth(today == 15 ? 14 : 15)
        let changedDate = wizard.selectedDate.value as? String
        XCTAssertNotNil(changedDate)
        XCTAssertNotEqual(changedDate, originalDate)
        for pass in 1...2 {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Calendar - roundtrip \(pass)"
            attachment.lifetime = .keepAlways
            add(attachment)
            wizard.goBack(to: app.buttons["expense-category-needs"])
            XCTAssertEqual(wizard.assertFooter(keyboardVisible: false).maxY, footer.maxY, accuracy: 3)
            wizard.advance(to: wizard.datePicker)
            XCTAssertEqual(wizard.selectedDate.value as? String, changedDate)
            XCTAssertEqual(wizard.assertFooter(keyboardVisible: false).maxY, footer.maxY, accuracy: 3)
        }
        wizard.selectDayInDisplayedMonth(today)
        XCTAssertEqual(wizard.selectedDate.value as? String, originalDate)
        // Selecting the same native calendar day leaves the next action usable.
        wizard.selectDayInDisplayedMonth(today)
        XCTAssertEqual(wizard.selectedDate.value as? String, originalDate)
        wizard.assertFooter(keyboardVisible: false)
        wizard.advance(to: wizard.note)
        wizard.saveAndWaitForDismissal()
        wizard.tap(app.descendants(matching: .any)["expense-row-Calendar layout"].firstMatch)
        XCTAssertTrue(wizard.name.waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons["Date"].value as? String, originalDate)
        wizard.assertAmount(5, editing: true)
    }
}
