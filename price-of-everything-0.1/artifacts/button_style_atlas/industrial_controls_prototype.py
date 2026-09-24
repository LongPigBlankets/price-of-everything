from pathlib import Path
import math

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent / "industrial_controls.png"
W, H = 1600, 900


def font(name, size):
    return ImageFont.truetype(str(ROOT / "assets/fonts" / name), size)


FONT_TITLE = font("BebasNeue-Regular.ttf", 52)
FONT_HEAD = font("BarlowCondensed-SemiBold.ttf", 28)
FONT_LABEL = font("IBMPlexSansCondensed-SemiBold.ttf", 18)
FONT_SMALL = font("IBMPlexSans-Regular.ttf", 15)
FONT_VALUE = font("IBMPlexSansCondensed-SemiBold.ttf", 44)

BG = "#03111D"
PANEL = "#071C2A"
PANEL_2 = "#0A2434"
TEXT = "#F7E7C5"
MUTED = "#B8C7D4"
LINE = "#536977"


def lerp(a, b, t):
    return tuple(round(a[i] * (1 - t) + b[i] * t) for i in range(3))


def shadow(base, box, radius, offset=(8, 10), blur=12, alpha=150):
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x0, y0, x1, y1 = box
    d.ellipse((x0 + offset[0], y0 + offset[1], x1 + offset[0], y1 + offset[1]),
              fill=(0, 0, 0, alpha))
    base.alpha_composite(layer.filter(ImageFilter.GaussianBlur(blur)))


def circle_gradient(base, center, radius, outer, inner):
    cx, cy = center
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    px = layer.load()
    x0, y0 = int(cx - radius), int(cy - radius)
    x1, y1 = int(cx + radius), int(cy + radius)
    for y in range(max(0, y0), min(base.height, y1 + 1)):
        for x in range(max(0, x0), min(base.width, x1 + 1)):
            dist = math.hypot(x - cx, y - cy)
            if dist <= radius:
                t = min(1.0, dist / radius)
                px[x, y] = (*lerp(inner, outer, t), 255)
    base.alpha_composite(layer)


def directional_circle_gradient(base, center, radius, top_left, bottom_right):
    """Fill a circle with one consistent top-left light / bottom-right shade."""
    cx, cy = center
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    px = layer.load()
    x0, y0 = int(cx - radius), int(cy - radius)
    x1, y1 = int(cx + radius), int(cy + radius)
    for y in range(max(0, y0), min(base.height, y1 + 1)):
        for x in range(max(0, x0), min(base.width, x1 + 1)):
            if math.hypot(x - cx, y - cy) <= radius:
                t = max(0.0, min(1.0, ((x - (cx - radius)) + (y - (cy - radius))) / (4.0 * radius)))
                px[x, y] = (*lerp(top_left, bottom_right, t), 255)
    base.alpha_composite(layer)


def directional_ring_gradient(base, center, outer_radius, inner_radius, top_left, bottom_right):
    """Fill a metal annulus while preserving the upper-left light direction."""
    cx, cy = center
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    px = layer.load()
    x0, y0 = int(cx - outer_radius), int(cy - outer_radius)
    x1, y1 = int(cx + outer_radius), int(cy + outer_radius)
    for y in range(max(0, y0), min(base.height, y1 + 1)):
        for x in range(max(0, x0), min(base.width, x1 + 1)):
            dist = math.hypot(x - cx, y - cy)
            if inner_radius <= dist <= outer_radius:
                t = max(0.0, min(1.0, ((x - (cx - outer_radius)) +
                                        (y - (cy - outer_radius))) / (4.0 * outer_radius)))
                px[x, y] = (*lerp(top_left, bottom_right, t), 255)
    base.alpha_composite(layer)


def rounded_gradient(base, box, radius, top_left, bottom_right):
    """Directional gradient for a raised plastic/painted component."""
    x0, y0, x1, y1 = [int(v) for v in box]
    width, height = x1 - x0, y1 - y0
    layer = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    px = layer.load()
    for y in range(height):
        for x in range(width):
            cx = max(0.0, min(1.0, (x + y) / max(1.0, width + height - 2)))
            px[x, y] = (*lerp(top_left, bottom_right, cx), 255)
    mask = Image.new("L", (width, height), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, width - 1, height - 1), radius, fill=255)
    layer.putalpha(mask)
    base.alpha_composite(layer, (x0, y0))


