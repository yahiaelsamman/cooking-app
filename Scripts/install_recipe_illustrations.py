"""Installs a freshly-generated illustration set (hero + per-step) for one recipe from ChatGPT.

Third script in this project's asset pipeline (see fetch_recipe_photos.py / install_recipe_photo.py
for the original stock-photo pipeline this supersedes for hero images, and now covers steps too).
Built for the illustrations/ pipeline — prompts live in illustrations/prompts/<slug>.md, built
from illustrations/README.md's locked style guide.

Human-in-the-loop workflow:
  1. Generate images in ChatGPT using illustrations/prompts/<slug>.md, IN ORDER: the hero shot
     first, then step 0, step 1, ... step N-1. Download each one as you make it — no need to
     rename anything. ChatGPT names downloads "ChatGPT Image <date>, <time>.png"; this script
     uses download order (oldest-in-batch = hero) to figure out which is which, not the filename.
  2. Run: python3 Scripts/install_recipe_illustrations.py <slug> <step-count>
     e.g. python3 Scripts/install_recipe_illustrations.py grilled-cheese 9
  3. The script takes the (step-count + 1) most recently downloaded "ChatGPT Image*" files in
     ~/Downloads, converts each to JPEG, and writes them into
     Assets.xcassets/Recipes/<slug>/ (one folder per recipe, holding its hero + every step
     illustration together):
       - oldest of the batch -> recipe-photo-<slug>.imageset (the same slot heroImageName already
         points to — no Swift change needed for the hero)
       - the rest, in order  -> recipe-step-<slug>-0.imageset, recipe-step-<slug>-1.imageset, ...
         (new imagesets — after running this, set stepImageName: "recipe-step-<slug>-N" on the
         matching RecipeStep in SampleRecipes.swift, or just ask Claude to)
     Prints exactly what it's about to do before touching anything. Refuses to run if fewer than
     (step-count + 1) matching files exist, or if any are older than 24 hours (a safety net
     against sweeping up leftovers from a previous recipe's batch).
  4. Source files are deleted from ~/Downloads only after every image has been written
     successfully.

Usage:
    python3 Scripts/install_recipe_illustrations.py <slug> <step-count> [--dry-run]
    (requires Pillow: pip install pillow)
"""
import sys
import time
from pathlib import Path

from PIL import Image

DOWNLOADS = Path.home() / "Downloads"
SOURCE_GLOB = "ChatGPT Image*"
MAX_AGE_SECONDS = 24 * 60 * 60

SCRIPT_DIR = Path(__file__).resolve().parent
ASSETS_ROOT = (
    SCRIPT_DIR.parent / "CookingApp" / "CookingApp" / "Resources" / "Assets.xcassets"
)


def write_imageset(image_path: Path, imageset_dir: Path, filename: str) -> None:
    imageset_dir.mkdir(parents=True, exist_ok=True)
    img = Image.open(image_path).convert("RGB")
    img.save(imageset_dir / filename, quality=88)
    (imageset_dir / "Contents.json").write_text(
        '{\n'
        '  "images" : [\n'
        '    {\n'
        f'      "filename" : "{filename}",\n'
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


def main() -> None:
    args = [a for a in sys.argv[1:] if a != "--dry-run"]
    dry_run = "--dry-run" in sys.argv
    if len(args) != 2:
        print("Usage: python3 Scripts/install_recipe_illustrations.py <slug> <step-count> [--dry-run]", file=sys.stderr)
        sys.exit(1)

    slug, step_count_str = args
    try:
        step_count = int(step_count_str)
    except ValueError:
        print(f"step-count must be an integer, got {step_count_str!r}", file=sys.stderr)
        sys.exit(1)

    needed = step_count + 1
    candidates = sorted(DOWNLOADS.glob(SOURCE_GLOB), key=lambda p: p.stat().st_mtime)
    now = time.time()
    candidates = [p for p in candidates if now - p.stat().st_mtime <= MAX_AGE_SECONDS]

    if len(candidates) < needed:
        print(
            f"Found only {len(candidates)} file(s) matching '{SOURCE_GLOB}' in the last 24h "
            f"under {DOWNLOADS}, need {needed} (1 hero + {step_count} steps).",
            file=sys.stderr,
        )
        sys.exit(1)

    batch = candidates[-needed:]
    hero_src, step_srcs = batch[0], batch[1:]

    print(f"Recipe: {slug}  ({step_count} steps)\n")
    print(f"  hero   <- {hero_src.name}")
    for i, src in enumerate(step_srcs):
        print(f"  step {i:<3}<- {src.name}")

    if dry_run:
        print("\n(dry run — nothing written)")
        return

    recipe_dir = ASSETS_ROOT / "Recipes" / slug
    hero_dir = recipe_dir / f"recipe-photo-{slug}.imageset"
    write_imageset(hero_src, hero_dir, f"recipe-photo-{slug}.jpg")

    for i, src in enumerate(step_srcs):
        step_dir = recipe_dir / f"recipe-step-{slug}-{i}.imageset"
        write_imageset(src, step_dir, f"recipe-step-{slug}-{i}.jpg")

    for src in batch:
        src.unlink()

    print(f"\nWrote {needed} images and removed the originals from {DOWNLOADS}.")
    print(
        f"\nNext: add stepImageName: \"recipe-step-{slug}-N\" to each step in SampleRecipes.swift "
        f"(N = 0..{step_count - 1}), or ask Claude to."
    )


if __name__ == "__main__":
    main()
