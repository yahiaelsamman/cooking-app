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
        soloSteps: [
            RecipeStep(order: 0, instruction: "Crack 3 eggs into a bowl.", assignee: .solo, imageSystemName: "basket.fill"),
            RecipeStep(order: 1, instruction: "Add a splash of milk and a pinch of salt.", assignee: .solo, imageSystemName: "sparkles"),
            RecipeStep(order: 2, instruction: "Whisk until fully combined and slightly frothy.", assignee: .solo, imageSystemName: "arrow.triangle.2.circlepath"),
            RecipeStep(order: 3, instruction: "Heat a non-stick pan over low-medium heat with a knob of butter.", assignee: .solo, imageSystemName: "flame.fill"),
            RecipeStep(order: 4, instruction: "Pour in the eggs once the butter foams.", assignee: .solo, imageSystemName: "drop.fill"),
            RecipeStep(order: 5, instruction: "Gently push the eggs from the edges to the center with a spatula as they set.", assignee: .solo, imageSystemName: "arrow.triangle.2.circlepath"),
            RecipeStep(order: 6, instruction: "Remove from heat while still slightly glossy — they'll finish cooking off the heat. Serve.", assignee: .solo, imageSystemName: "fork.knife")
        ],
        iconSystemName: "frying.pan.fill",
        heroImageName: "recipe-photo-scrambled-eggs",
        difficulty: 1,
        soloCookTimeMinutes: 5,
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
        soloSteps: [
            RecipeStep(order: 0, instruction: "Take the steak out of the fridge and let it come to room temperature.", assignee: .solo, timerSeconds: 1800, imageSystemName: "clock.fill"),
            RecipeStep(order: 1, instruction: "Pat the steak dry and season generously with salt and pepper on both sides.", assignee: .solo, imageSystemName: "sparkles"),
            RecipeStep(order: 2, instruction: "Heat a heavy skillet over high heat until it's smoking hot.", assignee: .solo, imageSystemName: "flame.fill"),
            RecipeStep(order: 3, instruction: "Add a high-smoke-point oil and lay the steak away from you.", assignee: .solo, imageSystemName: "drop.fill"),
            RecipeStep(order: 4, instruction: "Sear undisturbed, 3 minutes per side, checking with a meat thermometer for your desired doneness (about 130°F for medium-rare, 145°F for medium).", assignee: .solo, timerSeconds: 180, imageSystemName: "timer"),
            RecipeStep(order: 5, instruction: "Add butter, garlic, and thyme to the pan.", assignee: .solo, imageSystemName: "basket.fill"),
            RecipeStep(order: 6, instruction: "Tilt the pan and continuously spoon the butter over the steak for 1 minute.", assignee: .solo, timerSeconds: 60, imageSystemName: "timer"),
            RecipeStep(order: 7, instruction: "Remove from the pan and let it rest.", assignee: .solo, timerSeconds: 300, imageSystemName: "clock.fill"),
            RecipeStep(order: 8, instruction: "Slice against the grain and serve with the pan butter spooned over top.", assignee: .solo, imageSystemName: "fork.knife")
        ],
        iconSystemName: "flame.fill",
        heroImageName: "recipe-photo-seared-steak",
        difficulty: 2,
        soloCookTimeMinutes: 25,
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
        title: "Weeknight Pasta",
        summary: "A simple tomato pasta — cook it solo, or split the sauce and pasta tracks with a partner.",
        servings: 2,
        soloSteps: [
            RecipeStep(order: 0, instruction: "Gather all ingredients and put a large pot of water on to boil.", assignee: .solo, imageSystemName: "flame.fill"),
            RecipeStep(order: 1, instruction: "Finely chop the garlic and onion.", assignee: .solo, imageSystemName: "scissors"),
            RecipeStep(order: 2, instruction: "Heat olive oil in a saucepan and soften the onion and garlic.", assignee: .solo, imageSystemName: "flame.fill"),
            RecipeStep(order: 3, instruction: "Add crushed tomatoes and a pinch of sugar, stir to combine.", assignee: .solo, imageSystemName: "drop.fill"),
            RecipeStep(order: 4, instruction: "Simmer the sauce, stirring occasionally.", assignee: .solo, timerSeconds: 600, imageSystemName: "timer"),
            RecipeStep(order: 5, instruction: "Season the sauce with salt, pepper, and torn basil.", assignee: .solo, imageSystemName: "sparkles"),
            RecipeStep(order: 6, instruction: "Salt the boiling water generously.", assignee: .solo, imageSystemName: "sparkles"),
            RecipeStep(order: 7, instruction: "Cook the pasta until al dente.", assignee: .solo, timerSeconds: 600, imageSystemName: "timer"),
            RecipeStep(order: 8, instruction: "Toast the garlic bread in the oven or a dry pan.", assignee: .solo, imageSystemName: "flame.fill"),
            RecipeStep(order: 9, instruction: "Make a quick side salad with whatever greens you have.", assignee: .solo, imageSystemName: "leaf.fill"),
            RecipeStep(order: 10, instruction: "Drain the pasta, toss it with the sauce, and plate up.", assignee: .solo, imageSystemName: "fork.knife")
        ],
        twoPersonSteps: [
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
        heroImageName: "recipe-photo-weeknight-pasta",
        difficulty: 2,
        soloCookTimeMinutes: 45,
        twoPersonCookTimeMinutes: 35,
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
        soloSteps: [
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
        heroImageName: "recipe-photo-avocado-toast",
        difficulty: 1,
        soloCookTimeMinutes: 10,
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
        soloSteps: [
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
        heroImageName: "recipe-photo-grilled-cheese",
        difficulty: 1,
        soloCookTimeMinutes: 10,
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
        soloSteps: [
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
        heroImageName: "recipe-photo-tomato-soup",
        difficulty: 1,
        soloCookTimeMinutes: 30,
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
        title: "Homemade Pizza",
        summary: "Stretch, sauce, top, and bake — solo start to finish, or split dough/sauce from toppings with a partner.",
        servings: 2,
        soloSteps: [
            RecipeStep(order: 0, instruction: "Gather ingredients and preheat the oven as hot as it will go with a pizza stone or tray inside.", assignee: .solo, imageSystemName: "flame.fill"),
            RecipeStep(order: 1, instruction: "Dust the counter with flour and stretch the dough into a round.", assignee: .solo, imageSystemName: "arrow.triangle.2.circlepath"),
            RecipeStep(order: 2, instruction: "Spread crushed tomatoes evenly over the dough, leaving a border for the crust.", assignee: .solo, imageSystemName: "drop.fill"),
            RecipeStep(order: 3, instruction: "Drizzle with olive oil and a pinch of salt.", assignee: .solo, imageSystemName: "sparkles"),
            RecipeStep(order: 4, instruction: "Mince the garlic and scatter it over the sauce.", assignee: .solo, imageSystemName: "scissors"),
            RecipeStep(order: 5, instruction: "Slice the mozzarella and your toppings of choice.", assignee: .solo, imageSystemName: "scissors"),
            RecipeStep(order: 6, instruction: "Tear fresh basil leaves.", assignee: .solo, imageSystemName: "leaf.fill"),
            RecipeStep(order: 7, instruction: "Scatter the cheese and toppings over the sauced dough.", assignee: .solo, imageSystemName: "basket.fill"),
            RecipeStep(order: 8, instruction: "Slide it onto the hot stone or tray and bake until the crust is golden and the cheese is bubbling.", assignee: .solo, timerSeconds: 600, imageSystemName: "timer"),
            RecipeStep(order: 9, instruction: "Slide onto a board, scatter the basil, slice, and serve.", assignee: .solo, imageSystemName: "fork.knife")
        ],
        twoPersonSteps: [
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
        heroImageName: "recipe-photo-homemade-pizza",
        difficulty: 3,
        soloCookTimeMinutes: 65,
        twoPersonCookTimeMinutes: 50,
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
        title: "Taco Night",
        summary: "Seasoned protein and fresh toppings — solo start to finish, or split the two tracks with a partner.",
        servings: 2,
        soloSteps: [
            RecipeStep(order: 0, instruction: "Gather all ingredients and warm a skillet for the tortillas.", assignee: .solo, imageSystemName: "flame.fill"),
            RecipeStep(order: 1, instruction: "Brown the ground beef in a skillet over medium-high heat.", assignee: .solo, imageSystemName: "flame.fill"),
            RecipeStep(order: 2, instruction: "Drain excess fat and stir in the taco seasoning with a splash of water.", assignee: .solo, imageSystemName: "drop.fill"),
            RecipeStep(order: 3, instruction: "Simmer until thickened.", assignee: .solo, timerSeconds: 300, imageSystemName: "timer"),
            RecipeStep(order: 4, instruction: "Dice the tomatoes and red onion.", assignee: .solo, imageSystemName: "scissors"),
            RecipeStep(order: 5, instruction: "Chop the cilantro and cut the lime into wedges.", assignee: .solo, imageSystemName: "scissors"),
            RecipeStep(order: 6, instruction: "Warm the tortillas in a dry skillet until pliable.", assignee: .solo, imageSystemName: "flame.fill"),
            RecipeStep(order: 7, instruction: "Set out the cheese, sour cream, and hot sauce for topping.", assignee: .solo, imageSystemName: "basket.fill"),
            RecipeStep(order: 8, instruction: "Build your tacos and dig in.", assignee: .solo, imageSystemName: "fork.knife")
        ],
        twoPersonSteps: [
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
        heroImageName: "recipe-photo-taco-night",
        difficulty: 2,
        spiceLevel: 2,
        soloCookTimeMinutes: 40,
        twoPersonCookTimeMinutes: 30,
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

    public static let chickenStirFry = Recipe(
        id: UUID(uuidString: "9E1F0A10-0009-4B7A-9C1A-000000000009")!,
        title: "Chicken Stir-Fry",
        summary: "Quick, saucy stir-fry with crisp vegetables — solo start to finish, or split veg prep from the wok with a partner.",
        servings: 2,
        soloSteps: [
            RecipeStep(order: 0, instruction: "Cut the chicken breast into bite-sized pieces.", assignee: .solo, imageSystemName: "scissors"),
            RecipeStep(order: 1, instruction: "Whisk soy sauce, garlic, ginger, and cornstarch into a stir-fry sauce.", assignee: .solo, imageSystemName: "drop.fill"),
            RecipeStep(order: 2, instruction: "Slice the bell pepper, broccoli, and carrot into thin pieces.", assignee: .solo, imageSystemName: "scissors"),
            RecipeStep(order: 3, instruction: "Heat oil in a wok or large skillet over high heat.", assignee: .solo, imageSystemName: "flame.fill"),
            RecipeStep(order: 4, instruction: "Stir-fry the chicken until browned and cooked through (165°F internal temperature).", assignee: .solo, timerSeconds: 300, imageSystemName: "timer"),
            RecipeStep(order: 5, instruction: "Add the vegetables and stir-fry until crisp-tender.", assignee: .solo, timerSeconds: 240, imageSystemName: "timer"),
            RecipeStep(order: 6, instruction: "Pour in the sauce and toss until everything's glossy and coated.", assignee: .solo, imageSystemName: "drop.fill"),
            RecipeStep(order: 7, instruction: "Serve over rice.", assignee: .solo, imageSystemName: "fork.knife")
        ],
        twoPersonSteps: [
            RecipeStep(order: 0, instruction: "Both: put rice on to cook and gather ingredients.", assignee: .shared, imageSystemName: "flame.fill"),

            RecipeStep(order: 1, instruction: "Whisk soy sauce, garlic, ginger, and cornstarch into a stir-fry sauce.", assignee: .personA, imageSystemName: "drop.fill"),
            RecipeStep(order: 2, instruction: "Slice the bell pepper, broccoli, and carrot into thin pieces.", assignee: .personA, imageSystemName: "scissors"),

            RecipeStep(order: 3, instruction: "Cut the chicken breast into bite-sized pieces.", assignee: .personB, imageSystemName: "scissors"),
            RecipeStep(order: 4, instruction: "Heat oil in a wok and stir-fry the chicken until browned and cooked through (165°F internal temperature).", assignee: .personB, timerSeconds: 300, imageSystemName: "timer"),

            RecipeStep(order: 5, instruction: "Both: add the vegetables and sauce to the wok and toss until glossy and coated.", assignee: .shared, timerSeconds: 180, imageSystemName: "timer"),
            RecipeStep(order: 6, instruction: "Both: serve over rice.", assignee: .shared, imageSystemName: "fork.knife")
        ],
        iconSystemName: "flame.fill",
        difficulty: 2,
        spiceLevel: 1,
        soloCookTimeMinutes: 30,
        twoPersonCookTimeMinutes: 22,
        ingredients: [
            Ingredient(name: "Chicken breast", amount: "400g"),
            Ingredient(name: "Soy sauce", amount: "3 tbsp"),
            Ingredient(name: "Garlic cloves", amount: "2"),
            Ingredient(name: "Ginger, grated", amount: "1 tsp"),
            Ingredient(name: "Cornstarch", amount: "1 tbsp"),
            Ingredient(name: "Bell pepper", amount: "1"),
            Ingredient(name: "Broccoli florets", amount: "1 cup"),
            Ingredient(name: "Carrot", amount: "1"),
            Ingredient(name: "Vegetable oil", amount: "2 tbsp"),
            Ingredient(name: "Cooked rice", amount: "For serving")
        ]
    )

    public static let beefChili = Recipe(
        id: UUID(uuidString: "9E1F0A10-0010-4B7A-9C1A-000000000010")!,
        title: "Beef Chili",
        summary: "A hearty, slow-simmered chili loaded with beans — solo start to finish, or split the simmering pot from the toppings bar with a partner.",
        servings: 4,
        soloSteps: [
            RecipeStep(order: 0, instruction: "Dice the onion and bell pepper.", assignee: .solo, imageSystemName: "scissors"),
            RecipeStep(order: 1, instruction: "Heat oil in a large pot and brown the ground beef.", assignee: .solo, timerSeconds: 480, imageSystemName: "timer"),
            RecipeStep(order: 2, instruction: "Add the onion, bell pepper, and garlic, and cook until softened.", assignee: .solo, timerSeconds: 300, imageSystemName: "timer"),
            RecipeStep(order: 3, instruction: "Stir in chili powder, cumin, and paprika.", assignee: .solo, imageSystemName: "sparkles"),
            RecipeStep(order: 4, instruction: "Add crushed tomatoes, beans, and beef stock.", assignee: .solo, imageSystemName: "drop.fill"),
            RecipeStep(order: 5, instruction: "Bring to a simmer and cook, stirring occasionally.", assignee: .solo, timerSeconds: 1800, imageSystemName: "timer"),
            RecipeStep(order: 6, instruction: "Season with salt and pepper to taste.", assignee: .solo, imageSystemName: "sparkles"),
            RecipeStep(order: 7, instruction: "Set out shredded cheese, sour cream, and chopped scallions for topping.", assignee: .solo, imageSystemName: "basket.fill"),
            RecipeStep(order: 8, instruction: "Ladle into bowls and top as you like.", assignee: .solo, imageSystemName: "fork.knife")
        ],
        twoPersonSteps: [
            RecipeStep(order: 0, instruction: "Both: gather ingredients and dice the onion and bell pepper together.", assignee: .shared, imageSystemName: "scissors"),

            RecipeStep(order: 1, instruction: "Heat oil in a large pot and brown the ground beef.", assignee: .personA, timerSeconds: 480, imageSystemName: "timer"),
            RecipeStep(order: 2, instruction: "Add the onion, bell pepper, and garlic, and cook until softened.", assignee: .personA, timerSeconds: 300, imageSystemName: "timer"),
            RecipeStep(order: 3, instruction: "Stir in the spices, then add crushed tomatoes, beans, and stock, and simmer.", assignee: .personA, timerSeconds: 1500, imageSystemName: "timer"),

            RecipeStep(order: 4, instruction: "Shred the cheese and chop the scallions.", assignee: .personB, imageSystemName: "scissors"),
            RecipeStep(order: 5, instruction: "Set out sour cream and any other toppings you like.", assignee: .personB, imageSystemName: "basket.fill"),
            RecipeStep(order: 6, instruction: "Warm cornbread or tortilla chips to serve alongside.", assignee: .personB, imageSystemName: "flame.fill"),

            RecipeStep(order: 7, instruction: "Both: ladle into bowls and top as you like.", assignee: .shared, imageSystemName: "fork.knife")
        ],
        iconSystemName: "flame.fill",
        difficulty: 2,
        spiceLevel: 2,
        soloCookTimeMinutes: 50,
        twoPersonCookTimeMinutes: 38,
        ingredients: [
            Ingredient(name: "Ground beef", amount: "500g"),
            Ingredient(name: "Onion", amount: "1"),
            Ingredient(name: "Bell pepper", amount: "1"),
            Ingredient(name: "Garlic cloves", amount: "3"),
            Ingredient(name: "Chili powder", amount: "2 tbsp"),
            Ingredient(name: "Cumin", amount: "1 tbsp"),
            Ingredient(name: "Paprika", amount: "1 tsp"),
            Ingredient(name: "Crushed tomatoes", amount: "1 can"),
            Ingredient(name: "Kidney beans, drained", amount: "1 can"),
            Ingredient(name: "Beef stock", amount: "1 cup"),
            Ingredient(name: "Shredded cheese", amount: "To taste"),
            Ingredient(name: "Sour cream", amount: "To taste"),
            Ingredient(name: "Scallions", amount: "A handful")
        ]
    )

    public static let capreseSalad = Recipe(
        id: UUID(uuidString: "9E1F0A10-0011-4B7A-9C1A-000000000011")!,
        title: "Caprese Salad",
        summary: "Ripe tomatoes, fresh mozzarella, and basil with a good olive oil — no cooking required.",
        servings: 2,
        soloSteps: [
            RecipeStep(order: 0, instruction: "Slice the tomatoes and mozzarella into rounds of similar thickness.", assignee: .solo, imageSystemName: "scissors"),
            RecipeStep(order: 1, instruction: "Arrange alternating slices of tomato and mozzarella on a plate.", assignee: .solo, imageSystemName: "arrow.triangle.2.circlepath"),
            RecipeStep(order: 2, instruction: "Tuck fresh basil leaves between the slices.", assignee: .solo, imageSystemName: "leaf.fill"),
            RecipeStep(order: 3, instruction: "Drizzle generously with olive oil and balsamic glaze.", assignee: .solo, imageSystemName: "drop.fill"),
            RecipeStep(order: 4, instruction: "Season with flaky salt and cracked black pepper.", assignee: .solo, imageSystemName: "sparkles"),
            RecipeStep(order: 5, instruction: "Serve immediately at room temperature.", assignee: .solo, imageSystemName: "fork.knife")
        ],
        iconSystemName: "leaf.fill",
        difficulty: 1,
        soloCookTimeMinutes: 10,
        dietaryTags: [.vegetarian, .glutenFree],
        ingredients: [
            Ingredient(name: "Ripe tomatoes", amount: "3"),
            Ingredient(name: "Fresh mozzarella", amount: "200g"),
            Ingredient(name: "Fresh basil", amount: "A handful"),
            Ingredient(name: "Olive oil", amount: "A generous drizzle"),
            Ingredient(name: "Balsamic glaze", amount: "A drizzle"),
            Ingredient(name: "Flaky salt", amount: "To taste"),
            Ingredient(name: "Black pepper", amount: "To taste")
        ]
    )

    public static let bananaPancakes = Recipe(
        id: UUID(uuidString: "9E1F0A10-0012-4B7A-9C1A-000000000012")!,
        title: "Banana Pancakes",
        summary: "Fluffy pancakes with mashed banana folded right into the batter.",
        servings: 2,
        soloSteps: [
            RecipeStep(order: 0, instruction: "Mash the ripe banana in a large bowl.", assignee: .solo, imageSystemName: "arrow.triangle.2.circlepath"),
            RecipeStep(order: 1, instruction: "Whisk in the egg, milk, and melted butter.", assignee: .solo, imageSystemName: "drop.fill"),
            RecipeStep(order: 2, instruction: "In a separate bowl, mix flour, sugar, baking powder, and a pinch of salt.", assignee: .solo, imageSystemName: "sparkles"),
            RecipeStep(order: 3, instruction: "Fold the dry ingredients into the wet ingredients until just combined.", assignee: .solo, imageSystemName: "arrow.triangle.2.circlepath"),
            RecipeStep(order: 4, instruction: "Heat a lightly oiled griddle or pan over medium heat.", assignee: .solo, imageSystemName: "flame.fill"),
            RecipeStep(order: 5, instruction: "Pour batter to form pancakes and cook until bubbles form on top.", assignee: .solo, timerSeconds: 180, imageSystemName: "timer"),
            RecipeStep(order: 6, instruction: "Flip and cook until golden on the other side.", assignee: .solo, timerSeconds: 120, imageSystemName: "timer"),
            RecipeStep(order: 7, instruction: "Stack and serve with maple syrup.", assignee: .solo, imageSystemName: "fork.knife")
        ],
        iconSystemName: "frying.pan.fill",
        difficulty: 1,
        soloCookTimeMinutes: 20,
        dietaryTags: [.vegetarian],
        ingredients: [
            Ingredient(name: "Ripe banana", amount: "1"),
            Ingredient(name: "Egg", amount: "1"),
            Ingredient(name: "Milk", amount: "3/4 cup"),
            Ingredient(name: "Butter, melted", amount: "2 tbsp"),
            Ingredient(name: "Flour", amount: "1 cup"),
            Ingredient(name: "Sugar", amount: "2 tbsp"),
            Ingredient(name: "Baking powder", amount: "2 tsp"),
            Ingredient(name: "Salt", amount: "A pinch"),
            Ingredient(name: "Maple syrup", amount: "For serving")
        ]
    )

    public static let shrimpScampi = Recipe(
        id: UUID(uuidString: "9E1F0A10-0013-4B7A-9C1A-000000000013")!,
        title: "Shrimp Scampi",
        summary: "Garlicky, buttery shrimp tossed with linguine and a splash of white wine.",
        servings: 2,
        soloSteps: [
            RecipeStep(order: 0, instruction: "Cook the linguine in salted boiling water until al dente.", assignee: .solo, timerSeconds: 600, imageSystemName: "timer"),
            RecipeStep(order: 1, instruction: "Pat the shrimp dry and season with salt and pepper.", assignee: .solo, imageSystemName: "sparkles"),
            RecipeStep(order: 2, instruction: "Melt butter with olive oil in a large skillet over medium heat.", assignee: .solo, imageSystemName: "flame.fill"),
            RecipeStep(order: 3, instruction: "Add minced garlic and red pepper flakes, and cook until fragrant.", assignee: .solo, timerSeconds: 60, imageSystemName: "timer"),
            RecipeStep(order: 4, instruction: "Add the shrimp and cook until just pink, about 2 minutes per side.", assignee: .solo, timerSeconds: 240, imageSystemName: "timer"),
            RecipeStep(order: 5, instruction: "Pour in white wine and lemon juice, and simmer briefly.", assignee: .solo, imageSystemName: "drop.fill"),
            RecipeStep(order: 6, instruction: "Toss the drained pasta with the shrimp and sauce.", assignee: .solo, imageSystemName: "arrow.triangle.2.circlepath"),
            RecipeStep(order: 7, instruction: "Finish with chopped parsley and serve.", assignee: .solo, imageSystemName: "leaf.fill")
        ],
        twoPersonSteps: [
            RecipeStep(order: 0, instruction: "Both: gather ingredients and get a pot of salted water on to boil.", assignee: .shared, imageSystemName: "flame.fill"),

            RecipeStep(order: 1, instruction: "Cook the linguine until al dente, then drain.", assignee: .personA, timerSeconds: 600, imageSystemName: "timer"),

            RecipeStep(order: 2, instruction: "Pat the shrimp dry and season with salt and pepper.", assignee: .personB, imageSystemName: "sparkles"),
            RecipeStep(order: 3, instruction: "Melt butter with olive oil in a skillet and cook garlic and red pepper flakes until fragrant.", assignee: .personB, timerSeconds: 60, imageSystemName: "timer"),
            RecipeStep(order: 4, instruction: "Add the shrimp and cook until just pink, about 2 minutes per side.", assignee: .personB, timerSeconds: 240, imageSystemName: "timer"),
            RecipeStep(order: 5, instruction: "Pour in white wine and lemon juice, and simmer briefly.", assignee: .personB, imageSystemName: "drop.fill"),

            RecipeStep(order: 6, instruction: "Both: toss the drained pasta with the shrimp and sauce.", assignee: .shared, imageSystemName: "arrow.triangle.2.circlepath"),
            RecipeStep(order: 7, instruction: "Both: finish with chopped parsley and serve.", assignee: .shared, imageSystemName: "leaf.fill")
        ],
        iconSystemName: "fork.knife.circle.fill",
        difficulty: 2,
        spiceLevel: 1,
        soloCookTimeMinutes: 25,
        twoPersonCookTimeMinutes: 18,
        ingredients: [
            Ingredient(name: "Linguine", amount: "200g"),
            Ingredient(name: "Shrimp, peeled and deveined", amount: "400g"),
            Ingredient(name: "Butter", amount: "3 tbsp"),
            Ingredient(name: "Olive oil", amount: "1 tbsp"),
            Ingredient(name: "Garlic cloves", amount: "4"),
            Ingredient(name: "Red pepper flakes", amount: "A pinch"),
            Ingredient(name: "White wine", amount: "1/4 cup"),
            Ingredient(name: "Lemon juice", amount: "1 tbsp"),
            Ingredient(name: "Fresh parsley, chopped", amount: "A handful"),
            Ingredient(name: "Salt and pepper", amount: "To taste")
        ]
    )

    public static let vegetableFriedRice = Recipe(
        id: UUID(uuidString: "9E1F0A10-0014-4B7A-9C1A-000000000014")!,
        title: "Vegetable Fried Rice",
        summary: "Fast, wok-fried rice loaded with vegetables and scrambled egg — great for using up leftover rice.",
        servings: 2,
        soloSteps: [
            RecipeStep(order: 0, instruction: "Dice the carrot, onion, and bell pepper.", assignee: .solo, imageSystemName: "scissors"),
            RecipeStep(order: 1, instruction: "Heat oil in a wok or large skillet over high heat.", assignee: .solo, imageSystemName: "flame.fill"),
            RecipeStep(order: 2, instruction: "Scramble the eggs in the wok and set aside.", assignee: .solo, timerSeconds: 120, imageSystemName: "timer"),
            RecipeStep(order: 3, instruction: "Add the vegetables and stir-fry until just tender.", assignee: .solo, timerSeconds: 180, imageSystemName: "timer"),
            RecipeStep(order: 4, instruction: "Add the cold, day-old rice, breaking up any clumps.", assignee: .solo, imageSystemName: "arrow.triangle.2.circlepath"),
            RecipeStep(order: 5, instruction: "Stir in soy sauce and sesame oil, tossing to coat evenly.", assignee: .solo, imageSystemName: "drop.fill"),
            RecipeStep(order: 6, instruction: "Fold the scrambled egg back in and add scallions.", assignee: .solo, imageSystemName: "basket.fill"),
            RecipeStep(order: 7, instruction: "Serve hot.", assignee: .solo, imageSystemName: "fork.knife")
        ],
        twoPersonSteps: [
            RecipeStep(order: 0, instruction: "Both: gather ingredients — the rice should be cold, day-old rice.", assignee: .shared, imageSystemName: "basket.fill"),

            RecipeStep(order: 1, instruction: "Dice the carrot, onion, and bell pepper.", assignee: .personA, imageSystemName: "scissors"),
            RecipeStep(order: 2, instruction: "Chop the scallions.", assignee: .personA, imageSystemName: "scissors"),

            RecipeStep(order: 3, instruction: "Heat oil in a wok and scramble the eggs, then set aside.", assignee: .personB, timerSeconds: 120, imageSystemName: "timer"),
            RecipeStep(order: 4, instruction: "Add the vegetables and stir-fry until just tender.", assignee: .personB, timerSeconds: 180, imageSystemName: "timer"),

            RecipeStep(order: 5, instruction: "Both: add the rice, breaking up clumps, and stir in soy sauce and sesame oil.", assignee: .shared, timerSeconds: 120, imageSystemName: "timer"),
            RecipeStep(order: 6, instruction: "Both: fold the egg back in, add scallions, and serve.", assignee: .shared, imageSystemName: "fork.knife")
        ],
        iconSystemName: "leaf.fill",
        difficulty: 1,
        soloCookTimeMinutes: 20,
        twoPersonCookTimeMinutes: 14,
        dietaryTags: [.vegetarian],
        ingredients: [
            Ingredient(name: "Cooked rice (cold, day-old)", amount: "3 cups"),
            Ingredient(name: "Eggs", amount: "2"),
            Ingredient(name: "Carrot", amount: "1"),
            Ingredient(name: "Onion", amount: "1/2"),
            Ingredient(name: "Bell pepper", amount: "1/2"),
            Ingredient(name: "Vegetable oil", amount: "2 tbsp"),
            Ingredient(name: "Soy sauce", amount: "2 tbsp"),
            Ingredient(name: "Sesame oil", amount: "1 tsp"),
            Ingredient(name: "Scallions, chopped", amount: "A handful")
        ]
    )

    public static let chickenCaesarSalad = Recipe(
        id: UUID(uuidString: "9E1F0A10-0015-4B7A-9C1A-000000000015")!,
        title: "Chicken Caesar Salad",
        summary: "Crisp romaine, shaved parmesan, and seared chicken tossed in a garlicky Caesar dressing.",
        servings: 2,
        soloSteps: [
            RecipeStep(order: 0, instruction: "Season the chicken breast with salt and pepper.", assignee: .solo, imageSystemName: "sparkles"),
            RecipeStep(order: 1, instruction: "Heat olive oil in a skillet over medium-high heat.", assignee: .solo, imageSystemName: "flame.fill"),
            RecipeStep(order: 2, instruction: "Sear the chicken until cooked through (165°F internal temperature), about 6 minutes per side.", assignee: .solo, timerSeconds: 720, imageSystemName: "timer"),
            RecipeStep(order: 3, instruction: "Let the chicken rest, then slice it.", assignee: .solo, timerSeconds: 300, imageSystemName: "clock.fill"),
            RecipeStep(order: 4, instruction: "Chop the romaine lettuce into bite-sized pieces.", assignee: .solo, imageSystemName: "scissors"),
            RecipeStep(order: 5, instruction: "Toast bread cubes in a dry pan until golden for croutons.", assignee: .solo, timerSeconds: 240, imageSystemName: "timer"),
            RecipeStep(order: 6, instruction: "Toss the lettuce with Caesar dressing and shaved parmesan.", assignee: .solo, imageSystemName: "arrow.triangle.2.circlepath"),
            RecipeStep(order: 7, instruction: "Top with the sliced chicken and croutons.", assignee: .solo, imageSystemName: "fork.knife")
        ],
        twoPersonSteps: [
            RecipeStep(order: 0, instruction: "Both: gather ingredients.", assignee: .shared, imageSystemName: "basket.fill"),

            RecipeStep(order: 1, instruction: "Season the chicken breast with salt and pepper.", assignee: .personA, imageSystemName: "sparkles"),
            RecipeStep(order: 2, instruction: "Heat olive oil in a skillet and sear the chicken until cooked through (165°F internal temperature), about 6 minutes per side.", assignee: .personA, timerSeconds: 720, imageSystemName: "timer"),
            RecipeStep(order: 3, instruction: "Let the chicken rest, then slice it.", assignee: .personA, timerSeconds: 300, imageSystemName: "clock.fill"),

            RecipeStep(order: 4, instruction: "Chop the romaine lettuce into bite-sized pieces.", assignee: .personB, imageSystemName: "scissors"),
            RecipeStep(order: 5, instruction: "Toast bread cubes in a dry pan until golden for croutons.", assignee: .personB, timerSeconds: 240, imageSystemName: "timer"),

            RecipeStep(order: 6, instruction: "Both: toss the lettuce with Caesar dressing and shaved parmesan.", assignee: .shared, imageSystemName: "arrow.triangle.2.circlepath"),
            RecipeStep(order: 7, instruction: "Both: top with the sliced chicken and croutons.", assignee: .shared, imageSystemName: "fork.knife")
        ],
        iconSystemName: "leaf.fill",
        difficulty: 2,
        soloCookTimeMinutes: 30,
        twoPersonCookTimeMinutes: 20,
        ingredients: [
            Ingredient(name: "Chicken breast", amount: "1"),
            Ingredient(name: "Romaine lettuce", amount: "1 head"),
            Ingredient(name: "Parmesan, shaved", amount: "1/2 cup"),
            Ingredient(name: "Bread, for croutons", amount: "2 slices"),
            Ingredient(name: "Caesar dressing", amount: "1/4 cup"),
            Ingredient(name: "Olive oil", amount: "1 tbsp"),
            Ingredient(name: "Salt and pepper", amount: "To taste")
        ]
    )

    public static let bakedSalmon = Recipe(
        id: UUID(uuidString: "9E1F0A10-0016-4B7A-9C1A-000000000016")!,
        title: "Baked Salmon with Asparagus",
        summary: "A simple sheet-pan dinner — salmon and asparagus roasted together with lemon and garlic.",
        servings: 2,
        soloSteps: [
            RecipeStep(order: 0, instruction: "Preheat the oven and line a sheet pan with foil.", assignee: .solo, imageSystemName: "flame.fill"),
            RecipeStep(order: 1, instruction: "Trim the woody ends off the asparagus.", assignee: .solo, imageSystemName: "scissors"),
            RecipeStep(order: 2, instruction: "Arrange the salmon and asparagus on the sheet pan.", assignee: .solo, imageSystemName: "basket.fill"),
            RecipeStep(order: 3, instruction: "Drizzle with olive oil and scatter minced garlic over both.", assignee: .solo, imageSystemName: "drop.fill"),
            RecipeStep(order: 4, instruction: "Season with salt, pepper, and lemon slices on top.", assignee: .solo, imageSystemName: "sparkles"),
            RecipeStep(order: 5, instruction: "Roast until the salmon flakes easily and the asparagus is tender.", assignee: .solo, timerSeconds: 720, imageSystemName: "timer"),
            RecipeStep(order: 6, instruction: "Squeeze fresh lemon juice over everything before serving.", assignee: .solo, imageSystemName: "drop.fill")
        ],
        twoPersonSteps: [
            RecipeStep(order: 0, instruction: "Both: preheat the oven and line a sheet pan with foil.", assignee: .shared, imageSystemName: "flame.fill"),

            RecipeStep(order: 1, instruction: "Trim the woody ends off the asparagus.", assignee: .personA, imageSystemName: "scissors"),
            RecipeStep(order: 2, instruction: "Mince the garlic and slice the lemon.", assignee: .personB, imageSystemName: "scissors"),

            RecipeStep(order: 3, instruction: "Both: arrange the salmon and asparagus on the sheet pan.", assignee: .shared, imageSystemName: "basket.fill"),
            RecipeStep(order: 4, instruction: "Both: drizzle with olive oil, scatter garlic, and season with salt, pepper, and lemon slices.", assignee: .shared, imageSystemName: "drop.fill"),
            RecipeStep(order: 5, instruction: "Both: roast until the salmon flakes easily and the asparagus is tender.", assignee: .shared, timerSeconds: 720, imageSystemName: "timer"),
            RecipeStep(order: 6, instruction: "Both: squeeze fresh lemon juice over everything before serving.", assignee: .shared, imageSystemName: "drop.fill")
        ],
        iconSystemName: "leaf.fill",
        difficulty: 1,
        soloCookTimeMinutes: 25,
        twoPersonCookTimeMinutes: 20,
        dietaryTags: [.glutenFree, .lactoseFree],
        ingredients: [
            Ingredient(name: "Salmon fillets", amount: "2"),
            Ingredient(name: "Asparagus", amount: "1 bunch"),
            Ingredient(name: "Olive oil", amount: "2 tbsp"),
            Ingredient(name: "Garlic cloves", amount: "2"),
            Ingredient(name: "Lemon", amount: "1"),
            Ingredient(name: "Salt and pepper", amount: "To taste")
        ]
    )

    public static let frenchOnionSoup = Recipe(
        id: UUID(uuidString: "9E1F0A10-0017-4B7A-9C1A-000000000017")!,
        title: "French Onion Soup",
        summary: "Deeply caramelized onions in a rich broth, topped with toasted bread and melted gruyère.",
        servings: 2,
        soloSteps: [
            RecipeStep(order: 0, instruction: "Thinly slice the onions.", assignee: .solo, imageSystemName: "scissors"),
            RecipeStep(order: 1, instruction: "Melt butter in a large pot over medium-low heat.", assignee: .solo, imageSystemName: "flame.fill"),
            RecipeStep(order: 2, instruction: "Cook the onions low and slow, stirring occasionally, until deeply caramelized.", assignee: .solo, timerSeconds: 2400, imageSystemName: "timer"),
            RecipeStep(order: 3, instruction: "Add minced garlic and cook until fragrant.", assignee: .solo, timerSeconds: 60, imageSystemName: "timer"),
            RecipeStep(order: 4, instruction: "Sprinkle in flour and stir to coat the onions.", assignee: .solo, imageSystemName: "sparkles"),
            RecipeStep(order: 5, instruction: "Pour in beef stock and a splash of sherry, and simmer.", assignee: .solo, timerSeconds: 900, imageSystemName: "timer"),
            RecipeStep(order: 6, instruction: "Season with salt, pepper, and thyme.", assignee: .solo, imageSystemName: "sparkles"),
            RecipeStep(order: 7, instruction: "Ladle into oven-safe bowls and top with toasted bread and gruyère.", assignee: .solo, imageSystemName: "basket.fill"),
            RecipeStep(order: 8, instruction: "Broil until the cheese is bubbling and golden.", assignee: .solo, timerSeconds: 180, imageSystemName: "timer")
        ],
        twoPersonSteps: [
            RecipeStep(order: 0, instruction: "Both: thinly slice the onions together — the more hands, the faster this part goes.", assignee: .shared, imageSystemName: "scissors"),

            RecipeStep(order: 1, instruction: "Melt butter in a large pot and cook the onions low and slow until deeply caramelized.", assignee: .personA, timerSeconds: 2400, imageSystemName: "timer"),
            RecipeStep(order: 2, instruction: "Add garlic, flour, stock, and sherry, and simmer.", assignee: .personA, timerSeconds: 900, imageSystemName: "timer"),
            RecipeStep(order: 3, instruction: "Season with salt, pepper, and thyme.", assignee: .personA, imageSystemName: "sparkles"),

            RecipeStep(order: 4, instruction: "Toast the baguette slices.", assignee: .personB, timerSeconds: 240, imageSystemName: "timer"),
            RecipeStep(order: 5, instruction: "Grate the gruyère cheese.", assignee: .personB, imageSystemName: "scissors"),

            RecipeStep(order: 6, instruction: "Both: ladle into oven-safe bowls, top with bread and cheese, and broil until bubbling.", assignee: .shared, timerSeconds: 180, imageSystemName: "timer")
        ],
        iconSystemName: "cup.and.saucer.fill",
        difficulty: 3,
        soloCookTimeMinutes: 70,
        twoPersonCookTimeMinutes: 55,
        ingredients: [
            Ingredient(name: "Onions", amount: "4 large"),
            Ingredient(name: "Butter", amount: "3 tbsp"),
            Ingredient(name: "Garlic cloves", amount: "2"),
            Ingredient(name: "Flour", amount: "1 tbsp"),
            Ingredient(name: "Beef stock", amount: "4 cups"),
            Ingredient(name: "Dry sherry", amount: "2 tbsp"),
            Ingredient(name: "Thyme", amount: "A few sprigs"),
            Ingredient(name: "Baguette, sliced and toasted", amount: "4 slices"),
            Ingredient(name: "Gruyère cheese, grated", amount: "1 cup"),
            Ingredient(name: "Salt and pepper", amount: "To taste")
        ]
    )

    public static let beefAndBroccoli = Recipe(
        id: UUID(uuidString: "9E1F0A10-0018-4B7A-9C1A-000000000018")!,
        title: "Beef and Broccoli",
        summary: "Thin-sliced beef and broccoli in a glossy garlic-ginger sauce, ready faster than takeout.",
        servings: 2,
        soloSteps: [
            RecipeStep(order: 0, instruction: "Thinly slice the beef against the grain.", assignee: .solo, imageSystemName: "scissors"),
            RecipeStep(order: 1, instruction: "Whisk soy sauce, oyster sauce, brown sugar, and cornstarch into a sauce.", assignee: .solo, imageSystemName: "drop.fill"),
            RecipeStep(order: 2, instruction: "Blanch the broccoli florets until bright green and just tender.", assignee: .solo, timerSeconds: 120, imageSystemName: "timer"),
            RecipeStep(order: 3, instruction: "Heat oil in a wok over high heat.", assignee: .solo, imageSystemName: "flame.fill"),
            RecipeStep(order: 4, instruction: "Sear the beef in batches until browned.", assignee: .solo, timerSeconds: 180, imageSystemName: "timer"),
            RecipeStep(order: 5, instruction: "Add garlic and ginger and stir-fry until fragrant.", assignee: .solo, timerSeconds: 60, imageSystemName: "timer"),
            RecipeStep(order: 6, instruction: "Return the beef and broccoli to the wok and pour in the sauce.", assignee: .solo, imageSystemName: "drop.fill"),
            RecipeStep(order: 7, instruction: "Toss until the sauce thickens and everything's coated.", assignee: .solo, timerSeconds: 120, imageSystemName: "timer"),
            RecipeStep(order: 8, instruction: "Serve over rice.", assignee: .solo, imageSystemName: "fork.knife")
        ],
        twoPersonSteps: [
            RecipeStep(order: 0, instruction: "Both: gather ingredients and put rice on to cook.", assignee: .shared, imageSystemName: "flame.fill"),

            RecipeStep(order: 1, instruction: "Thinly slice the beef against the grain.", assignee: .personA, imageSystemName: "scissors"),
            RecipeStep(order: 2, instruction: "Whisk soy sauce, oyster sauce, brown sugar, and cornstarch into a sauce.", assignee: .personA, imageSystemName: "drop.fill"),
            RecipeStep(order: 3, instruction: "Heat oil in a wok and sear the beef in batches until browned.", assignee: .personA, timerSeconds: 180, imageSystemName: "timer"),

            RecipeStep(order: 4, instruction: "Blanch the broccoli florets until bright green and just tender.", assignee: .personB, timerSeconds: 120, imageSystemName: "timer"),
            RecipeStep(order: 5, instruction: "Mince the garlic and ginger.", assignee: .personB, imageSystemName: "scissors"),

            RecipeStep(order: 6, instruction: "Both: add garlic, ginger, broccoli, and sauce to the wok and toss until glossy.", assignee: .shared, timerSeconds: 150, imageSystemName: "timer"),
            RecipeStep(order: 7, instruction: "Both: serve over rice.", assignee: .shared, imageSystemName: "fork.knife")
        ],
        iconSystemName: "takeoutbag.and.cup.and.straw.fill",
        difficulty: 2,
        spiceLevel: 1,
        soloCookTimeMinutes: 30,
        twoPersonCookTimeMinutes: 22,
        ingredients: [
            Ingredient(name: "Flank steak or sirloin", amount: "400g"),
            Ingredient(name: "Broccoli florets", amount: "3 cups"),
            Ingredient(name: "Soy sauce", amount: "3 tbsp"),
            Ingredient(name: "Oyster sauce", amount: "2 tbsp"),
            Ingredient(name: "Brown sugar", amount: "1 tsp"),
            Ingredient(name: "Cornstarch", amount: "1 tbsp"),
            Ingredient(name: "Garlic cloves", amount: "3"),
            Ingredient(name: "Ginger, grated", amount: "1 tsp"),
            Ingredient(name: "Vegetable oil", amount: "2 tbsp"),
            Ingredient(name: "Cooked rice", amount: "For serving")
        ]
    )

    public static let chickenQuesadillas = Recipe(
        id: UUID(uuidString: "9E1F0A10-0019-4B7A-9C1A-000000000019")!,
        title: "Chicken Quesadillas",
        summary: "Crisp, cheesy tortillas folded over seasoned chicken — on the table in 20 minutes.",
        servings: 2,
        soloSteps: [
            RecipeStep(order: 0, instruction: "Season the chicken with cumin, chili powder, and salt.", assignee: .solo, imageSystemName: "sparkles"),
            RecipeStep(order: 1, instruction: "Heat oil in a skillet and cook the chicken until done (165°F internal temperature).", assignee: .solo, timerSeconds: 480, imageSystemName: "timer"),
            RecipeStep(order: 2, instruction: "Let the chicken rest briefly, then dice or shred it.", assignee: .solo, imageSystemName: "clock.fill"),
            RecipeStep(order: 3, instruction: "Lay a tortilla in the skillet and sprinkle cheese over half.", assignee: .solo, imageSystemName: "basket.fill"),
            RecipeStep(order: 4, instruction: "Add the chicken, bell pepper, and more cheese, then fold the tortilla over.", assignee: .solo, imageSystemName: "arrow.triangle.2.circlepath"),
            RecipeStep(order: 5, instruction: "Cook until golden and crisp, then flip and cook the other side.", assignee: .solo, timerSeconds: 180, imageSystemName: "timer"),
            RecipeStep(order: 6, instruction: "Slice into wedges and serve with salsa and sour cream.", assignee: .solo, imageSystemName: "fork.knife")
        ],
        twoPersonSteps: [
            RecipeStep(order: 0, instruction: "Both: gather ingredients.", assignee: .shared, imageSystemName: "basket.fill"),

            RecipeStep(order: 1, instruction: "Season the chicken with cumin, chili powder, and salt.", assignee: .personA, imageSystemName: "sparkles"),
            RecipeStep(order: 2, instruction: "Heat oil in a skillet and cook the chicken until done (165°F internal temperature).", assignee: .personA, timerSeconds: 480, imageSystemName: "timer"),
            RecipeStep(order: 3, instruction: "Let the chicken rest briefly, then dice or shred it.", assignee: .personA, imageSystemName: "clock.fill"),

            RecipeStep(order: 4, instruction: "Dice the bell pepper and have extra cheese ready.", assignee: .personB, imageSystemName: "scissors"),
            RecipeStep(order: 5, instruction: "Lay a tortilla in a skillet and sprinkle cheese over half.", assignee: .personB, imageSystemName: "basket.fill"),

            RecipeStep(order: 6, instruction: "Both: add the chicken, bell pepper, and more cheese, then fold the tortilla over.", assignee: .shared, imageSystemName: "arrow.triangle.2.circlepath"),
            RecipeStep(order: 7, instruction: "Both: cook until golden and crisp, then flip and cook the other side.", assignee: .shared, timerSeconds: 180, imageSystemName: "timer"),
            RecipeStep(order: 8, instruction: "Both: slice into wedges and serve with salsa and sour cream.", assignee: .shared, imageSystemName: "fork.knife")
        ],
        iconSystemName: "takeoutbag.and.cup.and.straw.fill",
        difficulty: 1,
        spiceLevel: 1,
        soloCookTimeMinutes: 20,
        twoPersonCookTimeMinutes: 14,
        ingredients: [
            Ingredient(name: "Chicken breast", amount: "1"),
            Ingredient(name: "Cumin", amount: "1 tsp"),
            Ingredient(name: "Chili powder", amount: "1 tsp"),
            Ingredient(name: "Flour tortillas", amount: "4"),
            Ingredient(name: "Shredded cheese", amount: "1.5 cups"),
            Ingredient(name: "Bell pepper, diced", amount: "1/2"),
            Ingredient(name: "Salsa", amount: "For serving"),
            Ingredient(name: "Sour cream", amount: "For serving"),
            Ingredient(name: "Salt", amount: "To taste")
        ]
    )

    public static let chocolateChipCookies = Recipe(
        id: UUID(uuidString: "9E1F0A10-0020-4B7A-9C1A-000000000020")!,
        title: "Chocolate Chip Cookies",
        summary: "Classic chewy-in-the-middle, crisp-at-the-edges chocolate chip cookies.",
        soloSteps: [
            RecipeStep(order: 0, instruction: "Cream together softened butter, brown sugar, and white sugar.", assignee: .solo, imageSystemName: "arrow.triangle.2.circlepath"),
            RecipeStep(order: 1, instruction: "Beat in the egg and vanilla extract.", assignee: .solo, imageSystemName: "drop.fill"),
            RecipeStep(order: 2, instruction: "In a separate bowl, whisk flour, baking soda, and salt.", assignee: .solo, imageSystemName: "sparkles"),
            RecipeStep(order: 3, instruction: "Fold the dry ingredients into the wet ingredients until just combined.", assignee: .solo, imageSystemName: "arrow.triangle.2.circlepath"),
            RecipeStep(order: 4, instruction: "Fold in the chocolate chips.", assignee: .solo, imageSystemName: "basket.fill"),
            RecipeStep(order: 5, instruction: "Scoop rounded portions of dough onto a lined baking sheet.", assignee: .solo, imageSystemName: "basket.fill"),
            RecipeStep(order: 6, instruction: "Bake until the edges are golden but the centers still look slightly underdone.", assignee: .solo, timerSeconds: 600, imageSystemName: "timer"),
            RecipeStep(order: 7, instruction: "Let cool on the pan for a few minutes before transferring to a rack.", assignee: .solo, imageSystemName: "clock.fill")
        ],
        twoPersonSteps: [
            RecipeStep(order: 0, instruction: "Both: preheat the oven and gather ingredients.", assignee: .shared, imageSystemName: "flame.fill"),

            RecipeStep(order: 1, instruction: "Cream together softened butter, brown sugar, and white sugar.", assignee: .personA, imageSystemName: "arrow.triangle.2.circlepath"),
            RecipeStep(order: 2, instruction: "Beat in the egg and vanilla extract.", assignee: .personA, imageSystemName: "drop.fill"),

            RecipeStep(order: 3, instruction: "Whisk flour, baking soda, and salt in a separate bowl.", assignee: .personB, imageSystemName: "sparkles"),
            RecipeStep(order: 4, instruction: "Line baking sheets with parchment paper.", assignee: .personB, imageSystemName: "basket.fill"),

            RecipeStep(order: 5, instruction: "Both: fold the dry ingredients and chocolate chips into the wet ingredients.", assignee: .shared, imageSystemName: "arrow.triangle.2.circlepath"),
            RecipeStep(order: 6, instruction: "Both: scoop rounded portions of dough onto the baking sheets.", assignee: .shared, imageSystemName: "basket.fill"),
            RecipeStep(order: 7, instruction: "Both: bake until golden at the edges, then cool before serving.", assignee: .shared, timerSeconds: 600, imageSystemName: "timer")
        ],
        iconSystemName: "rectangle.stack.fill",
        difficulty: 1,
        soloCookTimeMinutes: 30,
        twoPersonCookTimeMinutes: 22,
        dietaryTags: [.vegetarian],
        ingredients: [
            Ingredient(name: "Butter, softened", amount: "1 cup"),
            Ingredient(name: "Brown sugar", amount: "3/4 cup"),
            Ingredient(name: "White sugar", amount: "3/4 cup"),
            Ingredient(name: "Egg", amount: "1"),
            Ingredient(name: "Vanilla extract", amount: "1 tsp"),
            Ingredient(name: "Flour", amount: "2.25 cups"),
            Ingredient(name: "Baking soda", amount: "1 tsp"),
            Ingredient(name: "Salt", amount: "1/2 tsp"),
            Ingredient(name: "Chocolate chips", amount: "2 cups")
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
        tacoTuesday,
        chickenStirFry,
        beefChili,
        capreseSalad,
        bananaPancakes,
        shrimpScampi,
        vegetableFriedRice,
        chickenCaesarSalad,
        bakedSalmon,
        frenchOnionSoup,
        beefAndBroccoli,
        chickenQuesadillas,
        chocolateChipCookies
    ]
}
