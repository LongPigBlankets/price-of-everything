"""Clear the leftover card blue from the Biomass good icon (owner, 2026-08-28).

The artwork was cut from a cyan card, and the pocket enclosed by the basket's handle and its
rim survived: a flood fill from the border cannot reach a hole, so that one patch kept the
background while everything around it was keyed. On the panel navies it reads as a bright blue
chip floating in the middle of the basket.

The cyan appears nowhere else in the icon -- measured, not assumed: every pixel near it falls
inside the handle's arch -- so it is safe to key the colour globally rather than fencing off a
rectangle by hand, which would leave the fence's own edge to explain.

Alpha is FEATHERED rather than switched. The pocket is ringed by the artwork's dark outline,
and the pixels between the two are blends of the two colours; clearing only the pure ones
leaves a bright rim exactly where the eye was already drawn.

    python tools/fix_biomass_icon.py
    "$GODOT" --headless --path . --import
"""
from PIL import Image

TARGETS = [
    "assets/icons/goods/small/g_062_biomass.png",
    "assets/icons/goods/medium/g_062_biomass.png",
]
# The card colour, sampled from the pocket.
CARD = (19, 187, 250)
# Inside this distance a pixel IS the card and goes entirely.
NEAR = 90.0
# Beyond this it is artwork and is left alone. Between the two, alpha ramps.
FAR = 200.0


def distance(a, b):
    return abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])


for path in TARGETS:
    img = Image.open(path).convert("RGBA")
    px = img.load()
    cleared = 0
    softened = 0
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            d = distance((r, g, b), CARD)
            if d <= NEAR:
                px[x, y] = (r, g, b, 0)
                cleared += 1
            elif d < FAR:
                scale = (d - NEAR) / (FAR - NEAR)
                px[x, y] = (r, g, b, int(round(a * scale)))
                softened += 1
    img.save(path)
    print("%s  cleared %d, feathered %d" % (path, cleared, softened))
