# Recipe Illustration Prompts

First-draft pass at replacing the stock hero photos (see `Scripts/fetch_recipe_photos.py`,
`Scripts/install_recipe_photo.py`) with a consistent hand-drawn illustration set, using the
locked style guide from `~/Downloads/illustration-style-guide.md`.

Three recipes to start, picked because they're the simplest (fewest, clearest steps) and already
have working hero photos to compare against: **Scrambled Eggs**, **Avocado Toast**,
**Grilled Cheese**.

## How to use these

Each file under `prompts/<slug>.md` has one entry per illustration (one hero shot + one per solo
step). Only `SUBJECT`, `HERO COLOR(S)`, and `SUPPORTING NEUTRAL` change between entries — per the
style guide's own rule ("leave every other word untouched"), paste each entry's three values into
the Master Prompt template in the style guide unchanged otherwise.

Where a prompt is marked **Reference:** attach the named locked reference image (egg-crack or
cheese-grater) alongside the prompt when you generate it — those two are your existing style
calibration images, not something generated here.

## Suggested output naming

To make wiring the results back into the app trivial, name generated files to match the step
order already in `SampleRecipes.swift`:

- Hero: `recipe-illustration-<slug>.jpg` → would replace `heroImageName` for that recipe
- Step N: `recipe-step-<slug>-<N>.jpg` → new field, doesn't exist on `RecipeStep` yet (currently
  steps only carry `imageSystemName`, an SF Symbol name — adding a real per-step illustration
  means adding an optional `stepImageName` field to `RecipeStep` and a view that prefers it over
  the SF Symbol when present, same fallback pattern `RecipeHeroImageView` already uses for the
  hero image)

## Once you have generated images back

1. Drop each into a new `.imageset` under `CookingApp/CookingApp/Resources/Assets.xcassets/`
   (same shape as the existing `recipe-photo-*.imageset` folders — single `3x` entry, no 1x/2x
   slots, per `install_recipe_photo.py`'s convention).
2. For the hero shot, swap `heroImageName` in `SampleRecipes.swift` to the new asset name.
3. For step illustrations, that needs the small model change above first — flag it and I'll wire
   it up.

## Also fixed this pass (unrelated to illustrations)

- All 8 existing `recipe-photo-*.imageset/Contents.json` files had picked up stray empty `1x`/`2x`
  slots (declared but with no filename) — reverted to the single `3x`-only format
  `install_recipe_photo.py` actually generates, which is what every one of these was originally
  committed as.
- `RecipeDetailView`'s favorite-heart toggle wasn't calling `modelContext.save()` after
  `recipe.isFavorite.toggle()`, unlike the identical toggle in `RecipeListView` — favoriting from
  the detail screen likely wasn't persisting. Fixed to match.
