"""Cuts assets/source/vegetable_sheet.png into one transparent sprite per vegetable.

Run from the project root:  python tools/slice_vegetables.py
The sheet has a flat grey background. Pixels that match it and connect to the image border
become transparent; the rest is grouped into sprites, trimmed and saved to assets/veg/.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage as ndi

ROOT = Path(__file__).resolve().parent.parent
SHEET = ROOT / "assets" / "source" / "vegetable_sheet.png"
OUT = ROOT / "assets" / "veg"
MAX_SIDE = 256
# Row-major order of the sprites on the sheet.
NAMES = [
    "potato", "broccoli", "carrot", "tomato", "onion", "pepper_red",
    "pepper_orange", "pepper_yellow", "pepper_green", "peas", "garlic", "mushrooms",
    "mushrooms_b", "celery", "pumpkin", "pumpkin_slice", "zucchini",
]


def main() -> int:
    img = Image.open(SHEET).convert("RGB")
    px = np.asarray(img).astype(np.float32)
    h, w, _ = px.shape

    border = np.concatenate([px[0], px[-1], px[:, 0], px[:, -1]])
    bg = np.median(border, axis=0)
    dist = np.sqrt(((px - bg) ** 2).sum(axis=2))
    # The background has a soft vignette, so the threshold is generous; outlines are dark.
    bg_like = dist < 38.0
    labels, _ = ndi.label(bg_like)
    edge_labels = set(np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]])))
    edge_labels.discard(0)
    background = np.isin(labels, list(edge_labels))
    fg = ~background
    fg = ndi.binary_opening(fg, iterations=2)
    fg = ndi.binary_fill_holes(fg)

    # Group pieces that belong to one sprite (e.g. a cluster of mushrooms or peas).
    grown = ndi.binary_dilation(fg, iterations=26)
    groups, count = ndi.label(grown)
    boxes = []
    for i, sl in enumerate(ndi.find_objects(groups), start=1):
        mask = (groups[sl] == i) & fg[sl]
        area = int(mask.sum())
        cy = (sl[0].start + sl[0].stop) / 2
        cx = (sl[1].start + sl[1].stop) / 2
        if area < 6000 or (cx > w * 0.92 and cy > h * 0.88):
            continue  # specks and the generator's watermark
        boxes.append((cy, cx, sl, i))
    if len(boxes) != len(NAMES):
        print(f"expected {len(NAMES)} sprites, found {len(boxes)}")
        for cy, cx, _, _ in sorted(boxes):
            print(f"  at x={cx:.0f} y={cy:.0f}")
        return 1

    # Sort into rows (by vertical band), then left to right.
    row_h = h / 3.0
    boxes.sort(key=lambda b: (int(b[0] // row_h), b[1]))

    OUT.mkdir(parents=True, exist_ok=True)
    for name, (cy, cx, sl, gid) in zip(NAMES, boxes):
        sub = px[sl]
        keep = (groups[sl] == gid) & fg[sl]
        keep = ndi.binary_erosion(keep, iterations=1)  # drops the grey anti-aliasing fringe
        alpha = Image.fromarray((keep * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
        rgba = np.dstack([sub, np.asarray(alpha)[..., None]]).astype(np.uint8)
        sprite = Image.fromarray(rgba, "RGBA")
        sprite = sprite.crop(sprite.getchannel("A").getbbox())
        scale = MAX_SIDE / max(sprite.size)
        sprite = sprite.resize((round(sprite.width * scale), round(sprite.height * scale)), Image.LANCZOS)
        # Pad so the sprite sits in a square with a little breathing room for outlines/shadows.
        side = max(sprite.size) + 8
        canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        canvas.paste(sprite, ((side - sprite.width) // 2, (side - sprite.height) // 2))
        canvas.save(OUT / f"{name}.png")
        print(f"{name:14s} {canvas.size}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
