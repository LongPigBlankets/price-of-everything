from pathlib import Path
import math
from PIL import Image, ImageColor, ImageDraw, ImageFont, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent / "button_style_atlas.png"
W, H = 1800, 1160


def font(name: str, size: int):
    return ImageFont.truetype(str(ROOT / "assets/fonts" / name), size)


FONT_TITLE = font("BebasNeue-Regular.ttf", 54)
FONT_HEAD = font("BarlowCondensed-SemiBold.ttf", 30)
FONT_LABEL = font("IBMPlexSansCondensed-SemiBold.ttf", 21)
FONT_SMALL = font("IBMPlexSans-Regular.ttf", 17)
FONT_TINY = font("IBMPlexSans-Regular.ttf", 14)

BG = "#03111D"
PANEL = "#071C2A"
PANEL_2 = "#0A2434"
TEXT = "#F7E7C5"
MUTED = "#B8C7D4"
LINE = "#536977"


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=255)
    return m


def shadow(base, box, radius=18, offset=(8, 10), blur=8, alpha=150):
    x0, y0, x1, y1 = box
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle((x0 + offset[0], y0 + offset[1], x1 + offset[0], y1 + offset[1]), radius,
                        fill=(0, 0, 0, alpha))
    base.alpha_composite(layer.filter(ImageFilter.GaussianBlur(blur)))


def gradient_rect(base, box, top, bottom, radius=18, border=None, border_w=2):
    x0, y0, x1, y1 = box
    width, height = int(x1 - x0), int(y1 - y0)
    mask = rounded_mask((width, height), radius)
    grad = Image.new("RGBA", (width, height))
    pix = grad.load()
    tr, tg, tb, ta = ImageColor.getcolor(top, "RGBA")
    br, bg, bb, ba = ImageColor.getcolor(bottom, "RGBA")
    for y in range(height):
        t = y / max(1, height - 1)
        c = (int(tr * (1 - t) + br * t), int(tg * (1 - t) + bg * t),
             int(tb * (1 - t) + bb * t), int(ta * (1 - t) + ba * t))
        for x in range(width):
            pix[x, y] = c
    grad.putalpha(mask)
    base.alpha_composite(grad, (int(x0), int(y0)))
    if border:
        ImageDraw.Draw(base).rounded_rectangle(box, radius, outline=border, width=border_w)


def paste_icon(base, path, center, size, tint=None):
    icon = Image.open(ROOT / path).convert("RGBA")
    icon.thumbnail((size, size), Image.Resampling.LANCZOS)
    if tint:
        r, g, b = tint
        alpha = icon.getchannel("A")
        icon = Image.new("RGBA", icon.size, (r, g, b, 255))
        icon.putalpha(alpha)
    base.alpha_composite(icon, (int(center[0] - icon.width / 2), int(center[1] - icon.height / 2)))


def paste_layer(base, path, center, size, tint=None, alpha_scale=1.0):
    layer = Image.open(ROOT / path).convert("RGBA")
    layer.thumbnail((size, size), Image.Resampling.LANCZOS)
    if tint or alpha_scale != 1.0:
        r, g, b = tint if tint else (255, 255, 255)
        alpha = layer.getchannel("A")
        if alpha_scale != 1.0:
            alpha = alpha.point(lambda value: int(value * alpha_scale))
        layer = Image.new("RGBA", layer.size, (r, g, b, 255))
        layer.putalpha(alpha)
    base.alpha_composite(layer, (int(center[0] - layer.width / 2), int(center[1] - layer.height / 2)))


def off_white_radius(path):
    """Return the furthest visible off-white pixel from the icon's centre."""
    icon = Image.open(ROOT / path).convert("RGBA")
    cx = (icon.width - 1) / 2.0
    cy = (icon.height - 1) / 2.0
    furthest = 0.0
    for y in range(icon.height):
        for x in range(icon.width):
            r, g, b, a = icon.getpixel((x, y))
            if a < 128 or min(r, g, b) < 120 or max(r, g, b) - min(r, g, b) > 100:
                continue
            furthest = max(furthest, math.hypot(x - cx, y - cy))
    return furthest


