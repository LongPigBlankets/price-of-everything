"""Re-cut the Power good icon from the isometric artwork (owner, 2026-08-28).

The shipped icon is a flat bolt; the replacement is the isometric one, supplied on a solid
magenta card. This keys that background out, trims to the ink, and writes the three sizes the
goods pipeline expects, matching the existing files' aspect and dimensions so nothing
downstream has to change.

    python tools/bake_power_icon.py
    "$GODOT" --headless --path . --import
"""
from PIL import Image
import sys

SRC = "C:/Users/urigi/Downloads/Gemini_Generated_Image_lwsrjalwsrjalwsr.jfif"
# (directory, long-side height) -- the sizes already on disk for this good.
TARGETS = [("very_small", 64), ("small", 450), ("medium", 1865)]
# The card is a magenta HALFTONE, not a flat fill: its dots run from about (134, 14, 88) to
# (177, 33, 115), which a single sampled colour plus a small tolerance does not cover -- the
# first attempt keyed the flat areas and kept every dot, so the trim found nothing to trim.
# The test is the hue instead: strongly red-dominant, green far below both other channels.
BG_MIN = (120, 0, 70)
BG_MAX = (195, 55, 130)

img = Image.open(SRC).convert("RGBA")
w, h = img.size
px = img.load()

def is_card(r, g, b):
    return (BG_MIN[0] <= r <= BG_MAX[0] and BG_MIN[1] <= g <= BG_MAX[1]
            and BG_MIN[2] <= b <= BG_MAX[2] and g < r and g < b)

out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
op = out.load()
for y in range(h):
    for x in range(w):
        r, g, b, _ = px[x, y]
        if is_card(r, g, b):
            continue
        op[x, y] = (r, g, b, 255)

box = out.getchannel("A").getbbox()
if box is None:
    sys.exit("bake_power_icon: nothing survived the key -- check TOLERANCE")
glyph = out.crop(box)
print("keyed the card -> ink %dx%d" % (glyph.width, glyph.height))

for folder, tall in TARGETS:
    wide = max(1, int(round(glyph.width * tall / glyph.height)))
    path = "assets/icons/goods/%s/g_010_power.png" % folder
    glyph.resize((wide, tall), Image.LANCZOS).save(path)
    print("%s  %dx%d" % (path, wide, tall))
