"""Bake the updates dock's DECISIONS glyph: a fountain-pen nib in the standalone icons' cream.

It sits beside the bell (standalone/bell.png) in the bottom-left updates dock, so it takes the
bell's family look: the same cream, the same soft light from the top left, the same small
shadow down and to the right, and a canvas as tall as its ink so it draws at the bell's height
in a shared icon box.

    python tools/bake_pen_icon.py
    "$GODOT" --headless --path . --import
"""
from PIL import Image, ImageDraw, ImageFilter

# The cream every standalone icon is drawn in, and the bell's shading either side of it.
LIGHT = (249, 240, 219)
DARK = (234, 220, 192)
SS = 4
W, H = 330, 512
PAD_R, PAD_B = 10, 10          # room for the shadow
SHADOW = (4, 6, 3, 95)         # offset x, offset y, blur, alpha


def bezier(p0, p1, p2, n=40):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1])
            for t in (i / n for i in range(n + 1))]


def nib_mask() -> Image.Image:
    w, h = (W - PAD_R) * SS, (H - PAD_B) * SS
    cx = w / 2
    s = lambda pts: [(x * SS, y * SS) for x, y in pts]
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    iw = (W - PAD_R)
    ih = (H - PAD_B)
    mid = iw / 2
    # The section the nib sits in: a rounded band across the top.
    d.rounded_rectangle([s([(mid - 100, 0)])[0], s([(mid + 100, 58)])[0]], radius=22 * SS, fill=255)
    # The nib: square shoulders that swell out, then taper to the point.
    top, shoulder, tip = 74, 225, ih
    left = bezier((mid - 128, top), (mid - 168, 150), (mid - 142, shoulder)) \
        + bezier((mid - 142, shoulder), (mid - 70, 390), (mid, tip))[1:]
    right = [(2 * mid - x, y) for x, y in reversed(left)]
    d.polygon(s(left + right), fill=255)
    # The breather hole and the slit that runs from it to the point.
    hole_y, r = 238, 36
    d.ellipse([s([(mid - r, hole_y - r)])[0], s([(mid + r, hole_y + r)])[0]], fill=0)
    d.rectangle([s([(mid - 8, hole_y)])[0], s([(mid + 8, tip)])[0]], fill=0)
    # A thin line across the shoulders, the nib's imprint.
    d.rectangle([s([(mid - 118, 110)])[0], s([(mid + 118, 118)])[0]], fill=0)
    return m.resize((iw, ih), Image.LANCZOS)


mask = nib_mask()
iw, ih = mask.size
# Light from the top left: a diagonal ramp between the bell's two creams.
ramp = Image.new("L", (iw, ih))
ramp.putdata([int(255 * (x / iw + y / ih) / 2) for y in range(ih) for x in range(iw)])
face = Image.composite(Image.new("RGB", (iw, ih), DARK), Image.new("RGB", (iw, ih), LIGHT), ramp)

out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
dx, dy, blur, alpha = SHADOW
shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
shadow_alpha = Image.new("L", (W, H), 0)
shadow_alpha.paste(mask, (dx, dy))
shadow_alpha = shadow_alpha.filter(ImageFilter.GaussianBlur(blur)).point(lambda v: v * alpha // 255)
shadow.putalpha(shadow_alpha)
out.alpha_composite(shadow)
art = face.convert("RGBA")
art.putalpha(mask)
out.alpha_composite(art, (0, 0))
path = "assets/icons/ui_icons/standalone/fountain_pen.png"
out.save(path)
print("%s  %dx%d  ink bbox %s" % (path, W, H, out.getchannel("A").getbbox()))
