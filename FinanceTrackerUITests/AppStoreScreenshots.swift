import XCTest

/// Drives the Debug build (which seeds mock data) through the screens used for App Store screenshots.
/// Run with `fastlane screenshots`; fastlane/screenshot_template.json decides how captures are composed.
@MainActor
final class AppStoreScreenshots: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        setupSnapshot(app)
        // iPad pages show a horizontal iPad, so capture in landscape.
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    }

    func testCaptureAppScreens() {
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["main-tab-view"].waitForExistence(timeout: 15))

        snapshot("01-Home")

        app.swipeUp(velocity: .fast)
        app.swipeUp(velocity: .fast)
        snapshot("04-HomeBottom")

        selectTab("Expenses")
        snapshot("05-Expenses")

        selectTab("Stats")
        XCTAssertTrue(app.descendants(matching: .any)["stats-scroll-view"].waitForExistence(timeout: 5))
        snapshot("03-Stats")

        selectTab("Settings")
        let tagsRow = app.staticTexts["Tags"].firstMatch
        XCTAssertTrue(tagsRow.waitForExistence(timeout: 5))
        tagsRow.tap()
        XCTAssertTrue(app.navigationBars["Tags"].waitForExistence(timeout: 5))
        snapshot("06-Tags")

        selectTab("Home")
        app.buttons["add-expense-button"].firstMatch.tap()
        let nameField = app.textFields["expense-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Farmers market")
        app.buttons["expense-next-button"].tap()

        XCTAssertTrue(app.buttons["2"].firstMatch.waitForExistence(timeout: 5))
        for digit in ["2", "4", "5", "0"] {
            app.buttons[digit].firstMatch.tap()
        }
        snapshot("07-AddExpense")
    }

    func testCaptureOnboardingBudget() {
        // The argument domain outranks the seeder's stored value, forcing onboarding for this launch.
        app.launchArguments += ["-hasOpenedAppOnce", "NO"]
        app.launch()

        let getStarted = app.buttons["onboarding-get-started-button"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 15))
        getStarted.tap()

        let incomeField = app.textFields["onboarding-income-field"]
        XCTAssertTrue(incomeField.waitForExistence(timeout: 5))
        incomeField.tap()
        incomeField.typeText("5000")
        let keyboardDone = app.buttons["onboarding-keyboard-done-button"]
        if keyboardDone.exists { keyboardDone.tap() }

        app.buttons["onboarding-budget-continue-button"].tap()
        XCTAssertTrue(app.buttons["onboarding-allocation-continue-button"].waitForExistence(timeout: 5))
        snapshot("02-Budget")
    }

    /// Tabs are tab bar buttons on iPhone and sidebar rows on a landscape iPad.
    private func selectTab(_ name: String) {
        let candidates = [app.tabBars.buttons[name], app.buttons[name].firstMatch, app.cells.staticTexts[name].firstMatch]
        let deadline = Date.now.addingTimeInterval(5)
        while Date.now < deadline {
            if let tab = candidates.first(where: \.isHittable) {
                tab.tap()
                return
            }
            RunLoop.current.run(until: .now.addingTimeInterval(0.25))
        }
        XCTFail("Missing tab \(name)")
    }
}
