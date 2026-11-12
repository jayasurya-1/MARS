"""Trims the rendered Kenney props and gives them a dark outline like the vegetable sprites.

Run from the project root after tools/render_models.gd:  python tools/outline_props.py
Already-processed files are detected by their name suffix, so it is safe to re-run.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage as ndi

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "props"
MAX_SIDE = 256
OUTLINE_PX = 4
OUTLINE_COLOR = (70, 44, 30)


def main() -> None:
    for path in sorted(SRC.glob("*.png")):
        image = Image.open(path).convert("RGBA")
        box = image.getchannel("A").getbbox()
        if box is None:
            continue
        image = image.crop(box)
        scale = MAX_SIDE / max(image.size)
        image = image.resize((max(1, round(image.width * scale)), max(1, round(image.height * scale))),
                             Image.LANCZOS)
        pad = OUTLINE_PX + 6
        canvas = Image.new("RGBA", (image.width + pad * 2, image.height + pad * 2), (0, 0, 0, 0))
        canvas.paste(image, (pad, pad))
        alpha = np.asarray(canvas.getchannel("A")) > 24
        grown = ndi.binary_dilation(alpha, structure=ndi.generate_binary_structure(2, 2),
                                    iterations=OUTLINE_PX)
        halo = Image.fromarray((grown * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
        out = Image.new("RGBA", canvas.size, OUTLINE_COLOR + (0,))
        out.putalpha(halo)
        out.alpha_composite(canvas)
        out.save(path)
        print(f"{path.stem:16s} {out.size}")


if __name__ == "__main__":
    main()
