"""Paper WPA Catalog: the final paper effect for the supply chain view's catalogue plates.

Takes a building rendered on a transparent background (tools/supply_chain_3d/catalog_plate.tscn)
and prints it onto an aged catalogue sheet:

  * ink and paper instead of black and white: the darkest tones land on a blue-black ink
    (#1f2b36), the lightest on cream stock (#ece0c6); mid tones keep their hue, near-neutrals
    soften toward print while strong accents keep (and gain) their colour;
  * paper: large soft mottling, horizontal fibres, a fine tooth, worn edges;
  * ink grain where coverage is thin (mid tones), none on solid ink or bare paper;
  * the dark key layer printed two pixels off register;
  * a soft shadow cast up the sheet at 11 o'clock (the sun stands south-east);
  * a ruled border and spaced lettering: plate number, title, subtitle, imprint.

Map sheets (`--map`) print a whole supply chain view capture instead: the landscape is muted to
sage and slate with the sea kept blue and roofs as accents, inside a neat line with a chequered
border, with place labels, a compass and a one-tile scale bar taken from the capture log of
tools/supply_chain_3d/review_colour.tscn (its [LABEL], [NORTH] and [TILEPX] lines).

Offline only for now: the game does not draw this effect yet.

  python3 tools/supply_chain_3d/paper_wpa_catalog.py <render.png> <plate.png> \\
      --title "INDUSTRIAL GOODS FACTORY" --subtitle "LEVEL III  ·  SAWTOOTH HALLS" --number 14
  python3 tools/supply_chain_3d/paper_wpa_catalog.py --map <capture.png> <sheet.png> --log <run.log> \\
      --title STONESHORE --subtitle "TOWN, OLD QUARTER AND DOCKS" --number 4 --feature tile_4_9

Needs numpy, scipy and Pillow. Fonts: Futura and Gill Sans from macOS's supplemental set.
"""
import argparse

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi

INK_RGB = np.array([0x1f, 0x2b, 0x36]) / 255
PAPER_RGB = np.array([0xec, 0xe0, 0xc6]) / 255
ACCENT_RGB = (0xa4, 0x43, 0x2f)
FUTURA = "/System/Library/Fonts/Supplemental/Futura.ttc"
GILL_SANS = "/System/Library/Fonts/Supplemental/GillSans.ttc"
# Texture strengths. Grain (tooth, fibres, ink grain) was cut 35% from the first plates.
MOTTLE, FIBRE, TOOTH = 0.022, 0.0039, 0.0065
INK_FIBRE, INK_GRAIN = 0.0078, 0.0195
SHEET = (1400, 1800)
BUILDING_WIDTH = 1000


def _linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def to_oklab(rgb):
    m1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929], [0.2119034982, 0.6806995451, 0.1073969566],
                   [0.0883024619, 0.2817188376, 0.6299787005]])
    m2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468], [1.9779984951, -2.4285922050, 0.4505937099],
                   [0.0259040371, 0.7827717662, -0.8086757660]])
    # Explicit contraction avoids spurious Accelerate/BLAS FP exceptions on
    # strided RGB views. This is mathematically identical to the plate original.
    return np.einsum('...j,ij->...i', np.cbrt(np.maximum(np.einsum('...j,ij->...i', _linear(rgb), m1), 0)), m2)


def from_oklab(lab):
    m2i = np.array([[1, 0.3963377774, 0.2158037573], [1, -0.1055613458, -0.0638541728],
                    [1, -0.0894841775, -1.2914855480]])
    m1i = np.array([[4.0767416621, -3.3077115913, 0.2309699292], [-1.2684380046, 2.6097574011, -0.3413193965],
                    [-0.0041960863, -0.7034186147, 1.7076147010]])
    return _srgb(np.einsum('...j,ij->...i', np.einsum('...j,ij->...i', lab, m2i) ** 3, m1i))


INK, PAPER = to_oklab(INK_RGB), to_oklab(PAPER_RGB)


def printed(rgb):
    """Map rendered colour onto ink and paper: the tone range runs ink -> paper, near-neutral
    mid tones soften, strong accents keep their colour, a faint warm cast of aged stock."""
    lab = to_oklab(rgb)
    lightness, a, b = lab[..., 0], lab[..., 1], lab[..., 2]
    l2 = INK[0] + (PAPER[0] - INK[0]) * np.clip((lightness - 0.24) / (0.84 - 0.24), 0, 1)
    t = np.clip((l2 - INK[0]) / (PAPER[0] - INK[0]), 0, 1)
    toward_paper = np.clip((t - 0.74) / 0.26, 0, 1) ** 1.5
    toward_ink = np.clip((0.22 - t) / 0.22, 0, 1)
    accent = np.clip((np.hypot(a, b) - 0.035) / 0.05, 0, 1)
    keep = (0.92 + 0.43 * accent) * (1 - toward_paper) * (1 - toward_ink)
    a2 = a * keep + PAPER[1] * toward_paper + INK[1] * toward_ink
    b2 = b * keep + PAPER[2] * toward_paper + INK[2] * toward_ink + 0.008
    return np.clip(from_oklab(np.stack([l2, a2, b2], -1)), 0, 1)


