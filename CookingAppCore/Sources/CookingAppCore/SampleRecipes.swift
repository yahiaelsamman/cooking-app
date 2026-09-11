import Foundation

public enum SampleRecipes {
    // Fixed, hardcoded UUIDs — not the default random `UUID()` — so every device running the
    // app agrees on the same recipe identity. This matters specifically for the two-person
    // handshake: the host and joiner each pick "the same recipe" independently from their own
    // local copy of this bundled data, and PeerSyncService confirms the match by comparing
    // `recipeID`s. Random per-launch IDs would make that comparison always fail.

    public static let scrambledEggs = Recipe(
        id: UUID(uuidString: "9E1F0A10-0001-4B7A-9C1A-000000000001")!,
        title: "Classic Scrambled Eggs",
        summary: "Soft, creamy scrambled eggs in under 5 minutes.",
        servings: 1,
        steps: [
            RecipeStep(order: 0, instruction: "Crack 3 eggs into a bowl.", assignee: .solo, imageSystemName: "basket.fill"),
            RecipeStep(order: 1, instruction: "Add a splash of milk and a pinch of salt.", assignee: .solo, imageSystemName: "sparkles"),
            RecipeStep(order: 2, instruction: "Whisk until fully combined and slightly frothy.", assignee: .solo, imageSystemName: "arrow.triangle.2.circlepath"),
            RecipeStep(order: 3, instruction: "Heat a non-stick pan over low-medium heat with a knob of butter.", assignee: .solo, imageSystemName: "flame.fill"),
            RecipeStep(order: 4, instruction: "Pour in the eggs once the butter foams.", assignee: .solo, imageSystemName: "drop.fill"),
            RecipeStep(order: 5, instruction: "Gently push the eggs from the edges to the center with a spatula as they set.", assignee: .solo, imageSystemName: "arrow.triangle.2.circlepath"),
            RecipeStep(order: 6, instruction: "Remove from heat while still slightly glossy — they'll finish cooking off the heat. Serve.", assignee: .solo, imageSystemName: "fork.knife")
        ],
        iconSystemName: "frying.pan.fill",
        difficulty: 1,
        cookTimeMinutes: 5,
        dietaryTags: [.vegetarian, .glutenFree],
        ingredients: [
            Ingredient(name: "Large eggs", amount: "3"),
            Ingredient(name: "Milk", amount: "A splash"),
            Ingredient(name: "Salt", amount: "A pinch"),
            Ingredient(name: "Butter", amount: "1 knob")
        ]
    )

    public static let searedSteak = Recipe(
        id: UUID(uuidString: "9E1F0A10-0002-4B7A-9C1A-000000000002")!,
        title: "Pan-Seared Steak with Garlic Butter",
        summary: "A restaurant-quality steak crust, finished with garlic butter.",
        servings: 1,
        steps: [
            RecipeStep(order: 0, instruction: "Take the steak out of the fridge and let it come to room temperature.", assignee: .solo, timerSeconds: 1800, imageSystemName: "clock.fill"),
            RecipeStep(order: 1, instruction: "Pat the steak dry and season generously with salt and pepper on both sides.", assignee: .solo, imageSystemName: "sparkles"),
            RecipeStep(order: 2, instruction: "Heat a heavy skillet over high heat until it's smoking hot.", assignee: .solo, imageSystemName: "flame.fill"),
            RecipeStep(order: 3, instruction: "Add a high-smoke-point oil and lay the steak away from you.", assignee: .solo, imageSystemName: "drop.fill"),
            RecipeStep(order: 4, instruction: "Sear undisturbed, 3 minutes per side.", assignee: .solo, timerSeconds: 180, imageSystemName: "timer"),
            RecipeStep(order: 5, instruction: "Add butter, garlic, and thyme to the pan.", assignee: .solo, imageSystemName: "basket.fill"),
            RecipeStep(order: 6, instruction: "Tilt the pan and continuously spoon the butter over the steak for 1 minute.", assignee: .solo, timerSeconds: 60, imageSystemName: "timer"),
            RecipeStep(order: 7, instruction: "Remove from the pan and let it rest.", assignee: .solo, timerSeconds: 300, imageSystemName: "clock.fill"),
            RecipeStep(order: 8, instruction: "Slice against the grain and serve with the pan butter spooned over top.", assignee: .solo, imageSystemName: "fork.knife")
        ],
        iconSystemName: "flame.fill",
        difficulty: 2,
        cookTimeMinutes: 25,
        dietaryTags: [.glutenFree],
        ingredients: [
            Ingredient(name: "Ribeye or NY strip steak", amount: "1"),
            Ingredient(name: "Salt and pepper", amount: "To taste"),
            Ingredient(name: "High-smoke-point oil", amount: "1 tbsp"),
            Ingredient(name: "Butter", amount: "2 tbsp"),
            Ingredient(name: "Garlic cloves, smashed", amount: "2"),
            Ingredient(name: "Thyme sprigs", amount: "2")
        ]
    )

