import XCTest

/// Drives only new/duplicate expense entry. Existing expenses still use the edit form.
@MainActor
struct ExpenseWizardUITestSupport {
    let app: XCUIApplication
    let timeout: TimeInterval = 20

    var name: XCUIElement { app.textFields["expense-name-field"] }
    var amount: XCUIElement { app.staticTexts["expense-amount-field"] }
    var note: XCUIElement { app.textFields["expense-note-field"] }
    var datePicker: XCUIElement { app.datePickers["expense-date-picker"] }
    var selectedDate: XCUIElement { app.descendants(matching: .any)["expense-selected-date"].firstMatch }
    var next: XCUIElement { app.buttons["expense-next-button"] }
    var back: XCUIElement { app.buttons["expense-back-button"] }
    var save: XCUIElement { app.buttons["save-expense-button"] }

    func open() {
        tap(app.descendants(matching: .any)["add-expense-button"].firstMatch)
        XCTAssertTrue(name.waitForExistence(timeout: timeout))
        XCTAssertTrue(next.waitForExistence(timeout: timeout))
        XCTAssertFalse(app.keyboards.firstMatch.exists, "New expense entry must not autofocus the name.")
        XCTAssertFalse(back.exists, "The first page must not expose Back.")
        XCTAssertFalse(save.exists, "Saving belongs only on the final date page.")
    }

    func enterName(_ text: String) {
        tap(name)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: timeout))
        // App-level typing does not silently restore lost focus.
        app.typeText(text)
        XCTAssertEqual(name.value as? String, text)
    }

    func advance(to destination: XCUIElement) {
        tap(next)
        XCTAssertTrue(destination.waitForExistence(timeout: timeout))
    }

    func goBack(to destination: XCUIElement) {
        tap(back)
        XCTAssertTrue(destination.waitForExistence(timeout: timeout))
    }

    func enterAmountDigits(_ digits: String) {
        XCTAssertTrue(amount.waitForExistence(timeout: timeout))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: timeout))
        for digit in digits {
            tap(app.buttons[String(digit)])
        }
    }

    func advanceFromAmountToDate() {
        advance(to: app.buttons["expense-category-needs"])
        advance(to: note)
        advance(to: datePicker)
        XCTAssertTrue(save.waitForExistence(timeout: timeout))
        XCTAssertFalse(next.exists)
    }

    func saveAndWaitForDismissal() {
        XCTAssertTrue(datePicker.waitForExistence(timeout: timeout))
        tap(save)
        // The name field is already absent on the date page; it cannot prove dismissal.
        XCTAssertTrue(save.waitForNonExistence(timeout: timeout))
        XCTAssertTrue(datePicker.waitForNonExistence(timeout: timeout))
        XCTAssertTrue(app.tabBars.buttons["Expenses"].wait(for: \.isHittable, toEqual: true, timeout: timeout))
    }

    func assertAmount(_ value: Double, editing: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        let field = editing ? app.textFields["expense-amount-field"] : amount
        XCTAssertTrue(field.waitForExistence(timeout: timeout), file: file, line: line)
        let expected = value.formatted(.currency(code: "USD"))
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
                       "Expected localized amount \(expected), got \(String(describing: field.value)).", file: file, line: line)
        XCTAssertEqual(field.label, "Amount", "The amount must retain its accessible label.", file: file, line: line)
    }

    /// No scrolling or recovery taps here: those can hide keyboard/detent animation regressions.
    @discardableResult
    func assertFooter(keyboardVisible: Bool, final: Bool = false, hasBack: Bool = true,
                      file: StaticString = #filePath, line: UInt = #line) -> CGRect {
        let primary = final ? save : next
        let keyboard = app.keyboards.firstMatch
        if keyboardVisible {
            XCTAssertTrue(keyboard.waitForExistence(timeout: timeout), file: file, line: line)
        } else {
            XCTAssertTrue(keyboard.waitForNonExistence(timeout: timeout), file: file, line: line)
        }
        let predicate = NSPredicate { _, _ in
            let screen = app.windows.firstMatch.frame
            let frame = primary.frame
            guard primary.exists, primary.isHittable, !frame.isEmpty,
                  frame.height >= 44, screen.contains(frame) else { return false }
            if hasBack {
                guard back.exists, back.isHittable, back.frame.height >= 44,
                      screen.contains(back.frame), abs(back.frame.midY - frame.midY) <= 2,
                      back.frame.maxX <= frame.minX else { return false }
            }
            if keyboardVisible {
                let keyboardFrame = keyboard.frame
                return !keyboardFrame.isEmpty && keyboardFrame.minY < screen.maxY
                    && frame.maxY <= keyboardFrame.minY + 1
                    && keyboardFrame.minY - frame.maxY <= 100
            }
            return screen.maxY - frame.maxY <= 100
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
                       "The footer must remain fully visible, aligned, and above the keyboard.\n\(app.debugDescription)",
                       file: file, line: line)
        return primary.frame
    }

    func selectDayInDisplayedMonth(_ day: Int, monthOffset: Int = 0) {
        XCTAssertTrue(datePicker.waitForExistence(timeout: timeout))
        // Native calendar labels include a localized full date on some iOS releases.
        // Restrict to date-picker buttons and match a whole day number, never a year.
        let dayButton = datePicker.buttons.matching(
            NSPredicate(format: "label MATCHES %@", "(^|.*[^0-9])\(day)([^0-9].*|$)")
        ).firstMatch
        tap(dayButton)
        let month = Calendar.current.date(byAdding: .month, value: monthOffset, to: .now)!
        var components = Calendar.current.dateComponents([.year, .month], from: month)
        components.day = day
        let expectedDate = Calendar.current.date(from: components)!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", formatter.string(from: expectedDate)),
            object: selectedDate
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
                       "The native calendar must select the requested date, not just accept a tap.")
    }

    func browseCalendarMonth(forward: Bool) {
        tap(datePicker.buttons.matching(
            NSPredicate(format: "label ==[c] %@", forward ? "Next Month" : "Previous Month")
        ).firstMatch)
    }

    func reveal(_ element: XCUIElement) {
        for _ in 0..<10 {
            if element.exists && element.isHittable && app.windows.firstMatch.frame.contains(element.frame) { return }
            app.swipeUp()
        }
        XCTFail("Control is not reachable: \(element)\n\(app.debugDescription)")
    }

    func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        XCTAssertTrue(element.wait(for: \.isHittable, toEqual: true, timeout: timeout))
        element.tap()
    }
}
