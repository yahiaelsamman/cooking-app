"""Regenerates the Cooking App icon.

No image-generation tool was available when this was first written, so the icon is drawn by hand
with Pillow rather than being real designed art: a warm diagonal gradient background with a
stylized frying pan + fried egg (a solid disc, not a ring — an earlier attempt at a ring read as a
magnifying glass instead of a pan). Treat this purely as a placeholder generator, not a design
tool — swap in real branding whenever you have it, by just replacing the PNG this writes.

Usage: python3 Scripts/generate_app_icon.py
(requires Pillow: pip install pillow)
"""
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024
OUTPUT_PATH = (
    Path(__file__).resolve().parent.parent
    / "CookingApp" / "CookingApp" / "Resources" / "Assets.xcassets"
    / "AppIcon.appiconset" / "icon-1024.png"
)


def main() -> None:
    img = Image.new("RGB", (SIZE, SIZE))
    px = img.load()

    top_left = (255, 158, 68)      # warm orange
    bottom_right = (214, 64, 44)   # deep red-orange

    for y in range(SIZE):
        for x in range(SIZE):
            t = (x + y) / (2 * SIZE)
            r = int(top_left[0] + (bottom_right[0] - top_left[0]) * t)
            g = int(top_left[1] + (bottom_right[1] - top_left[1]) * t)
            b = int(top_left[2] + (bottom_right[2] - top_left[2]) * t)
            px[x, y] = (r, g, b)

    draw = ImageDraw.Draw(img, "RGBA")

    cx, cy = SIZE * 0.44, SIZE * 0.50
    pan_radius = SIZE * 0.27

    # Soft shadow beneath the whole pan+handle group.
    draw.ellipse(
        [cx - pan_radius * 1.15, cy - pan_radius * 0.4, cx + pan_radius * 1.3, cy + pan_radius * 1.25],
        fill=(0, 0, 0, 45),
    )

    # Handle first (so the pan disc draws on top of its base and hides the seam).
    handle_h = pan_radius * 0.42
    handle_len = SIZE * 0.30
    handle_x0 = cx + pan_radius * 0.55
    handle_y0 = cy - handle_h / 2
    draw.rounded_rectangle(
        [handle_x0, handle_y0, handle_x0 + handle_len, handle_y0 + handle_h],
        radius=handle_h / 2,
        fill=(255, 250, 244, 255),
    )

    # Pan body — a solid dark disc (the cooking surface) with a thin cream rim.
    rim_width = pan_radius * 0.10
    draw.ellipse(
        [cx - pan_radius, cy - pan_radius, cx + pan_radius, cy + pan_radius],
        fill=(255, 250, 244, 255),
    )
    inner_radius = pan_radius - rim_width
    draw.ellipse(
        [cx - inner_radius, cy - inner_radius, cx + inner_radius, cy + inner_radius],
        fill=(120, 58, 40, 255),  # dark seared-pan brown
    )

    # Fried egg on the pan surface.
    egg_w, egg_h = inner_radius * 1.35, inner_radius * 1.05
    draw.ellipse(
        [cx - egg_w * 0.5, cy - egg_h * 0.5, cx + egg_w * 0.5, cy + egg_h * 0.5],
        fill=(255, 250, 244, 240),
    )
    yolk_r = inner_radius * 0.34
    draw.ellipse(
        [cx - yolk_r, cy - yolk_r, cx + yolk_r, cy + yolk_r],
        fill=(255, 179, 71, 255),
    )
    # A small highlight on the yolk for a touch of dimension.
    hl_r = yolk_r * 0.32
    draw.ellipse(
        [cx - yolk_r * 0.35 - hl_r, cy - yolk_r * 0.35 - hl_r, cx - yolk_r * 0.35 + hl_r, cy - yolk_r * 0.35 + hl_r],
        fill=(255, 220, 170, 200),
    )

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUTPUT_PATH)
    print(f"wrote {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