    public static let pastaForTwo = Recipe(
        id: UUID(uuidString: "9E1F0A10-0003-4B7A-9C1A-000000000003")!,
        title: "Weeknight Pasta for Two",
        summary: "A simple tomato pasta split into two tracks so you can both cook at once.",
        servings: 2,
        steps: [
            RecipeStep(order: 0, instruction: "Both: gather all ingredients and put a large pot of water on to boil.", assignee: .shared, imageSystemName: "flame.fill"),

            RecipeStep(order: 1, instruction: "Finely chop the garlic and onion.", assignee: .personA, imageSystemName: "scissors"),
            RecipeStep(order: 2, instruction: "Heat olive oil in a saucepan and soften the onion and garlic.", assignee: .personA, imageSystemName: "flame.fill"),
            RecipeStep(order: 3, instruction: "Add crushed tomatoes and a pinch of sugar, stir to combine.", assignee: .personA, imageSystemName: "drop.fill"),
            RecipeStep(order: 4, instruction: "Simmer the sauce, stirring occasionally.", assignee: .personA, timerSeconds: 600, imageSystemName: "timer"),
            RecipeStep(order: 5, instruction: "Season the sauce with salt, pepper, and torn basil.", assignee: .personA, imageSystemName: "sparkles"),

            RecipeStep(order: 6, instruction: "Salt the boiling water generously.", assignee: .personB, imageSystemName: "sparkles"),
            RecipeStep(order: 7, instruction: "Cook the pasta until al dente.", assignee: .personB, timerSeconds: 600, imageSystemName: "timer"),
            RecipeStep(order: 8, instruction: "Toast the garlic bread in the oven or a dry pan.", assignee: .personB, imageSystemName: "flame.fill"),
            RecipeStep(order: 9, instruction: "Make a quick side salad with whatever greens you have.", assignee: .personB, imageSystemName: "leaf.fill"),

            RecipeStep(order: 10, instruction: "Both: drain the pasta, toss it with the sauce, and plate together.", assignee: .shared, imageSystemName: "fork.knife")
        ],
        iconSystemName: "fork.knife.circle.fill",
        difficulty: 2,
        cookTimeMinutes: 35,
        dietaryTags: [.vegetarian],
        ingredients: [
            Ingredient(name: "Pasta", amount: "200g"),
            Ingredient(name: "Crushed tomatoes", amount: "1 can"),
            Ingredient(name: "Garlic cloves", amount: "2"),
            Ingredient(name: "Onion", amount: "1 small"),
            Ingredient(name: "Olive oil", amount: "2 tbsp"),
            Ingredient(name: "Sugar", amount: "A pinch"),
            Ingredient(name: "Fresh basil", amount: "A few leaves"),
            Ingredient(name: "Garlic bread", amount: "1 loaf"),
            Ingredient(name: "Salad greens", amount: "A handful")
        ]
    )