def market_icon_size(button_diameter, ring_width):
    """Fit the object so its gap to the ring stays between 5px and 20px."""
    source_radius = off_white_radius("assets/icons/ui_icons/alt/market_object.png")
    inner_radius = button_diameter / 2.0 - ring_width
    # Aim for a comfortable midpoint, then clamp against the explicit bounds.
    target_gap = 3.0
    min_size = math.ceil((inner_radius - 20.0) * 256.0 / source_radius)
    max_size = math.floor((inner_radius - target_gap) * 256.0 / source_radius)
    target_size = round((inner_radius - target_gap) * 256.0 / source_radius)
    return max(min_size, min(max_size, target_size))


def text_center(draw, xy, value, fnt, fill):
    box = draw.textbbox((0, 0), value, font=fnt)
    draw.text((xy[0] - (box[2] - box[0]) / 2, xy[1] - (box[3] - box[1]) / 2), value,
              font=fnt, fill=fill)


def bottom_button(base, box, state):
    x0, y0, x1, y1 = box
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    if state == "pressed":
        y0 += 7; y1 += 7; cy += 7
    shadow(base, (x0, y0, x1, y1), radius=90, offset=(4, 5), blur=5, alpha=145)
    bg = {"normal": "#235B3C", "hover": "#34734F", "pressed": "#1B472F"}[state]
    ring = "#E4EFCF"
    ImageDraw.Draw(base).ellipse((x0, y0, x1, y1), fill=bg, outline=ring, width=6)
    if state == "hover":
        paste_layer(base, "assets/icons/ui_icons/alt/_glow_market_clean.png", (cx, cy), x1 - x0,
                    tint=(126, 190, 151), alpha_scale=0.55)
    # The circular bevel is a separate surface layer, behind the object.
    paste_layer(base, "assets/icons/ui_icons/alt/market_bevel.png", (cx, cy), x1 - x0)
    # The market artwork is now the separated arrow/banknote object layer. The
    # circular surface and outer ring belong to the button itself.
    paste_icon(base, "assets/icons/ui_icons/alt/market_object.png", (cx, cy),
               market_icon_size(x1 - x0, 6))


def ds_button(base, box, state):
    x0, y0, x1, y1 = box
    if state == "pressed":
        y0 += 5; y1 += 5
    shadow(base, (x0, y0, x1, y1), radius=16, offset=(7, 8), blur=7, alpha=155)
    colors = {
        "normal": ("#B9D7E1", "#4E7A8E"),
        "hover": ("#D7EDF1", "#6F9BAA"),
        "pressed": ("#7B9EAC", "#345868"),
    }[state]
    gradient_rect(base, (x0, y0, x1, y1), colors[0], colors[1], radius=12, border="#F7E7C5", border_w=3)
    # The DS style is text-led; this icon is deliberately secondary.
    paste_icon(base, "assets/icons/ui_icons/input_status_icon.png", ((x0 + x1) / 2, y0 + 46), 38, tint=(247, 231, 197))
    text_center(ImageDraw.Draw(base), ((x0 + x1) / 2, y0 + 101), "LOGISTICS SETTINGS", FONT_LABEL, "#03111D")


