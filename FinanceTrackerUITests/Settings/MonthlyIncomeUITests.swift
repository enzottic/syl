import XCTest

@MainActor
final class MonthlyIncomeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMonthlyIncomeIsAnEditableAccessibleTextField() {
        let app = XCUIApplication()
        app.launchEnvironment["SAGE_UI_TESTING"] = "1"
        app.launchEnvironment["SAGE_UI_TEST_ONBOARDING"] = "0"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        let budget = app.buttons["Budget and Allocation"]
        XCTAssertTrue(budget.waitForHittability(timeout: 10))
        budget.tap()

        // Query by the spoken label and native text-field role, not coordinates.
        let income = app.textFields["Monthly income"]
        XCTAssertTrue(income.waitForHittability(timeout: 10))
        XCTAssertEqual(income.identifier, "monthly-income-field")
        XCTAssertGreaterThan(income.frame.height, 0)
        XCTAssertGreaterThan(income.frame.width, 0)
        income.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))

        // Clear the prefilled amount, then verify whole-unit editing and the cap.
        income.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12))
        assertIncome(0, in: income)
        income.typeText("123456789")
        assertIncome(12_345_678, in: income)
        income.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8))
        assertIncome(0, in: income)
        income.typeText("6200")
        assertIncome(6_200, in: income)

        app.buttons["Done"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(budget.waitForHittability(timeout: 10))
        budget.tap()
        XCTAssertTrue(income.waitForHittability(timeout: 10))
        assertIncome(6_200, in: income)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Accessible monthly income field"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertIncome(_ amount: Int, in field: XCUIElement) {
        let expected = amount.formatted(
            .currency(code: "USD").locale(Locale(identifier: "en_US")).precision(.fractionLength(0))
        )
        XCTAssertEqual(field.value as? String, expected)
    }
}
