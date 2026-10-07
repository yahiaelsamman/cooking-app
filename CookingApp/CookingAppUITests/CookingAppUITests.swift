import XCTest

/// Real touch-driven UI coverage. Launches with `-UITesting`, which the app checks for in two
/// places: `CookingAppApp` uses an in-memory SwiftData store instead of the real on-device one (so
/// every run starts from exactly the 20 bundled recipes, isolated from a real user's data), and
/// `RecipeDetailView` skips requesting the system notification permission on Start Cooking (that
/// dialog can't be reliably dismissed from XCUITest).
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
            // The keyboard's Return key is also labelled "Continue", so match by identifier.
            app.buttons["welcomeContinueButton"].tap()
        }
    }

    /// SwiftUI's `List` only realizes rows near the visible area — swipes up until the target
    /// element actually exists in the accessibility hierarchy, or gives up after `maxSwipes`.
    private func scrollUntilVisible(_ element: XCUIElement, maxSwipes: Int = 12) {
        var attempts = 0
        while (!element.exists || !element.isHittable) && attempts < maxSwipes {
            app.swipeUp()
            attempts += 1
        }
    }

    /// The list defaults to A-Z and its rows are tall, so most recipes aren't realized until
    /// scrolled into view. Returns the row once it exists.
    private func recipeRow(_ title: String) -> XCUIElement {
        let row = app.buttons["recipeRow_\(title)"]
        _ = row.waitForExistence(timeout: 3)
        scrollUntilVisible(row, maxSwipes: 20)
        return row
    }

    func testRecipeListShowsBundledRecipesAndOpensDetail() throws {
        XCTAssertTrue(app.navigationBars["Recipes"].waitForExistence(timeout: 5))

        let firstRow = recipeRow("Classic Scrambled Eggs")
        XCTAssertTrue(firstRow.isHittable)
        firstRow.tap()

        XCTAssertTrue(app.buttons["Start Cooking"].waitForExistence(timeout: 5))
    }

    func testFavoritingFromDetailTogglesImmediately() throws {
        let firstRow = recipeRow("Classic Scrambled Eggs")
        XCTAssertTrue(firstRow.isHittable)
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
        let row = recipeRow("Homemade Pizza")
        XCTAssertTrue(row.isHittable)
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

        // The editor is a long Form: lazily realized rows below the fold need a scroll first.
        let ingredientNameField = app.descendants(matching: .any).matching(identifier: "ingredientNameField").element(boundBy: 0)
        scrollUntilVisible(ingredientNameField, maxSwipes: 8)
        ingredientNameField.tap()
        ingredientNameField.typeText("Eggs")

        let ingredientAmountField = app.descendants(matching: .any).matching(identifier: "ingredientAmountField").element(boundBy: 0)
        ingredientAmountField.tap()
        ingredientAmountField.typeText("2")

        // Axis-vertical TextField surfaces as a text view, so match by identifier on any type.
        let stepField = app.descendants(matching: .any).matching(identifier: "stepInstructionField").element(boundBy: 0)
        scrollUntilVisible(stepField, maxSwipes: 8)
        stepField.tap()
        stepField.typeText("Whisk and cook.")

        let saveButton = app.buttons["saveRecipeButton"]
        XCTAssertTrue(saveButton.isEnabled, "Save should be enabled once every required field is filled")
        saveButton.tap()

        let newRow = app.buttons["recipeRow_Test Omelette"]
        scrollUntilVisible(newRow, maxSwipes: 30)
        XCTAssertTrue(newRow.exists, "the newly-created recipe should appear in the list (A-Z puts it near the end)")

        newRow.tap()
        XCTAssertTrue(app.buttons["Start Cooking"].waitForExistence(timeout: 5), "tapping the new row should open its detail")
        XCTAssertTrue(app.buttons["editRecipeButton"].waitForExistence(timeout: 5), "a user-created recipe should show an Edit button")
    }

    func testSearchFiltersByTitleAndByIngredientName() throws {
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))

        searchField.tap()
        searchField.typeText("Pizza")
        XCTAssertTrue(app.buttons["recipeRow_Homemade Pizza"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["recipeRow_Classic Scrambled Eggs"].exists, "search by title should hide non-matching recipes")

        // `matchesSearch` also checks ingredient names, not just the title — verify that path too,
        // searching for something that only appears as an ingredient of a different recipe.
        searchField.buttons["Clear text"].tap()
        searchField.typeText("shrimp")
        XCTAssertTrue(app.buttons["recipeRow_Shrimp Scampi"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["recipeRow_Homemade Pizza"].exists, "search by ingredient should hide recipes that don't contain it")
    }

    func testServingsStepperScalesIngredientAmountsLive() throws {
        let row = recipeRow("Classic Scrambled Eggs")
        XCTAssertTrue(row.isHittable)
        row.tap()

        // Classic Scrambled Eggs is `servings: 1` with "3" large eggs — doubling servings should
        // double that leading number while leaving every non-numeric amount ("A splash," "A
        // pinch," "1 knob") untouched.
        let eggsAmount = app.staticTexts["ingredientAmount_Large eggs"]
        XCTAssertTrue(eggsAmount.waitForExistence(timeout: 5))
        XCTAssertEqual(eggsAmount.label, "3")

        app.buttons["increaseServingsButton"].tap()
        XCTAssertEqual(eggsAmount.label, "6")

        app.buttons["decreaseServingsButton"].tap()
        XCTAssertEqual(eggsAmount.label, "3")
    }

    func testDietaryFilterChipHidesRecipesMissingTheTag() throws {
        // Classic Scrambled Eggs is vegetarian; Pan-Seared Steak with Garlic Butter is not.
        // Rows are tall and lazily realized, so narrow the list with search to keep each
        // recipe on screen while the Vegetarian chip is toggled.
        let chip = app.buttons["dietaryFilterChip_vegetarian"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()

        let searchField = app.searchFields.firstMatch
        searchField.tap()
        searchField.typeText("Scrambled")
        XCTAssertTrue(app.buttons["recipeRow_Classic Scrambled Eggs"].waitForExistence(timeout: 5))

        searchField.buttons["Clear text"].tap()
        searchField.typeText("Pan-Seared")
        let steak = app.buttons["recipeRow_Pan-Seared Steak with Garlic Butter"]
        XCTAssertTrue(app.buttons["recipeRow_Classic Scrambled Eggs"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(steak.exists, "a non-vegetarian recipe should be hidden while the Vegetarian filter is active")

        // Tapping the chip again clears the filter.
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()
        XCTAssertTrue(steak.waitForExistence(timeout: 5))
    }

    func testAddToShoppingListAddsIngredientsAndClearingChecksThemOff() throws {
        let row = recipeRow("Classic Scrambled Eggs")
        XCTAssertTrue(row.isHittable)
        row.tap()

        app.buttons["addToShoppingListButton"].tap()
        app.navigationBars.buttons["Recipes"].tap()

        app.buttons["shoppingListButton"].tap()
        let eggsItem = app.buttons["shoppingListItem_Large eggs"]
        XCTAssertTrue(eggsItem.waitForExistence(timeout: 5), "the recipe's ingredients should have been added to the shopping list")

        eggsItem.tap()
        app.buttons["clearCheckedItemsButton"].tap()
        XCTAssertFalse(eggsItem.exists, "clearing checked items should remove them from the list")
    }
}
