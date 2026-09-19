"""Fetches candidate hero photos for each sample recipe from Pexels' free stock-photo API.

This is step one of a two-step, human-in-the-loop pipeline (see instructions.md): stock-photo
relevance needs a real look before it's locked in, so this script only narrows the field — it
downloads a handful of candidates per recipe into a scratch review folder, it never picks one for
you. Once you've picked a winner for a recipe, hand it to `install_recipe_photo.py` to actually
land it in the asset catalog.

Why Pexels and not Unsplash: both have free APIs with plenty of food photography, but Unsplash's
API terms require attribution plus a "download-triggered" tracking ping per photo; Pexels'
license requires neither. For a personal app with no existing credits/about screen, that's real
added complexity just to show 8 photos.

Usage:
    export PEXELS_API_KEY=your_key_here   # free at https://www.pexels.com/api/
    python3 Scripts/fetch_recipe_photos.py
    (requires requests: pip install requests)

Output: Scripts/recipe_photo_candidates/<slug>/candidate-N.jpg, plus a manifest.json per recipe
recording each candidate's photographer credit and Pexels page URL (kept for reference even though
Pexels doesn't require displaying it).
"""
import json
import os
import sys
from pathlib import Path

import requests

API_URL = "https://api.pexels.com/v1/search"
CANDIDATES_PER_RECIPE = 5
OUTPUT_ROOT = Path(__file__).resolve().parent / "recipe_photo_candidates"

# (slug, search query) — query is a plain description of the finished dish, not the recipe's full
# title (which often includes technique/serving details a photo search doesn't need).
RECIPES = [
    ("scrambled-eggs", "scrambled eggs breakfast"),
    ("seared-steak", "pan seared steak garlic butter"),
    ("weeknight-pasta", "tomato pasta spaghetti"),
    ("avocado-toast", "avocado toast fried egg"),
    ("grilled-cheese", "grilled cheese sandwich"),
    ("tomato-soup", "tomato soup bowl"),
    ("homemade-pizza", "homemade pizza"),
    ("taco-night", "tacos"),
]


def fetch_candidates(api_key: str, slug: str, query: str) -> None:
    out_dir = OUTPUT_ROOT / slug
    out_dir.mkdir(parents=True, exist_ok=True)

    response = requests.get(
        API_URL,
        headers={"Authorization": api_key},
        params={"query": query, "per_page": CANDIDATES_PER_RECIPE, "orientation": "landscape"},
        timeout=30,
    )
    response.raise_for_status()
    photos = response.json().get("photos", [])

    if not photos:
        print(f"  no results for '{query}' — try a different query in RECIPES")
        return

    manifest = []
    for i, photo in enumerate(photos, start=1):
        image_url = photo["src"]["large"]
        filename = f"candidate-{i}.jpg"
        image_response = requests.get(image_url, timeout=30)
        try:
            image_response.raise_for_status()
        except requests.HTTPError as error:
            # Without this, a 404/rate-limit response body gets written straight to disk as if
            # it were a real photo — silently "successful" until someone opens the file. Skip
            # and keep going rather than aborting the whole recipe's candidate batch over one bad
            # download.
            print(f"  skipping {filename}: {error}")
            continue
        (out_dir / filename).write_bytes(image_response.content)
        manifest.append({
            "filename": filename,
            "photographer": photo["photographer"],
            "pexels_url": photo["url"],
        })
        print(f"  saved {filename} (by {photo['photographer']})")

    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2))


def main() -> None:
    api_key = os.environ.get("PEXELS_API_KEY")
    if not api_key:
        print("Set PEXELS_API_KEY first (free key at https://www.pexels.com/api/).", file=sys.stderr)
        sys.exit(1)

    for slug, query in RECIPES:
        print(f"{slug}: searching '{query}'")
        fetch_candidates(api_key, slug, query)

    print(f"\nDone. Review candidates under {OUTPUT_ROOT}, then run install_recipe_photo.py "
          f"for whichever ones you approve.")


if __name__ == "__main__":
    main()
