import XCTest

/// Real touch-driven UI coverage — the thing every earlier pass's "verified via screenshot" notes
/// in instructions.md explicitly couldn't do, since this sandbox had no accessibility automation
/// and no XCUITest target until now. Launches with `-UITesting`, which the app checks for in two
/// places: `CookingAppApp` uses an in-memory SwiftData store instead of the real on-device one (so
/// every run starts from exactly the 20 bundled recipes, isolated from a real user's data), and
/// `RecipeListView` skips requesting the system notification permission (that dialog can't be
/// reliably dismissed from XCUITest).
final class CookingAppUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        dismissWelcomeNameIfNeeded()
    }

    /// The welcome-name sheet only appears when `@AppStorage("cookName")` is empty — that's real
    /// UserDefaults, not reset by the in-memory-store flag, so a simulator that's run the app
    /// non-UI-test before might already have a name saved. Handled conditionally rather than
    /// assumed, so this suite doesn't depend on the simulator's prior state.
    private func dismissWelcomeNameIfNeeded() {
        let nameField = app.textFields["welcomeNameField"]
        if nameField.waitForExistence(timeout: 3) {
            nameField.tap()
            nameField.typeText("Tester")
            app.buttons["Continue"].tap()
        }
    }

    /// SwiftUI's `List` only realizes rows near the visible area — swipes up until the target
    /// element actually exists in the accessibility hierarchy, or gives up after `maxSwipes`.
    private func scrollUntilVisible(_ element: XCUIElement, maxSwipes: Int = 12) {
        var attempts = 0
        while !element.exists && attempts < maxSwipes {
            app.swipeUp()
            attempts += 1
        }
    }

    func testRecipeListShowsBundledRecipesAndOpensDetail() throws {
        XCTAssertTrue(app.navigationBars["Recipes"].waitForExistence(timeout: 5))

        let firstRow = app.buttons["recipeRow_Classic Scrambled Eggs"]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.tap()

        XCTAssertTrue(app.buttons["Start Cooking"].waitForExistence(timeout: 5))
    }

    func testFavoritingFromDetailTogglesImmediately() throws {
        let firstRow = app.buttons["recipeRow_Classic Scrambled Eggs"]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.tap()

        let favoriteButton = app.buttons["detailFavoriteButton"]
        XCTAssertTrue(favoriteButton.waitForExistence(timeout: 5))
        XCTAssertEqual(favoriteButton.label, "Add to favorites")

        favoriteButton.tap()
        XCTAssertEqual(favoriteButton.label, "Remove from favorites")

        favoriteButton.tap()
        XCTAssertEqual(favoriteButton.label, "Add to favorites")
    }

    func testSwipeToFavoriteFromListPersistsToDetail() throws {
        let row = app.buttons["recipeRow_Homemade Pizza"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeRight()

        let swipeFavoriteButton = app.buttons["swipeFavoriteButton_Homemade Pizza"]
        XCTAssertTrue(swipeFavoriteButton.waitForExistence(timeout: 3))
        swipeFavoriteButton.tap()

        row.tap()
        let favoriteButton = app.buttons["detailFavoriteButton"]
        XCTAssertTrue(favoriteButton.waitForExistence(timeout: 5))
        XCTAssertEqual(favoriteButton.label, "Remove from favorites", "swipe-to-favorite from the list didn't persist")
    }

    func testAddRecipeFlowCreatesAndShowsNewRecipe() throws {
        app.buttons["addRecipeButton"].tap()

        let titleField = app.textFields["editorTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("Test Omelette")

        app.textFields["editorSummaryField"].tap()
        app.typeText("A quick test recipe.")

        app.textFields["editorCookTimeField"].tap()
        app.typeText("5")

        let ingredientNameField = app.textFields.matching(identifier: "ingredientNameField").element(boundBy: 0)
        ingredientNameField.tap()
        ingredientNameField.typeText("Eggs")

        let ingredientAmountField = app.textFields.matching(identifier: "ingredientAmountField").element(boundBy: 0)
        ingredientAmountField.tap()
        ingredientAmountField.typeText("2")

        let stepField = app.textFields.matching(identifier: "stepInstructionField").element(boundBy: 0)
        stepField.tap()
        stepField.typeText("Whisk and cook.")

        let saveButton = app.buttons["saveRecipeButton"]
        XCTAssertTrue(saveButton.isEnabled, "Save should be enabled once every required field is filled")
        saveButton.tap()

        let newRow = app.buttons["recipeRow_Test Omelette"]
        scrollUntilVisible(newRow)
        XCTAssertTrue(newRow.exists, "the newly-created recipe should appear in the list (it sorts last in My Order)")

        newRow.tap()
        XCTAssertTrue(app.buttons["editRecipeButton"].waitForExistence(timeout: 5), "a user-created recipe should show an Edit button")
    }
}
