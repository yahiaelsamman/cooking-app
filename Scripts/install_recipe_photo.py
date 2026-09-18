"""Installs one approved recipe-photo candidate into the app's asset catalog.

Step two of the two-step pipeline (see fetch_recipe_photos.py for step one and the rationale).
Run this once per recipe you've picked a winning candidate for — after looking at the images under
Scripts/recipe_photo_candidates/<slug>/ yourself, since stock-photo relevance needs a human call.

What it does:
  1. Center-crops the chosen image to match the app's hero aspect ratio (RecipeDetailView's header
     frame, 260x160 — roughly 13:8) so it isn't stretched/squashed at display time.
  2. Writes it into
     CookingApp/CookingApp/Resources/Assets.xcassets/Recipes/<slug>/recipe-photo-<slug>.imageset/
     (one folder per recipe, holding its hero + every step illustration together), declared at
     "3x" scale (the source is high-res enough that this avoids blur on Retina without needing to
     generate separate 1x/2x/3x files — same one-file trick used for icons).
  3. Prints the exact `heroImageName` line to add in SampleRecipes.swift — this script doesn't
     edit Swift source itself, since matching the right recipe initializer is a one-line, easy to
     double-check manual step.

Usage:
    python3 Scripts/install_recipe_photo.py <slug> <candidate-file>
    e.g. python3 Scripts/install_recipe_photo.py scrambled-eggs candidate-2.jpg
    (requires Pillow: pip install pillow)
"""
import sys
from pathlib import Path

from PIL import Image

HERO_ASPECT = 260 / 160  # RecipeDetailView's header frame
OUTPUT_WIDTH = 1200  # generous for 3x display at the header's on-screen size

SCRIPT_DIR = Path(__file__).resolve().parent
CANDIDATES_ROOT = SCRIPT_DIR / "recipe_photo_candidates"
ASSETS_ROOT = (
    SCRIPT_DIR.parent / "CookingApp" / "CookingApp" / "Resources" / "Assets.xcassets"
)

# Must match fetch_recipe_photos.py's slugs, and the recipe each corresponds to in
# CookingAppCore/Sources/CookingAppCore/SampleRecipes.swift.
SLUG_TO_RECIPE_PROPERTY = {
    "scrambled-eggs": "scrambledEggs",
    "seared-steak": "searedSteak",
    "weeknight-pasta": "pastaForTwo",
    "avocado-toast": "avocadoToast",
    "grilled-cheese": "grilledCheese",
    "tomato-soup": "tomatoSoup",
    "homemade-pizza": "pizzaNight",
    "taco-night": "tacoTuesday",
}


def center_crop_to_aspect(img: Image.Image, aspect: float) -> Image.Image:
    w, h = img.size
    current_aspect = w / h
    if current_aspect > aspect:
        new_w = int(h * aspect)
        left = (w - new_w) // 2
        return img.crop((left, 0, left + new_w, h))
    else:
        new_h = int(w / aspect)
        top = (h - new_h) // 2
        return img.crop((0, top, w, top + new_h))


def main() -> None:
    if len(sys.argv) != 3:
        print("Usage: python3 Scripts/install_recipe_photo.py <slug> <candidate-file>", file=sys.stderr)
        sys.exit(1)

    slug, candidate_file = sys.argv[1], sys.argv[2]
    if slug not in SLUG_TO_RECIPE_PROPERTY:
        print(f"Unknown slug '{slug}'. Known slugs: {', '.join(SLUG_TO_RECIPE_PROPERTY)}", file=sys.stderr)
        sys.exit(1)

    source_path = CANDIDATES_ROOT / slug / candidate_file
    if not source_path.exists():
        print(f"Not found: {source_path}", file=sys.stderr)
        sys.exit(1)

    asset_name = f"recipe-photo-{slug}"
    imageset_dir = ASSETS_ROOT / "Recipes" / slug / f"{asset_name}.imageset"
    imageset_dir.mkdir(parents=True, exist_ok=True)

    img = Image.open(source_path).convert("RGB")
    img = center_crop_to_aspect(img, HERO_ASPECT)
    if img.width > OUTPUT_WIDTH:
        new_height = int(OUTPUT_WIDTH * img.height / img.width)
        img = img.resize((OUTPUT_WIDTH, new_height), Image.LANCZOS)

    image_filename = f"{asset_name}.jpg"
    img.save(imageset_dir / image_filename, quality=88)

    contents = imageset_dir / "Contents.json"
    contents.write_text(
        '{\n'
        '  "images" : [\n'
        '    {\n'
        f'      "filename" : "{image_filename}",\n'
        '      "idiom" : "universal",\n'
        '      "scale" : "3x"\n'
        '    }\n'
        '  ],\n'
        '  "info" : {\n'
        '    "author" : "xcode",\n'
        '    "version" : 1\n'
        '  }\n'
        '}\n'
    )

    recipe_property = SLUG_TO_RECIPE_PROPERTY[slug]
    print(f"Installed {asset_name} -> {imageset_dir}")
    print(f"\nNext: in SampleRecipes.swift, add this to the `{recipe_property}` recipe's "
          f"initializer (alongside iconSystemName):")
    print(f'    heroImageName: "{asset_name}",')
    print("\nThen re-run `xcodegen generate` from CookingApp/ if this is a new imageset (asset "
          "catalogs are picked up automatically, but doesn't hurt to confirm) and rebuild.")


if __name__ == "__main__":
    main()
