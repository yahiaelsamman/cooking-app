# Recipe illustrations

Prompts used to generate the step-by-step illustrations for **Scrambled Eggs**, **Avocado
Toast**, and **Grilled Cheese** (AI-generated, in a consistent hand-drawn style). Each file in
`prompts/` has one entry for the hero image and one per solo step, in step order. Only
`SUBJECT`, `HERO COLOR(S)`, and `SUPPORTING NEUTRAL` change between entries; they plug into a
master style prompt that isn't included in this repo. Where an entry is marked **Reference:**,
the named style-calibration image was attached alongside the prompt.

The other recipes don't have illustrations yet — their steps fall back to an SF Symbol
placeholder card, and their hero is either a stock photo or the same placeholder.

## Adding a set for another recipe

1. Generate the images in order: the hero first, then step 0 … N-1.
2. Run `python3 Scripts/install_recipe_illustrations.py <slug> <step-count>`. It writes the hero
   to `recipe-photo-<slug>` (the slot `heroImageName` already points to) and each step to
   `recipe-step-<slug>-<N>` under `Assets.xcassets/Recipes/<slug>/`.
3. Set `stepImageName: "recipe-step-<slug>-N"` on each matching step in `SampleRecipes.swift`.
   `StepIllustrationView` shows it in place of the SF Symbol placeholder.