    public static let avocadoToast = Recipe(
        id: UUID(uuidString: "9E1F0A10-0004-4B7A-9C1A-000000000004")!,
        title: "Avocado Toast with Fried Egg",
        summary: "Crisp sourdough, creamy avocado, and a perfectly fried egg.",
        servings: 1,
        steps: [
            RecipeStep(order: 0, instruction: "Toast the bread until golden and crisp.", assignee: .solo, imageSystemName: "flame.fill"),
            RecipeStep(order: 1, instruction: "Halve and pit the avocado.", assignee: .solo, imageSystemName: "scissors"),
            RecipeStep(order: 2, instruction: "Scoop the avocado into a bowl.", assignee: .solo, imageSystemName: "basket.fill"),
            RecipeStep(order: 3, instruction: "Mash with a squeeze of lemon juice and a pinch of salt.", assignee: .solo, imageSystemName: "arrow.triangle.2.circlepath"),
            RecipeStep(order: 4, instruction: "Heat a small non-stick pan with a little oil over medium heat.", assignee: .solo, imageSystemName: "flame.fill"),
            RecipeStep(order: 5, instruction: "Crack the egg into the pan and fry until the white is set.", assignee: .solo, timerSeconds: 180, imageSystemName: "timer"),
            RecipeStep(order: 6, instruction: "Spread the mashed avocado over the toast.", assignee: .solo, imageSystemName: "arrow.triangle.2.circlepath"),
            RecipeStep(order: 7, instruction: "Top with the fried egg, red pepper flakes, and a pinch of salt.", assignee: .solo, imageSystemName: "sparkles"),
            RecipeStep(order: 8, instruction: "Serve immediately.", assignee: .solo, imageSystemName: "fork.knife")
        ],
        iconSystemName: "leaf.fill",
        difficulty: 1,
        cookTimeMinutes: 10,
        dietaryTags: [.vegetarian],
        ingredients: [
            Ingredient(name: "Sourdough bread", amount: "2 slices"),
            Ingredient(name: "Ripe avocado", amount: "1"),
            Ingredient(name: "Egg", amount: "1"),
            Ingredient(name: "Olive oil", amount: "A drizzle"),
            Ingredient(name: "Red pepper flakes", amount: "A pinch"),
            Ingredient(name: "Lemon juice", amount: "A squeeze"),
            Ingredient(name: "Salt", amount: "To taste")
        ]
    )

    public static let grilledCheese = Recipe(
        id: UUID(uuidString: "9E1F0A10-0005-4B7A-9C1A-000000000005")!,
        title: "Classic Grilled Cheese",
        summary: "Golden, buttery bread with melted cheddar in the middle.",
        servings: 1,
        steps: [
            RecipeStep(order: 0, instruction: "Butter one side of each bread slice.", assignee: .solo, imageSystemName: "basket.fill"),
            RecipeStep(order: 1, instruction: "Heat a skillet over medium-low heat.", assignee: .solo, imageSystemName: "flame.fill"),
            RecipeStep(order: 2, instruction: "Place one slice butter-side down in the skillet.", assignee: .solo, imageSystemName: "drop.fill"),
            RecipeStep(order: 3, instruction: "Layer the cheese slices on top.", assignee: .solo, imageSystemName: "basket.fill"),
            RecipeStep(order: 4, instruction: "Top with the second slice, butter-side up.", assignee: .solo, imageSystemName: "arrow.triangle.2.circlepath"),
            RecipeStep(order: 5, instruction: "Cook until the bottom is golden brown.", assignee: .solo, timerSeconds: 180, imageSystemName: "timer"),
            RecipeStep(order: 6, instruction: "Flip carefully and cook the other side until golden and the cheese has melted.", assignee: .solo, timerSeconds: 180, imageSystemName: "timer"),
            RecipeStep(order: 7, instruction: "Remove from the pan and let it rest for a minute before cutting.", assignee: .solo, timerSeconds: 60, imageSystemName: "clock.fill"),
            RecipeStep(order: 8, instruction: "Slice in half and serve.", assignee: .solo, imageSystemName: "fork.knife")
        ],
        iconSystemName: "rectangle.stack.fill",
        difficulty: 1,
        cookTimeMinutes: 10,
        dietaryTags: [.vegetarian],
        ingredients: [
            Ingredient(name: "White bread", amount: "2 slices"),
            Ingredient(name: "Cheddar cheese", amount: "2 slices"),
            Ingredient(name: "Butter", amount: "1 tbsp")
        ]
    )

