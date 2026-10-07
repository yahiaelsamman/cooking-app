import XCTest

/// End-to-end cooking journeys: start from a recipe, step through, timers, checklist, servings
/// carrying into cooking, hold-to-finish, resume after relaunch, rating, and large-text/dark
/// appearance sweeps. Each key screen is attached as a screenshot (`journey-*`).
final class CookingJourneyUITests: XCTestCase {
    var app: XCUIApplication!

    private func launch(extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-cookName", "Tester",
                               "-hasSeenStepTour", "YES", "-hasSeenTimerTourTip", "YES",
                               "-hasSeenFinishTourTip", "YES", "-hasSeenRecipeDetailTour", "YES",
                               "-hasSeenRecipeListTour", "YES"] + extra
        app.launch()
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "journey-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func scrollUntilVisible(_ element: XCUIElement, maxSwipes: Int = 20) {
        var attempts = 0
        while (!element.exists || !element.isHittable) && attempts < maxSwipes {
            app.swipeUp()
            attempts += 1
        }
    }

    private func openRecipe(_ title: String) {
        let row = app.buttons["recipeRow_\(title)"]
        _ = row.waitForExistence(timeout: 5)
        scrollUntilVisible(row)
        XCTAssertTrue(row.isHittable, "row \(title) not reachable")
        row.tap()
        XCTAssertTrue(app.buttons["Start Cooking"].waitForExistence(timeout: 5))
    }

    private var stepElement: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Step '")).firstMatch
    }

    private func assertStep(_ n: Int, of total: Int = 9, file: StaticString = #filePath, line: UInt = #line) {
        let el = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Step \(n) of \(total)")).firstMatch
        let lastEl = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Step \(n) of \(total)")).firstMatch
        XCTAssertTrue(el.waitForExistence(timeout: 4) || lastEl.exists, "expected Step \(n) of \(total)", file: file, line: line)
    }

    private func advance() {
        let s = stepElement
        XCTAssertTrue(s.waitForExistence(timeout: 4))
        s.tap()
    }

    private func holdToFinish() {
        let finish = app.descendants(matching: .any)["Finish Recipe"].firstMatch
        XCTAssertTrue(finish.waitForExistence(timeout: 4), "Finish Recipe control missing on last step")
        finish.press(forDuration: 1.6)
    }

    func testFullCookingJourneyWithTimerChecklistServingsAndFinish() throws {
        launch()
        openRecipe("Pan-Seared Steak with Garlic Butter")
        shot("01-detail")

        // Servings 1 -> 2 should carry into the cooking checklist (steak amount "1" -> "2").
        app.buttons["increaseServingsButton"].tap()
        XCTAssertEqual(app.staticTexts["ingredientAmount_Ribeye or NY strip steak"].label, "2")

        app.buttons["Start Cooking"].tap()
        assertStep(1)
        shot("02-step1-timer-step")

        // Timer: start, watch it count, cancel.
        let start = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Start '")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 4), "step 1 has a timer button")
        start.tap()
        let cancel = app.buttons["Cancel timer"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 4))
        let v1 = cancel.value as? String ?? ""
        sleep(3)
        let v2 = cancel.value as? String ?? ""
        XCTAssertNotEqual(v1, v2, "timer should count down (\(v1) vs \(v2))")
        shot("03-timer-running")

        // Timer keeps running on another step and shows as a chip.
        advance()
        assertStep(2)
        shot("04-step2-with-timer-chip")

        // Back returns to step 1 with the timer still running.
        app.buttons["Previous step"].tap()
        assertStep(1)
        XCTAssertTrue(app.buttons["Cancel timer"].waitForExistence(timeout: 3), "timer survived step navigation")
        app.buttons["Cancel timer"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Start '")).firstMatch.waitForExistence(timeout: 3))

        // Checklist with the scaled amount.
        app.buttons["ingredientChecklistButton"].tap()
        let row = app.buttons["ingredientChecklistRow_Ribeye or NY strip steak"]
        XCTAssertTrue(row.waitForExistence(timeout: 4))
        XCTAssertTrue(row.label.contains("2"), "scaled servings should carry into checklist: \(row.label)")
        row.tap()
        shot("05-checklist-ticked")
        XCTAssertTrue(app.buttons["ingredientChecklistRow_Ribeye or NY strip steak"].isSelected)
        app.buttons["Done"].tap()

        // Checklist state persists when reopened.
        app.buttons["ingredientChecklistButton"].tap()
        XCTAssertTrue(app.buttons["ingredientChecklistRow_Ribeye or NY strip steak"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["ingredientChecklistRow_Ribeye or NY strip steak"].isSelected)
        app.buttons["Done"].tap()

        // Walk to the last step.
        for n in 2...9 {
            advance()
            assertStep(n)
        }
        shot("06-last-step")
        holdToFinish()
        XCTAssertTrue(app.staticTexts["Recipe Complete"].waitForExistence(timeout: 5))
        shot("07-complete")

        // Go Back from completion returns to the last step.
        app.buttons["Go Back"].tap()
        assertStep(9)
        holdToFinish()
        XCTAssertTrue(app.staticTexts["Recipe Complete"].waitForExistence(timeout: 5))
        app.buttons["Back to Recipes"].tap()
        XCTAssertTrue(app.navigationBars["Recipes"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Resume cooking Pan-Seared Steak with Garlic Butter"].exists)
    }

    func testResumeMidCookAfterRelaunch() throws {
        launch()
        openRecipe("Pan-Seared Steak with Garlic Butter")
        app.buttons["Start Cooking"].tap()
        assertStep(1)
        advance(); advance(); advance()
        assertStep(4)
        app.terminate()

        launch(extra: ["-UITestKeepSession"])
        let resume = app.buttons["Resume cooking Pan-Seared Steak with Garlic Butter"]
        XCTAssertTrue(resume.waitForExistence(timeout: 6), "resume button should appear after relaunch")
        shot("08-list-with-resume")
        resume.tap()
        assertStep(4)
        shot("09-resumed-step4")
    }

    func testRatingFromDetail() throws {
        launch()
        openRecipe("Classic Scrambled Eggs")
        let rating = app.descendants(matching: .any)["Rating"].firstMatch
        scrollUntilVisible(rating)
        XCTAssertTrue(rating.exists)
        shot("10-rating-before")
        let star4 = app.buttons["4 stars"]
        if star4.waitForExistence(timeout: 2) {
            star4.tap()
        } else {
            rating.adjust(toNormalizedSliderPosition: 0.8)
        }
        shot("11-rating-after")
    }

    func testFavoritesFilterShowsOnlyFavorites() throws {
        launch()
        let row = app.buttons["recipeRow_Homemade Pizza"]
        scrollUntilVisible(row)
        row.swipeRight()
        app.buttons["swipeFavoriteButton_Homemade Pizza"].tap()
        app.buttons["favoritesFilterButton"].tap()
        XCTAssertTrue(app.buttons["recipeRow_Homemade Pizza"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["recipeRow_Classic Scrambled Eggs"].exists)
        shot("12-favorites-only")
    }

    // MARK: appearance sweeps

    private func sweep(_ prefix: String) {
        XCTAssertTrue(app.navigationBars["Recipes"].waitForExistence(timeout: 6))
        shot("\(prefix)-list")
        openRecipe("Pan-Seared Steak with Garlic Butter")
        shot("\(prefix)-detail")
        app.swipeUp(); shot("\(prefix)-detail-scrolled")
        app.swipeDown(); app.swipeDown()
        let start = app.buttons["Start Cooking"]
        scrollUntilVisible(start)
        start.tap()
        _ = stepElement.waitForExistence(timeout: 5)
        shot("\(prefix)-step1")
        let timerBtn = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Start '")).firstMatch
        if timerBtn.exists { timerBtn.tap() }
        advance()
        shot("\(prefix)-step2-chip")
        app.buttons["ingredientChecklistButton"].tap()
        sleep(1)
        shot("\(prefix)-checklist")
        app.buttons["Done"].tap()
        for _ in 2...8 { advance() }
        shot("\(prefix)-last-step")
        holdToFinish()
        _ = app.staticTexts["Recipe Complete"].waitForExistence(timeout: 5)
        shot("\(prefix)-complete")
    }

    func testDarkModeSweep() throws {
        launch(extra: ["-AppleInterfaceStyle", "Dark"])
        sweep("dark")
    }

    func testLargestDynamicTypeSweep() throws {
        launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        sweep("ax5")
    }

    func testDarkLargeTypeShoppingList() throws {
        launch(extra: ["-AppleInterfaceStyle", "Dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openRecipe("Classic Scrambled Eggs")
        app.buttons["addToShoppingListButton"].tap()
        app.navigationBars.buttons["Recipes"].tap()
        app.buttons["shoppingListButton"].tap()
        XCTAssertTrue(app.buttons["shoppingListItem_Large eggs"].waitForExistence(timeout: 5))
        shot("darkax5-shopping")
    }
}