def metal_rim(base, center, radius):
    cx, cy = center
    shadow(base, (cx - radius, cy - radius, cx + radius, cy + radius), radius)
    # Treat the rim as one machined bezel: a rounded outside wall, a sloped
    # face, a narrow tool-cut groove, and a dark inner wall around the recess.
    directional_circle_gradient(base, center, radius, (195, 202, 204), (35, 42, 47))
    directional_ring_gradient(base, center, radius - 2, radius - 8,
                              (252, 253, 249), (118, 127, 131))
    directional_ring_gradient(base, center, radius - 8, radius - 23,
                              (169, 178, 181), (64, 73, 78))
    # A thin dark groove is what separates the bevel from the inner wall;
    # without it the part looks like painted concentric bands.
    directional_ring_gradient(base, center, radius - 23, radius - 28,
                              (71, 80, 84), (18, 24, 28))
    directional_ring_gradient(base, center, radius - 28, radius - 42,
                              (103, 112, 116), (28, 34, 38))
    recess_radius = radius - 42
    directional_circle_gradient(base, center, recess_radius, (26, 33, 38), (11, 16, 20))
    d = ImageDraw.Draw(base)
    outer = (cx - radius + 2, cy - radius + 2, cx + radius - 2, cy + radius - 2)
    inner = (cx - recess_radius, cy - recess_radius, cx + recess_radius, cy + recess_radius)
    # These are directional edge breaks, not full outlines: the upper-left
    # catches the light while the lower-right turns into the shadowed metal.
    d.arc(outer, start=182, end=286, fill="#F8FAF7", width=2)
    d.arc(outer, start=4, end=112, fill="#252D32", width=4)
    cap = (cx - radius + 8, cy - radius + 8, cx + radius - 8, cy + radius - 8)
    d.arc(cap, start=188, end=270, fill="#D8DFE0", width=2)
    d.arc(cap, start=8, end=104, fill="#4A555A", width=2)
    # A crisp contact line and a softer lower-right occlusion make the cavity
    # read as cut into the metal housing.
    d.ellipse(inner, outline="#0B1013", width=2)
    d.arc(inner, start=184, end=292, fill="#AAB4B8", width=2)
    d.arc(inner, start=0, end=116, fill="#05090B", width=5)


def draw_switch(base, center, radius):
    cx, cy = center
    metal_rim(base, center, radius)
    # Molded plastic face: soft upper-left reflection, cool grey lower-right shade.
    face_radius = radius - 55
    shadow(base, (cx - face_radius, cy - face_radius, cx + face_radius, cy + face_radius),
           face_radius, offset=(3, 7), blur=7, alpha=145)
    directional_circle_gradient(base, center, face_radius, (250, 252, 251), (137, 149, 158))
    d = ImageDraw.Draw(base)
    d.ellipse((cx - face_radius, cy - face_radius, cx + face_radius, cy + face_radius),
              outline="#30373B", width=2)
    d.arc((cx - face_radius + 3, cy - face_radius + 3, cx + face_radius - 3, cy + face_radius - 3),
          start=190, end=315, fill="#FFFFFF", width=3)
    d.arc((cx - face_radius + 3, cy - face_radius + 3, cx + face_radius - 3, cy + face_radius - 3),
          start=15, end=110, fill="#76838A", width=3)

    # Three discrete detents for the switch. The lever is parked on AUTO.
    lever_w = 68
    lever_top = cy - radius + 13
    lever_bottom = cy + radius - 10
    shadow(base, (cx - lever_w / 2, lever_top, cx + lever_w / 2, lever_bottom), 8,
           offset=(7, 10), blur=10, alpha=125)
    rounded_gradient(base, (cx - lever_w / 2, lever_top, cx + lever_w / 2, lever_bottom),
                     8, (255, 255, 253), (159, 169, 177))
    d.rounded_rectangle((cx - lever_w / 2, lever_top, cx + lever_w / 2, lever_bottom),
                        radius=8, outline="#66737A", width=2)
    d.line((cx - lever_w / 2 + 6, lever_top + 5, cx + lever_w / 2 - 6, lever_top + 5),
           fill="#FFFFFF", width=3)
    d.ellipse((cx - 10, cy - 34, cx + 10, cy - 14), fill="#C64242", outline="#702B2B", width=2)
    d.rounded_rectangle((cx - lever_w / 2 + 5, lever_bottom - 9, cx + lever_w / 2 - 5, lever_bottom + 2),
                        radius=3, fill="#171D21")

    for label, x in (("OFF", cx - radius - 18), ("AUTO", cx), ("MAX", cx + radius + 18)):
        bbox = d.textbbox((0, 0), label, font=FONT_LABEL)
        d.text((x - (bbox[2] - bbox[0]) / 2, cy + radius + 30), label,
               font=FONT_LABEL, fill=TEXT)
    lightning = [(cx - 8, cy - radius - 50), (cx + 3, cy - radius - 50),
                 (cx - 4, cy - radius - 37), (cx + 8, cy - radius - 37),
                 (cx - 9, cy - radius - 20), (cx - 2, cy - radius - 34),
                 (cx - 12, cy - radius - 34)]
    d.line(lightning + [lightning[0]], fill="#CBD4D9", width=3, joint="curve")
    d.text((cx - 9, cy - radius - 78), "I", font=FONT_HEAD, fill="#E35353")