    public static let tomatoSoup = Recipe(
        id: UUID(uuidString: "9E1F0A10-0006-4B7A-9C1A-000000000006")!,
        title: "Simple Tomato Soup",
        summary: "A comforting, blended tomato soup from a can of good tomatoes.",
        servings: 2,
        steps: [
            RecipeStep(order: 0, instruction: "Dice the onion and mince the garlic.", assignee: .solo, imageSystemName: "scissors"),
            RecipeStep(order: 1, instruction: "Heat olive oil in a pot over medium heat.", assignee: .solo, imageSystemName: "flame.fill"),
            RecipeStep(order: 2, instruction: "Add the onion and cook until soft and translucent.", assignee: .solo, timerSeconds: 300, imageSystemName: "timer"),
            RecipeStep(order: 3, instruction: "Add the garlic and cook until fragrant.", assignee: .solo, timerSeconds: 60, imageSystemName: "timer"),
            RecipeStep(order: 4, instruction: "Add the canned tomatoes and vegetable stock.", assignee: .solo, imageSystemName: "drop.fill"),
            RecipeStep(order: 5, instruction: "Season with salt and pepper.", assignee: .solo, imageSystemName: "sparkles"),
            RecipeStep(order: 6, instruction: "Bring to a simmer.", assignee: .solo, imageSystemName: "flame.fill"),
            RecipeStep(order: 7, instruction: "Simmer, stirring occasionally.", assignee: .solo, timerSeconds: 900, imageSystemName: "timer"),
            RecipeStep(order: 8, instruction: "Blend until smooth with an immersion blender.", assignee: .solo, imageSystemName: "arrow.triangle.2.circlepath"),
            RecipeStep(order: 9, instruction: "Stir in a splash of cream if using, and taste for seasoning.", assignee: .solo, imageSystemName: "drop.fill"),
            RecipeStep(order: 10, instruction: "Ladle into bowls and top with torn basil.", assignee: .solo, imageSystemName: "fork.knife")
        ],
        iconSystemName: "cup.and.saucer.fill",
        difficulty: 1,
        cookTimeMinutes: 30,
        dietaryTags: [.vegetarian, .glutenFree],
        ingredients: [
            Ingredient(name: "Olive oil", amount: "2 tbsp"),
            Ingredient(name: "Onion", amount: "1"),
            Ingredient(name: "Garlic cloves", amount: "2"),
            Ingredient(name: "Canned tomatoes", amount: "800g"),
            Ingredient(name: "Vegetable stock", amount: "500ml"),
            Ingredient(name: "Salt and pepper", amount: "To taste"),
            Ingredient(name: "Fresh basil", amount: "A few leaves"),
            Ingredient(name: "Cream (optional)", amount: "A splash")
        ]
    )

    public static let pizzaNight = Recipe(
        id: UUID(uuidString: "9E1F0A10-0007-4B7A-9C1A-000000000007")!,
        title: "Homemade Pizza Night",
        summary: "Stretch, sauce, top, and bake — split into a dough-and-sauce track and a toppings track.",
        servings: 2,
        steps: [
            RecipeStep(order: 0, instruction: "Both: gather ingredients and preheat the oven as hot as it will go with a pizza stone or tray inside.", assignee: .shared, imageSystemName: "flame.fill"),

            RecipeStep(order: 1, instruction: "Dust the counter with flour and stretch the dough into a round.", assignee: .personA, imageSystemName: "arrow.triangle.2.circlepath"),
            RecipeStep(order: 2, instruction: "Spread crushed tomatoes evenly over the dough, leaving a border for the crust.", assignee: .personA, imageSystemName: "drop.fill"),
            RecipeStep(order: 3, instruction: "Drizzle with olive oil and a pinch of salt.", assignee: .personA, imageSystemName: "sparkles"),
            RecipeStep(order: 4, instruction: "Mince the garlic and scatter it over the sauce.", assignee: .personA, imageSystemName: "scissors"),

            RecipeStep(order: 5, instruction: "Slice the mozzarella and your toppings of choice.", assignee: .personB, imageSystemName: "scissors"),
            RecipeStep(order: 6, instruction: "Tear fresh basil leaves.", assignee: .personB, imageSystemName: "leaf.fill"),
            RecipeStep(order: 7, instruction: "Arrange the cheese and toppings, ready to hand off.", assignee: .personB, imageSystemName: "basket.fill"),

            RecipeStep(order: 8, instruction: "Both: scatter the cheese and toppings over the sauced dough together.", assignee: .shared, imageSystemName: "person.2.fill"),
            RecipeStep(order: 9, instruction: "Both: slide it onto the hot stone or tray and bake until the crust is golden and the cheese is bubbling.", assignee: .shared, timerSeconds: 600, imageSystemName: "timer"),
            RecipeStep(order: 10, instruction: "Both: slide onto a board, scatter the basil, slice, and serve.", assignee: .shared, imageSystemName: "fork.knife")
        ],
        iconSystemName: "flame.fill",
        difficulty: 3,
        cookTimeMinutes: 50,
        dietaryTags: [.vegetarian],
        ingredients: [
            Ingredient(name: "Pizza dough", amount: "1 ball"),
            Ingredient(name: "Crushed tomatoes", amount: "1/2 cup"),
            Ingredient(name: "Olive oil", amount: "A drizzle"),
            Ingredient(name: "Garlic cloves", amount: "2"),
            Ingredient(name: "Mozzarella", amount: "200g"),
            Ingredient(name: "Fresh basil", amount: "A handful"),
            Ingredient(name: "Toppings of choice", amount: "To taste"),
            Ingredient(name: "Flour, for dusting", amount: "As needed")
        ]
    )

