"""Bake the top bar's MENU glyph so it belongs to the same family as the others.

The bar's menu button was a text "\u2630" -- flat, thin, and the one control up there that
could not carry the cream tint, the specular sheen or the hover glow, because those are
applied to a TEXTURE and a glyph is not one. This draws the same three bars as artwork, in
the family's own cream (sampled from trophy.png / open-book.png), on a canvas cropped tight
to the ink so it renders at the same visual weight as its neighbours in a fixed icon box.

    python tools/bake_menu_icon.py
    "$GODOT" --headless --path . --import
"""
from PIL import Image, ImageDraw

# The cream every other standalone icon is drawn in.
INK = (246, 234, 209, 255)
# Supersampled, then reduced -- the caps are round and 4x is the cheapest way to keep them
# from stair-stepping.
SS = 4
W, H = 512, 356
BARS = 3
BAR_H = 80
GAP = (H - BARS * BAR_H) // (BARS - 1)

img = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)
for i in range(BARS):
    top = i * (BAR_H + GAP)
    draw.rounded_rectangle(
        [0, top * SS, W * SS - 1, (top + BAR_H) * SS - 1],
        radius=(BAR_H // 2) * SS,
        fill=INK,
    )
img = img.resize((W, H), Image.LANCZOS)
out = "assets/icons/ui_icons/standalone/menu.png"
img.save(out)
box = img.getchannel("A").getbbox()
print("%s  %dx%d  ink bbox %s" % (out, W, H, box))
