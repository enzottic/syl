import XCTest

@MainActor
final class ExpenseDetailsSheetUITests: XCTestCase {
    func testCalendarExpandsUpwardAndKeepsFooterVisible() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SAGE_UI_TESTING"] = "1"
        app.launchEnvironment["SAGE_UI_TEST_ONBOARDING"] = "0"
        app.launch()

        let add = app.buttons["add-expense-button"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 20))
        add.tap()
        let name = app.textFields["Expense name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Calendar layout")
        app.buttons["Next"].tap()
        XCTAssertTrue(app.buttons["5"].waitForExistence(timeout: 10))
        app.buttons["5"].tap()
        app.buttons["Next"].tap()
        app.buttons["Next"].tap()

        let date = app.buttons["Date"]
        let done = app.buttons["Done"]
        let back = app.buttons["Back"]
        let tags = app.staticTexts["Tags"]
        XCTAssertTrue(date.waitForExistence(timeout: 10))
        let collapsedDateY = date.frame.minY
        let footerY = done.frame.maxY
        let tagsY = tags.frame.minY

        let originalDateValue = date.value as? String
        for _ in 0..<2 {
            date.tap()
            XCTAssertTrue(app.buttons["expense-date-calendar-next-month"].waitForExistence(timeout: 5))
            XCTAssertLessThan(date.frame.minY, collapsedDateY - 100)
            XCTAssertEqual(done.frame.maxY, footerY, accuracy: 2)
            XCTAssertEqual(tags.frame.minY, tagsY, accuracy: 2)
            XCTAssertTrue(app.windows.firstMatch.frame.contains(done.frame))
            XCTAssertTrue(done.isHittable)
            XCTAssertTrue(back.isHittable)
            let month = app.descendants(matching: .any).matching(identifier: "expense-date-calendar-month").firstMatch
            let originalMonth = month.value as? String
            let expandedDateY = date.frame.minY
            app.buttons["expense-date-calendar-next-month"].tap()
            XCTAssertNotEqual(month.value as? String, originalMonth)
            XCTAssertEqual(done.frame.maxY, footerY, accuracy: 2)
            XCTAssertEqual(date.frame.minY, expandedDateY, accuracy: 2)
            app.buttons["expense-date-calendar-previous-month"].tap()
            XCTAssertEqual(month.value as? String, originalMonth)
            date.tap()
            XCTAssertTrue(app.buttons["expense-date-calendar-next-month"].waitForNonExistence(timeout: 5))
            XCTAssertEqual(date.frame.minY, collapsedDateY, accuracy: 2)
            XCTAssertEqual(done.frame.maxY, footerY, accuracy: 2)
        }
        date.tap()
        app.buttons["expense-date-calendar-next-month"].tap()
        app.buttons["expense-date-calendar-day-15"].tap()
        XCTAssertTrue(app.buttons["expense-date-calendar-next-month"].waitForNonExistence(timeout: 5))
        XCTAssertNotEqual(date.value as? String, originalDateValue)
        XCTAssertEqual(done.frame.maxY, footerY, accuracy: 2)
        date.tap()
        app.buttons["expense-date-calendar-today"].tap()
        XCTAssertTrue(app.buttons["expense-date-calendar-next-month"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(date.value as? String, originalDateValue)
        // Selecting the already-selected day must close the calendar too.
        date.tap()
        app.buttons["expense-date-calendar-today"].tap()
        XCTAssertTrue(app.buttons["expense-date-calendar-next-month"].waitForNonExistence(timeout: 5))
    }
}