def keyboard_button(base, box, state):
    x0, y0, x1, y1 = box
    if state == "pressed":
        y0 += 7; y1 += 7

    # Topology mapped from the supplied reference: a light outer cap, a broad
    # bevel, and a large recessed rounded-square face. The previous prototype
    # added a dark chassis and circular well; those layers do not exist in the
    # reference and made the centred icon look boxed-in.
    shadow(base, (x0, y0, x1, y1), radius=28, offset=(9, 11), blur=9, alpha=175)
    gradient_rect(base, (x0, y0, x1, y1), "#FAF9F5", "#B4B0A9", radius=28, border="#6E7377", border_w=2)
    inner = (x0 + 38, y0 + 38, x1 - 38, y1 - 38)
    inner_shadow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ImageDraw.Draw(inner_shadow).rounded_rectangle(
        (inner[0], inner[1] + 7, inner[2], inner[3] + 7), 34, fill=(53, 52, 49, 105)
    )
    base.alpha_composite(inner_shadow.filter(ImageFilter.GaussianBlur(7)))
    face_top, face_bottom = {
        "normal": ("#F4F1EA", "#D2CDC4"),
        "hover": ("#FFFDF7", "#E0DCD3"),
        "pressed": ("#D8D3CA", "#A6A39D"),
    }[state]
    gradient_rect(base, inner, face_top, face_bottom, radius=34, border="#D9D6D0", border_w=1)

    # The reference has a soft top-left highlight and a heavier lower-right
    # bevel. Keep these as two short edge glints rather than a separate icon
    # container, so the centred symbol sits directly on the key face.
    d = ImageDraw.Draw(base)
    d.line((inner[0] + 20, inner[1] + 10, inner[2] - 22, inner[1] + 10),
           fill=(255, 255, 252, 180), width=3)
    d.line((inner[0] + 18, inner[3] - 10, inner[2] - 20, inner[3] - 10),
           fill=(116, 110, 101, 105), width=3)

    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    # The icon is centred on the inner face with no circle, plate, or extra
    # rectangular bevel around it. This uses the existing logistics lorry glyph
    # so the prototype tests the real icon proportions in the new topology.
    icon_color = (48, 56, 57) if state != "pressed" else (246, 234, 206)
    paste_icon(base, "assets/icons/ui_icons/route_lorry.png", (cx, cy), 104, tint=icon_color)


def main():
    img = Image.new("RGBA", (W, H), BG)
    d = ImageDraw.Draw(img)
    # Outer panel and header rule.
    d.rounded_rectangle((34, 28, W - 34, H - 28), 28, fill=PANEL, outline="#6B7D86", width=2)
    d.text((76, 64), "BUTTON STYLE ATLAS", font=FONT_TITLE, fill=TEXT)
    d.text((78, 124), "Current menu modules  /  DS main buttons  /  keyboard-style skeuomorphic prototype", font=FONT_SMALL, fill=MUTED)
    d.line((76, 164, W - 76, 164), fill=LINE, width=2)

    columns = [(80, 560, "CURRENT BOTTOM MENU", "Single surface / separated object layer"),
               (650, 1130, "DS MAIN BUTTON", "Generated steel bevel / text-led CTA"),
               (1220, 1700, "NEW KEYBOARD STYLE", "Keycap chassis / centered icon")]
    for x0, x1, head, sub in columns:
        d.rounded_rectangle((x0, 195, x1, H - 78), 18, fill=PANEL_2, outline="#334B58", width=2)
        text_center(d, ((x0 + x1) / 2, 229), head, FONT_HEAD, TEXT)
        text_center(d, ((x0 + x1) / 2, 264), sub, FONT_TINY, MUTED)

    states = [("NORMAL", "normal"), ("HOVER", "hover"), ("PRESSED / ACTIVE", "pressed")]
    for i, (label, state) in enumerate(states):
        y = 310 + i * 230
        d.text((102, y + 74), label, font=FONT_TINY, fill=MUTED)
        bottom_button(img, (260, y, 430, y + 170), state)
        ds_button(img, (750, y + 18, 1030, y + 151), state)
        keyboard_button(img, (1325, y - 5, 1595, y + 175), state)

    d.line((76, H - 55, W - 76, H - 55), fill=LINE, width=1)
    d.text((78, H - 42), "Prototype only — no game scene or theme code changed.", font=FONT_TINY, fill=MUTED)
    img.convert("RGB").save(OUT, quality=96)
    print(OUT)


if __name__ == "__main__":
    main()