    public static let tacoTuesday = Recipe(
        id: UUID(uuidString: "9E1F0A10-0008-4B7A-9C1A-000000000008")!,
        title: "Taco Tuesday for Two",
        summary: "Seasoned protein on one track, fresh toppings on the other, tacos together at the end.",
        servings: 2,
        steps: [
            RecipeStep(order: 0, instruction: "Both: gather all ingredients and warm a skillet for the tortillas.", assignee: .shared, imageSystemName: "flame.fill"),

            RecipeStep(order: 1, instruction: "Brown the ground beef in a skillet over medium-high heat.", assignee: .personA, imageSystemName: "flame.fill"),
            RecipeStep(order: 2, instruction: "Drain excess fat and stir in the taco seasoning with a splash of water.", assignee: .personA, imageSystemName: "drop.fill"),
            RecipeStep(order: 3, instruction: "Simmer until thickened.", assignee: .personA, timerSeconds: 300, imageSystemName: "timer"),

            RecipeStep(order: 4, instruction: "Dice the tomatoes and red onion.", assignee: .personB, imageSystemName: "scissors"),
            RecipeStep(order: 5, instruction: "Chop the cilantro and cut the lime into wedges.", assignee: .personB, imageSystemName: "scissors"),
            RecipeStep(order: 6, instruction: "Warm the tortillas in a dry skillet until pliable.", assignee: .personB, imageSystemName: "flame.fill"),

            RecipeStep(order: 7, instruction: "Both: set out the cheese, sour cream, and hot sauce for topping.", assignee: .shared, imageSystemName: "basket.fill"),
            RecipeStep(order: 8, instruction: "Both: build your tacos and dig in.", assignee: .shared, imageSystemName: "fork.knife")
        ],
        iconSystemName: "takeoutbag.and.cup.and.straw.fill",
        difficulty: 2,
        spiceLevel: 2,
        cookTimeMinutes: 30,
        dietaryTags: [],
        ingredients: [
            Ingredient(name: "Ground beef (or plant-based crumble)", amount: "500g"),
            Ingredient(name: "Taco seasoning", amount: "1 packet"),
            Ingredient(name: "Corn tortillas", amount: "8"),
            Ingredient(name: "Tomatoes", amount: "2"),
            Ingredient(name: "Red onion", amount: "1/2"),
            Ingredient(name: "Cilantro", amount: "A handful"),
            Ingredient(name: "Lime", amount: "1"),
            Ingredient(name: "Shredded cheese", amount: "1 cup"),
            Ingredient(name: "Sour cream", amount: "To taste"),
            Ingredient(name: "Hot sauce", amount: "To taste")
        ]
    )

    public static let all: [Recipe] = [
        scrambledEggs,
        searedSteak,
        pastaForTwo,
        avocadoToast,
        grilledCheese,
        tomatoSoup,
        pizzaNight,
        tacoTuesday
    ]
}
