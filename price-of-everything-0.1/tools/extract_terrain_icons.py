#!/usr/bin/env python3
"""Cut the six terrain glyphs out of the owner's sprite sheet and key out its navy.

The sheet (white glyphs on navy rounded tiles, labels under each) is chroma keyed by brightness: a pixel's
alpha is how far its darkest channel stands above the navy, so the glyphs keep their soft edges through the
JPEG's noise. Each glyph is trimmed to its drawn extent, padded by PAD pixels and saved white on
transparent into assets/icons/ui_icons/terrain/terrain_<type>.png, one per tile type the game uses
(tile_properties.csv: rural, urban, hill, mountain, sea, deep_sea). All six keep one scale (SCALE of the
sheet), so their sizes stay as the set was drawn: the flat land's glyph is lower than the city's.

    python3 tools/extract_terrain_icons.py artifacts/terrain_icons/terrain_icons_sheet.jpg
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parents[1] / "assets" / "icons" / "ui_icons" / "terrain"
SCALE = 0.45
PAD = 6
# The tiles in the 2000 x 1091 sheet, inset from their rounded edges; the labels sit below them.
TILES = {
    "urban": (107, 84, 668, 436),
    "hill": (754, 84, 1246, 436),
    "mountain": (1342, 84, 1903, 436),
    "rural": (96, 574, 678, 950),
    "sea": (762, 590, 1250, 950),
    "deep_sea": (1352, 590, 1904, 950),
}
# The navy's darkest channel sits near 8, the white's near 250: alpha ramps between these.
KEY_LOW = 60.0
KEY_HIGH = 210.0


def main(sheet: str) -> None:
    img = np.asarray(Image.open(sheet).convert("RGB")).astype(np.float32)
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (x0, y0, x1, y1) in TILES.items():
        tile = img[y0:y1, x0:x1]
        alpha = np.clip((tile.min(axis=2) - KEY_LOW) / (KEY_HIGH - KEY_LOW), 0.0, 1.0)
        ys, xs = np.nonzero(alpha > 0.04)
        top, bottom, left, right = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        alpha = alpha[top:bottom, left:right]
        h, w = alpha.shape
        pad = int(round(PAD / SCALE))
        canvas = np.zeros((h + 2 * pad, w + 2 * pad), np.float32)
        canvas[pad:pad + h, pad:pad + w] = alpha
        rgba = np.zeros(canvas.shape + (4,), np.uint8)
        rgba[..., :3] = 255
        rgba[..., 3] = np.round(canvas * 255).astype(np.uint8)
        out = Image.fromarray(rgba)
        out = out.resize((max(1, round(out.size[0] * SCALE)), max(1, round(out.size[1] * SCALE))), Image.LANCZOS)
        out.save(OUT / f"terrain_{name}.png")
        print(f"terrain_{name}.png {out.size[0]}x{out.size[1]} (glyph {w}x{h} in the sheet)")


if __name__ == "__main__":
    main(sys.argv[1])