def _hue_weight(h, centre, width):
    d = np.abs((h - centre + 180) % 360 - 180)
    x = np.clip(1 - d / width, 0, 1)
    return x * x * (3 - 2 * x)


def printed_map(rgb):
    """The landscape as a print: ink to paper over a gentler range than a building plate,
    grass muted toward sage, the sea kept blue, warm roofs and brick kept as accents."""
    lab = to_oklab(rgb)
    lightness, a, b = lab[..., 0], lab[..., 1], lab[..., 2]
    hue = np.degrees(np.arctan2(b, a)) % 360
    l2 = INK[0] + (PAPER[0] - INK[0]) * np.clip((lightness - 0.20) / (0.90 - 0.20), 0, 1)
    t = np.clip((l2 - INK[0]) / (PAPER[0] - INK[0]), 0, 1)
    toward_paper = np.clip((t - 0.84) / 0.16, 0, 1) ** 1.5
    toward_ink = np.clip((0.16 - t) / 0.16, 0, 1)
    green, sea, warm = _hue_weight(hue, 125, 40), _hue_weight(hue, 255, 45), _hue_weight(hue, 40, 30)
    keep = 0.86 - 0.30 * green - 0.10 * sea + 0.20 * warm
    keep = keep * (1 - toward_paper) * (1 - toward_ink)
    a2 = a * keep + PAPER[1] * toward_paper + INK[1] * toward_ink
    b2 = b * keep + PAPER[2] * toward_paper + INK[2] * toward_ink + 0.010
    return np.clip(from_oklab(np.stack([l2, a2, b2], -1)), 0, 1)


def read_capture_log(path, shot):
    """[LABEL]/[NORTH]/[TILEPX] lines for one shot of review_colour.tscn."""
    labels, north, east, tile_px = [], None, None, None
    for line in open(path, encoding="utf-8", errors="replace"):
        if not line.startswith("[") or ("] " + shot + "|") not in line:
            continue
        kind, rest = line.split("] ", 1)
        fields = rest.strip().split("|")
        if kind == "[LABEL":
            labels.append((fields[1], fields[2], float(fields[3]), float(fields[4])))
        elif kind == "[NORTH":
            north, east = (float(fields[1]), float(fields[2])), (float(fields[3]), float(fields[4]))
        elif kind == "[TILEPX":
            tile_px = float(fields[1])
    return labels, north, east, tile_px