def draw_gauge(base, center, radius, value=68):
    cx, cy = center
    metal_rim(base, center, radius)
    face_radius = radius - 55
    shadow(base, (cx - face_radius, cy - face_radius, cx + face_radius, cy + face_radius),
           face_radius, offset=(3, 7), blur=7, alpha=155)
    directional_circle_gradient(base, center, face_radius, (76, 88, 94), (14, 20, 25))
    d = ImageDraw.Draw(base)
    inner = face_radius - 5
    d.ellipse((cx - inner, cy - inner, cx + inner, cy + inner), outline="#10171B", width=2)

    # Threshold bands on a -135°..135° sweep.
    start, end = -135, 135
    for a0, a1, color in ((-135, -15, "#4E9A67"), (-15, 65, "#D6A74E"), (65, 135, "#B84B4B")):
        d.arc((cx - inner + 10, cy - inner + 10, cx + inner - 10, cy + inner - 10),
              start=a0 - 90, end=a1 - 90, fill=color, width=10)

    # Tick marks and numerals.
    for i in range(11):
        angle = math.radians(start + (end - start) * i / 10 - 90)
        outer = inner - 14
        tick = inner - (34 if i % 5 == 0 else 25)
        x0, y0 = cx + math.cos(angle) * outer, cy + math.sin(angle) * outer
        x1, y1 = cx + math.cos(angle) * tick, cy + math.sin(angle) * tick
        d.line((x0, y0, x1, y1), fill="#E6ECEC", width=3 if i % 5 == 0 else 2)

    # Black needle, with a cast shadow falling down-right from the raised arm.
    angle = math.radians(start + (end - start) * value / 100 - 90)
    tip = inner - 54
    needle_shadow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(needle_shadow)
    shadow_offset = (7, 9)
    sx, sy = cx + shadow_offset[0], cy + shadow_offset[1]
    sd.line((sx, sy, sx + math.cos(angle) * tip, sy + math.sin(angle) * tip),
            fill=(0, 0, 0, 150), width=10)
    base.alpha_composite(needle_shadow.filter(ImageFilter.GaussianBlur(6)))
    d.line((cx, cy, cx + math.cos(angle) * tip, cy + math.sin(angle) * tip),
           fill="#050708", width=8)
    d.polygon([(cx + math.cos(angle + math.pi / 2) * 7, cy + math.sin(angle + math.pi / 2) * 7),
               (cx + math.cos(angle) * (tip + 16), cy + math.sin(angle) * (tip + 16)),
               (cx + math.cos(angle - math.pi / 2) * 7, cy + math.sin(angle - math.pi / 2) * 7)],
              fill="#050708")
    d.ellipse((cx - 15, cy - 15, cx + 15, cy + 15), fill="#0A0D0F", outline="#D9B24C", width=3)
    text = f"{value}%"
    bbox = d.textbbox((0, 0), text, font=FONT_VALUE)
    d.text((cx - (bbox[2] - bbox[0]) / 2, cy + 54), text, font=FONT_VALUE, fill=TEXT)


def main():
    img = Image.new("RGBA", (W, H), BG)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((34, 28, W - 34, H - 28), 28, fill=PANEL,
                        outline="#6B7D86", width=2)
    d.text((76, 64), "INDUSTRIAL CONTROL PROTOTYPES", font=FONT_TITLE, fill=TEXT)
    d.text((78, 124), "Rotary switch / metal-rim gauge / discrete state and continuous value", font=FONT_SMALL, fill=MUTED)
    d.line((76, 164, W - 76, 164), fill=LINE, width=2)

    cards = [(80, 205, 720, 810, "ROTARY SWITCH", "Discrete mode selector / snap to OFF · AUTO · MAX"),
             (880, 205, 1520, 810, "INDUSTRIAL GAUGE", "Continuous value / thresholds / black needle")]
    for x0, y0, x1, y1, title, note in cards:
        d.rounded_rectangle((x0, y0, x1, y1), 18, fill=PANEL_2, outline="#334B58", width=2)
        d.text((x0 + 28, y0 + 24), title, font=FONT_HEAD, fill=TEXT)
        d.text((x0 + 28, y0 + 64), note, font=FONT_SMALL, fill=MUTED)

    draw_switch(img, (400, 485), 190)
    draw_gauge(img, (1200, 485), 190, value=68)

    d.line((76, H - 55, W - 76, H - 55), fill=LINE, width=1)
    d.text((78, H - 42), "Prototype only — controls should be custom-drawn Godot Controls, not flattened images.",
           font=FONT_SMALL, fill=MUTED)
    img.convert("RGB").save(OUT, quality=96)
    print(OUT)


if __name__ == "__main__":
    main()
