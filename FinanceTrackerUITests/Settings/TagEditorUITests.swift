import XCTest

@MainActor
final class TagEditorUITests: XCTestCase {
    private let timeout: TimeInterval = 20

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTagControlsAndSavedSelection() {
        let app = openTagEditor(dark: false)

        let glyph = app.buttons["Choose tag icon"]
        XCTAssertTrue(glyph.waitForExistence(timeout: timeout))
        XCTAssertFalse((glyph.value as? String ?? "").isEmpty)
        XCTAssertGreaterThanOrEqual(glyph.frame.width, 44)
        XCTAssertGreaterThanOrEqual(glyph.frame.height, 44)
        screenshot("Tag editor - medium sheet", in: app)
        // Sample opposite ends of the shared palette instead of every color.
        app.swipeUp()
        let colors = ["Red", "Pink"]
        var previous: XCUIElement?
        for name in colors {
            let swatch = app.buttons["\(name) color"]
            reveal(swatch, in: app)
            XCTAssertGreaterThanOrEqual(swatch.frame.width, 44)
            XCTAssertGreaterThanOrEqual(swatch.frame.height, 44)
            // The corner is outside the visible 28-point circle, but inside its target.
            swatch.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.05)).tap()
            XCTAssertTrue(swatch.isSelected, "\(name) must expose selection after an edge tap.")
            if let previous { XCTAssertFalse(previous.isSelected) }
            previous = swatch
        }
        screenshot("Tag editor - named palette selected", in: app)

        // Return to the top if larger text required scrolling through the palette.
        app.scrollViews.firstMatch.swipeDown()
        tap(glyph)
        XCTAssertTrue(app.navigationBars["Tag Icon"].waitForExistence(timeout: timeout))
        tap(app.segmentedControls.buttons["Icon"])
        tap(app.buttons["creditcard fill"])
        XCTAssertEqual(glyph.value as? String, "creditcard fill")

        let nameField = app.textFields["Tag Name"]
        tap(nameField)
        nameField.typeText("Accessible Tag")
        tap(app.buttons["Add Tag"])
        let savedTag = app.buttons.containing(.staticText, identifier: "Accessible Tag").firstMatch
        reveal(savedTag, in: app)
        tap(savedTag)
        XCTAssertTrue(app.buttons["Pink color"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.buttons["Pink color"].isSelected, "Stored UIColor must match the original preset.")
        XCTAssertEqual(glyph.value as? String, "creditcard fill")
        screenshot("Tag editor - reopened saved selection", in: app)
        tap(app.buttons["cancel-tag-button"])
        XCTAssertTrue(glyph.waitForNonExistence(timeout: timeout), "An unchanged reopened tag should dismiss without confirmation.")
    }

    func testTagControlsInDarkModeWithLargeText() {
        let app = openTagEditor(dark: true)
        let glyph = app.buttons["Choose tag icon"]
        XCTAssertTrue(glyph.waitForExistence(timeout: timeout))
        XCTAssertTrue(glyph.isHittable)
        XCTAssertGreaterThanOrEqual(glyph.frame.width, 44)
        XCTAssertGreaterThanOrEqual(glyph.frame.height, 44)
        app.swipeUp()

        for name in ["Red", "Pink"] {
            let swatch = app.buttons["\(name) color"]
            reveal(swatch, in: app)
            XCTAssertGreaterThanOrEqual(swatch.frame.width, 44)
            XCTAssertGreaterThanOrEqual(swatch.frame.height, 44)
        }
        reveal(app.descendants(matching: .any)["Custom color"].firstMatch, in: app)
        let cancel = app.buttons["cancel-tag-button"]
        let save = app.buttons["Add Tag"]
        XCTAssertTrue(cancel.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(save.frame))
        XCTAssertFalse(save.isEnabled)
        screenshot("Tag editor - dark large text controls", in: app)
        tap(cancel)
        XCTAssertTrue(glyph.waitForNonExistence(timeout: timeout))
    }

    func testCustomColorPickerOpensAndDismisses() {
        let app = openTagEditor(dark: false)
        app.swipeUp()
        for name in ["Red", "Pink"] {
            let swatch = app.buttons["\(name) color"]
            reveal(swatch, in: app)
            tap(swatch)
        }
        let custom = app.buttons["Custom color"]
        reveal(custom, in: app)
        custom.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let close = app.buttons.matching(
            NSPredicate(format: "label ==[c] %@ OR label == %@", "close", "Done")
        ).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: timeout),
                      "The native color picker did not open after tapping its visible color well.\n\(app.debugDescription)")
        screenshot("Tag editor - native custom color picker", in: app)
        tap(close)
        XCTAssertTrue(app.buttons["Choose tag icon"].wait(for: \.isHittable, toEqual: true, timeout: timeout))
    }

    func testLongTagFitsPickerAndCanBeSelected() {
        verifyLongTagPicker(dark: false)
    }

    func testLongTagFitsPickerWithAccessibilityText() {
        verifyLongTagPicker(dark: true)
    }

    private func verifyLongTagPicker(dark: Bool) {
        let app = openTagEditor(dark: dark)
        let name = "Weekend groceries and household supplies for the whole family"
        let nameField = app.textFields["Tag Name"]
        tap(nameField)
        nameField.typeText(name)
        tap(app.buttons["Add Tag"])
        XCTAssertTrue(nameField.waitForNonExistence(timeout: timeout))
        tap(app.navigationBars.buttons.firstMatch)
        tap(app.tabBars.buttons["Expenses"])
        let wizard = ExpenseWizardUITestSupport(app: app)
        wizard.open()
        wizard.enterName("Long tag layout")
        wizard.advance(to: wizard.amount)
        wizard.enterAmountDigits("100")
        wizard.advance(to: app.buttons["expense-category-needs"])
        wizard.advance(to: wizard.datePicker)
        wizard.advance(to: wizard.note)

        let chip = app.buttons["Tag: \(name)"]
        reveal(chip, in: app)
        let screen = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(chip.frame.minX, screen.minX)
        XCTAssertLessThanOrEqual(chip.frame.maxX, screen.maxX)
        XCTAssertGreaterThan(chip.frame.height, dark ? 80 : 40, "The long tag should wrap, not truncate.")
        let addTag = app.buttons.containing(.staticText, identifier: "Add new tag").firstMatch
        reveal(addTag, in: app)
        XCTAssertGreaterThanOrEqual(addTag.frame.minY, chip.frame.maxY)
        screenshot(dark ? "Long tag - dark accessibility XL" : "Long tag - light default text", in: app)

        reveal(chip, in: app)
        tap(chip)
        XCTAssertEqual(chip.value as? String, "Selected")
        tap(chip)
        XCTAssertEqual(chip.value as? String, "Not selected")
        wizard.goBack(to: wizard.datePicker)
        wizard.goBack(to: app.buttons["expense-category-needs"])
        wizard.goBack(to: wizard.amount)
        wizard.goBack(to: wizard.name)
        wizard.dismissBySwipe()
        XCTAssertTrue(wizard.note.waitForNonExistence(timeout: timeout))
        XCTAssertTrue(app.tabBars.buttons["Expenses"].isHittable)
    }

    private func openTagEditor(dark: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SAGE_UI_TESTING"] = "1"
        app.launchEnvironment["SAGE_UI_TEST_ONBOARDING"] = "0"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if dark {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        }
        app.launch()
        tap(app.tabBars.buttons["Settings"])
        tap(app.buttons["Appearance"])
        tap(app.buttons.containing(.staticText, identifier: dark ? "Dark" : "Light").firstMatch)
        tap(app.navigationBars.buttons.firstMatch)
        let tags = app.buttons["Tags"]
        reveal(tags, in: app)
        tap(tags)
        tap(app.buttons["Add new tag"])
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable && app.windows.firstMatch.frame.contains(element.frame) { return }
            app.swipeUp()
        }
        XCTFail("Control is not reachable: \(element)\n\(app.debugDescription)")
    }

    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        XCTAssertTrue(element.waitForHittability(timeout: timeout))
        element.tap()
    }

    private func screenshot(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