def map_sheet(render_path, title, subtitle, number, log_path, feature="", crop=None,
              imprint="CARBON AND CAPITAL  ·  INDUSTRIAL CATALOGUE", map_width=1800, seed=11, bare=False):
    """`bare`: the print alone, edge to edge at the capture's own size, as the game screen would
    look (no border, labels, title, fold)."""
    rng = np.random.default_rng(seed)
    capture = Image.open(render_path).convert("RGB")
    shot = render_path.replace("\\", "/").split("/")[-1]
    labels, north, east, _tile_px = read_capture_log(log_path, shot) if log_path else ([], None, None, None)
    x0, y0, x1, y1 = crop or (0, 0, capture.width, capture.height)
    capture = capture.crop((x0, y0, x1, y1))
    scale = 1.0 if bare else map_width / capture.width
    if not bare:
        capture = capture.resize((map_width, int(capture.height * scale)), Image.LANCZOS)
    mw, mh = capture.size
    margin, top, band = (0, 0, 0) if bare else (70, 110, 360)
    width, height = mw + 2 * margin, top + mh + band
    mx, my = margin, top

    def noise(sigma):
        n = ndi.gaussian_filter(rng.standard_normal((height, width)), sigma)
        return n / n.std()
    mottle, fibre, tooth, grain = noise(110), noise((0.8, 3.5)), noise(1.2), noise(0.7)
    yy, xx = np.mgrid[0:height, 0:width]
    edge = np.minimum(np.minimum(xx, width - 1 - xx) / width, np.minimum(yy, height - 1 - yy) / height)
    sheet = PAPER_RGB * (1 + MOTTLE * mottle[..., None] + FIBRE * fibre[..., None] + TOOTH * tooth[..., None])
    sheet *= ((0.97 + 0.03 * np.clip(edge / 0.03, 0, 1)) if bare else (0.93 + 0.07 * np.clip(edge / 0.05, 0, 1)))[..., None]

    rgb = np.asarray(capture).astype(float) / 255
    ink = printed_map(rgb)
    # Engraved water-lining: an inked coastline and fading parallel lines offshore. The sea is
    # the large connected blue areas (blue glass towers are too small to survive the opening).
    lab = to_oklab(rgb)
    hue = np.degrees(np.arctan2(lab[..., 2], lab[..., 1])) % 360
    sea = (np.hypot(lab[..., 1], lab[..., 2]) > 0.05) & (_hue_weight(hue, 258, 35) > 0.3)
    pad = 48   # the sea runs on past the frame: the frame edge is not a coast
    sea = np.pad(sea, pad, mode="edge")
    sea = ndi.binary_opening(sea, iterations=4)
    parts, count = ndi.label(sea)
    sizes = ndi.sum(sea, parts, range(1, count + 1))
    sea = np.isin(parts, [i + 1 for i, z in enumerate(sizes) if z > 0.004 * sea.size])
    sea = ndi.binary_closing(sea, iterations=3)
    off = ndi.distance_transform_edt(sea)[pad:-pad, pad:-pad]
    sea = sea[pad:-pad, pad:-pad]
    lining = np.zeros(sea.shape)
    for d, strength, w in ((1.2, 0.85, 1.1), (7.0, 0.42, 0.7), (14.0, 0.30, 0.6), (23.0, 0.20, 0.55), (35.0, 0.12, 0.5)):
        lining = np.maximum(lining, strength * np.clip(1 - np.abs(off - d) / w, 0, 1))
    lining *= sea
    ink = ink * (1 - lining[..., None]) + INK_RGB * lining[..., None]
    luma = ink @ [0.2126, 0.7152, 0.0722]
    sub = (slice(my, my + mh), slice(mx, mx + mw))
    ink = ink * (1 + INK_FIBRE * fibre[sub][..., None]) + (INK_GRAIN * grain[sub] * 4 * luma * (1 - luma))[..., None]
    ink *= 0.95 + 0.05 * sheet[sub] / PAPER_RGB
    key = np.roll(np.roll(np.clip((0.30 - luma) / 0.15, 0, 1), -2, 0), -2, 1)
    ink = ink * (1 - 0.22 * key[..., None]) + INK_RGB * 0.22 * key[..., None]
    sheet[sub] = ink
    if bare:
        return Image.fromarray((np.clip(sheet, 0, 1) * 255).astype("uint8"))
    # A soft fold down the middle of the sheet.
    fold = np.exp(-((xx - width / 2) / 14.0) ** 2)
    sheet *= (1 - 0.035 * fold * (xx < width / 2) + 0.02 * fold * (xx >= width / 2))[..., None]

    image = Image.fromarray((np.clip(sheet, 0, 1) * 255).astype("uint8"))
    draw = ImageDraw.Draw(image)
    ink_c = tuple(int(c * 255) for c in INK_RGB)
    paper_c = tuple(int(c * 255) for c in PAPER_RGB)
    # Neat line with a chequered border, and the outer rules.
    bar = 12
    draw.rectangle((mx - 1, my - 1, mx + mw, my + mh), outline=ink_c, width=2)
    draw.rectangle((mx - bar - 2, my - bar - 2, mx + mw + bar + 1, my + mh + bar + 1), outline=ink_c, width=2)
    seg = 64
    for k in range(0, mw, seg):
        if (k // seg) % 2 == 0:
            draw.rectangle((mx + k, my - bar - 1, min(mx + k + seg, mx + mw) - 1, my - 2), fill=ink_c)
            draw.rectangle((mx + k, my + mh + 1, min(mx + k + seg, mx + mw) - 1, my + mh + bar), fill=ink_c)
    for k in range(0, mh, seg):
        if (k // seg) % 2 == 0:
            draw.rectangle((mx - bar - 1, my + k, mx - 2, min(my + k + seg, my + mh) - 1), fill=ink_c)
            draw.rectangle((mx + mw + 1, my + k, mx + mw + bar, min(my + k + seg, my + mh) - 1), fill=ink_c)
    draw.rectangle((24, 24, width - 24, height - 24), outline=ink_c, width=3)
    draw.rectangle((34, 34, width - 34, height - 34), outline=ink_c, width=1)

    def font(path, size, index=0):
        return ImageFont.truetype(path, size, index=index)

    def spaced(x, y, text, f, fill, track, anchor="l", halo=0):
        total = sum(draw.textlength(ch, font=f) + track for ch in text) - track
        if anchor == "m":
            x -= total / 2
        elif anchor == "r":
            x -= total
        for ch in text:
            draw.text((x, y), ch, font=f, fill=fill, stroke_width=halo, stroke_fill=paper_c)
            x += draw.textlength(ch, font=f) + track
        return total

    # Place labels from the capture, in map coordinates; anything near the edge is left out.
    for tid, name, lx, ly in labels:
        px, py = (lx - x0) * scale + mx, (ly - y0) * scale + my
        if not (mx + 120 < px < mx + mw - 120 and my + 40 < py < my + mh - 50):
            continue
        upper = name.upper()
        if tid == feature:
            spaced(px, py - 26, upper, font(FUTURA, 40), ink_c, 10, "m", halo=4)
        elif "Coast" in name or "Beach" in name:
            spaced(px, py - 10, upper, font(GILL_SANS, 19, 2), ink_c, 5, "m", halo=3)
        elif "Fields" in name:
            spaced(px, py - 10, upper, font(GILL_SANS, 20), ink_c, 6, "m", halo=3)
        else:
            spaced(px, py - 14, upper, font(GILL_SANS, 26, 1), ink_c, 7, "m", halo=4)

    # Title band: sheet number, title, subtitle, imprint; scale bar and compass on the right.
    by = my + mh + bar + 40
    spaced(mx, by, "SHEET " + str(number), font(GILL_SANS, 24), ink_c, 10)
    spaced(mx, by + 36, title, font(FUTURA, 86), ink_c, 10)
    spaced(mx, by + 146, subtitle, font(GILL_SANS, 30), ACCENT_RGB, 8)
    spaced(mx, by + 196, imprint, font(GILL_SANS, 22), ink_c, 6)
    if north and east:
        # Horizontal on the sheet runs along north + east on the ground (iso), 400 units each.
        per_unit = np.hypot(north[0] + east[0], north[1] + east[1]) / (400 * np.sqrt(2)) * scale
        # One tile across, or a half or quarter of one when a whole tile would crowd the title.
        fraction, label = next(((f, t) for f, t in ((1.0, "ONE TILE"), (0.5, "HALF A TILE"), (0.25, "QUARTER TILE"))
                                if 540 * per_unit * f <= 440), (0.25, "QUARTER TILE"))
        length = 540 * per_unit * fraction
        sx, sy = width - margin - 240 - length, by + 120
        for k in range(4):
            fill = ink_c if k % 2 == 0 else paper_c
            draw.rectangle((sx + k * length / 4, sy, sx + (k + 1) * length / 4, sy + 12), fill=fill, outline=ink_c, width=2)
        spaced(sx, sy + 22, "0", font(GILL_SANS, 20), ink_c, 2, "m")
        spaced(sx + length, sy + 22, label, font(GILL_SANS, 20), ink_c, 4, "m")
        spaced(sx + length / 2, sy - 34, "SCALE ACROSS THE SHEET", font(GILL_SANS, 18, 2), ink_c, 4, "m")
        cx, cy, r = width - margin - 90, by + 110, 62
        n = np.array(north) / np.hypot(*north)
        perp = np.array([-n[1], n[0]])
        tip, tail = np.array([cx, cy]) + n * r, np.array([cx, cy]) - n * r * 0.75
        draw.ellipse((cx - r * 0.82, cy - r * 0.82, cx + r * 0.82, cy + r * 0.82), outline=ink_c, width=2)
        left = [tuple(tip), (cx + perp[0] * 14, cy + perp[1] * 14), tuple(tail)]
        right = [tuple(tip), (cx - perp[0] * 14, cy - perp[1] * 14), tuple(tail)]
        draw.polygon(left, fill=ink_c)
        draw.polygon(right, fill=paper_c, outline=ink_c)
        lx, ly = np.array([cx, cy]) + n * (r + 22)
        spaced(lx, ly - 14, "N", font(FUTURA, 28), ink_c, 0, "m")
    return image


def plate(render_path, title, subtitle, number, imprint="CARBON AND CAPITAL  ·  INDUSTRIAL CATALOGUE", seed=11):
    rng = np.random.default_rng(seed)
    building = Image.open(render_path).convert("RGBA")
    building = building.crop(building.getbbox())
    scale = BUILDING_WIDTH / building.width
    building = building.resize((int(building.width * scale), int(building.height * scale)), Image.LANCZOS)
    rgba = np.asarray(building).astype(float) / 255
    width, height = SHEET
    x0, y0 = (width - building.width) // 2, 260
    h, w = rgba.shape[:2]
    alpha = np.zeros((height, width))
    alpha[y0:y0 + h, x0:x0 + w] = rgba[..., 3]

    def noise(sigma):
        n = ndi.gaussian_filter(rng.standard_normal((height, width)), sigma)
        return n / n.std()
    mottle, fibre, tooth, grain = noise(90), noise((0.8, 3.5)), noise(1.2), noise(0.7)
    yy, xx = np.mgrid[0:height, 0:width]
    edge = np.minimum(np.minimum(xx, width - 1 - xx) / width, np.minimum(yy, height - 1 - yy) / height)
    sheet = PAPER_RGB * (1 + MOTTLE * mottle[..., None] + FIBRE * fibre[..., None] + TOOTH * tooth[..., None])
    sheet *= (0.94 + 0.06 * np.clip(edge / 0.05, 0, 1))[..., None]
    # The sun stands south-east: the shadow falls up the sheet and a little left (11 o'clock).
    shadow = np.roll(np.roll(ndi.gaussian_filter(alpha, 22), -55, 0), -18, 1) * (1 - alpha)
    sheet *= (1 - 0.13 * shadow)[..., None]

    ink = np.zeros((height, width, 3))
    ink[y0:y0 + h, x0:x0 + w] = printed(rgba[..., :3])
    luma = ink @ [0.2126, 0.7152, 0.0722]
    ink = ink * (1 + INK_FIBRE * fibre[..., None]) + (INK_GRAIN * grain * 4 * luma * (1 - luma))[..., None]
    ink *= 0.965 + 0.035 * sheet / PAPER_RGB
    sheet = sheet * (1 - alpha[..., None]) + ink * alpha[..., None]
    # The dark key layer, two pixels off register.
    key = np.roll(np.roll(np.clip((0.33 - luma) / 0.15, 0, 1) * alpha, -2, 0), -2, 1)
    sheet = sheet * (1 - 0.25 * key[..., None]) + INK_RGB * 0.25 * key[..., None]

    image = Image.fromarray((np.clip(sheet, 0, 1) * 255).astype("uint8"))
    draw = ImageDraw.Draw(image)
    ink_colour = tuple(int(c * 255) for c in INK_RGB)
    draw.rectangle((48, 48, width - 48, height - 48), outline=ink_colour, width=3)
    draw.rectangle((60, 60, width - 60, height - 60), outline=ink_colour, width=1)

    def spaced(y, text, font, fill, track):
        total = sum(draw.textlength(ch, font=font) + track for ch in text) - track
        x = (width - total) / 2
        for ch in text:
            draw.text((x, y), ch, font=font, fill=fill)
            x += draw.textlength(ch, font=font) + track
    spaced(110, "PLATE " + str(number), ImageFont.truetype(GILL_SANS, 26), ink_colour, 10)
    y = y0 + h + 80
    draw.line((width / 2 - 260, y, width / 2 + 260, y), fill=ink_colour, width=2)
    spaced(y + 34, title, ImageFont.truetype(FUTURA, 70), ink_colour, 6)
    spaced(y + 130, subtitle, ImageFont.truetype(GILL_SANS, 30), ACCENT_RGB, 8)
    draw.line((width / 2 - 160, y + 190, width / 2 + 160, y + 190), fill=ink_colour, width=1)
    spaced(y + 215, imprint, ImageFont.truetype(GILL_SANS, 22), ink_colour, 6)
    return image


def main():
    parser = argparse.ArgumentParser(description="Print a render in the Paper WPA Catalog style.")
    parser.add_argument("render")
    parser.add_argument("output")
    parser.add_argument("--title", default="")
    parser.add_argument("--subtitle", default="")
    parser.add_argument("--number", default="1")
    parser.add_argument("--map", action="store_true", help="a whole view capture, printed as a map sheet")
    parser.add_argument("--log", help="review_colour.tscn's output for the capture (map sheets)")
    parser.add_argument("--feature", default="", help="tile id whose name is set largest (map sheets)")
    parser.add_argument("--crop", help="x0,y0,x1,y1 in capture pixels (map sheets)")
    parser.add_argument("--bare", action="store_true", help="map print alone, full frame: no border, labels or title")
    args = parser.parse_args()
    if args.map:
        crop = tuple(int(v) for v in args.crop.split(",")) if args.crop else None
        map_sheet(args.render, args.title, args.subtitle, args.number, args.log or "", args.feature, crop,
                  bare=args.bare).save(args.output)
    else:
        plate(args.render, args.title, args.subtitle, args.number).save(args.output)


if __name__ == "__main__":
    main()
