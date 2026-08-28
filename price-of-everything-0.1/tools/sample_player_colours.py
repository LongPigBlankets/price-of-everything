"""One-time sampling of the eight company-livery colours from their goods icons.

Two things make a naive sample wrong, and both are handled here:

1. The icons do NOT share a background. Some are chroma-keyed magenta, others sit on a
   solid blue or cyan plate. The background is therefore detected from the corner pixels
   rather than assumed, and excluded by distance.
2. An icon shows a SCENE, not a swatch: the fertiliser icon is a green sack beside brown
   soil, red tomatoes and a wooden crate. "Dominant colour" picks whichever element is
   largest, which is why fertiliser first sampled blue. Each livery therefore names the
   hue family it wants, and the sample is the median of the subject pixels inside that
   band -- the real green of the sack, not an average of the whole picture.

Writes data/player_colours.json, which both the dropdown swatches and the map painter read.
"""
import colorsys
import json
from pathlib import Path

ICONS = Path("assets/icons/goods/medium")
OUT = Path("data/player_colours.json")
SHEET = Path("artifacts/player_colour_sheet.png")

# key, label, icon stem, search hue band, search value band, min saturation,
# then the LIVERY BAND: (s_min, s_max), (v_min, v_max).
#
# The hue always comes from the icon -- that is the good's identity and is never invented.
# The livery band clamps only saturation and value, and exists because a livery has a job
# beyond resembling its good: eight companies must be told apart at a glance, on the map's
# warm-grey fabric. Raw samples fail that twice over. Ethylene is pale laboratory glass
# whose only blue is its shading, so it sampled a near-black navy that no one could tell
# from Graphite Black; and graphite sampled too light to read as black at all. Brown keeps
# a LOW value ceiling on purpose -- brown is dark orange, and letting it brighten collapses
# it into Pipe Orange, which shares its hue within five degrees.
GOODS = [
    ("diesel_red",          "Diesel Red",          "g_031_fuels",                      (345, 15),  (0.25, 0.90), 0.35, (0.55, 0.75), (0.60, 0.78)),
    ("ethylene_blue",       "Ethylene Blue",       "g_024_ethylene",                   (175, 255), (0.20, 0.90), 0.12, (0.50, 0.70), (0.50, 0.68)),
    ("fertiliser_green",    "Fertiliser Green",    "g_064_fertilisers",                (70, 165),  (0.20, 0.90), 0.25, (0.45, 0.65), (0.52, 0.68)),
    ("biomass_brown",       "Biomass Brown",       "g_062_biomass",                    (12, 45),   (0.20, 0.62), 0.25, (0.45, 0.65), (0.34, 0.48)),
    ("construction_yellow", "Construction Yellow", "g_071_construction_equipment_ice", (38, 68),   (0.35, 1.00), 0.35, (0.55, 0.78), (0.72, 0.86)),
    ("graphite_black",      "Graphite Black",      "g_066_graphite",                   None,       (0.05, 0.42), 0.00, (0.06, 0.20), (0.18, 0.28)),
    ("pipe_orange",         "Pipe Orange",         "g_021_copper_pipe",                (10, 42),   (0.45, 1.00), 0.40, (0.50, 0.72), (0.62, 0.80)),
    ("lithium_pink",        "Lithium Pink",        "g_051_lithium_carbonate",          (290, 355), (0.30, 0.95), 0.15, (0.38, 0.55), (0.72, 0.88)),
]


def corners_background(img):
    """The plate colour, taken from the four corners so it works for magenta and solid alike."""
    w, h = img.size
    pts = [(2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3)]
    cols = [img.getpixel(p) for p in pts]
    return tuple(sorted(c[i] for c in cols)[len(cols) // 2] for i in range(3))


def in_band(hue_deg, band):
    lo, hi = band
    if lo <= hi:
        return lo <= hue_deg <= hi
    return hue_deg >= lo or hue_deg <= hi     # wraps through 0


def sample(path, band, vband, min_s):
    from PIL import Image
    img = Image.open(path).convert("RGB")
    img.thumbnail((360, 360))
    bg = corners_background(img)

    subject = 0
    hits = []
    for (r, g, b) in img.getdata():
        # Background, by distance from the detected plate colour.
        if abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2]) < 60:
            continue
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if v < 0.10:                      # ink outline
            continue
        subject += 1
        if s < min_s or not (vband[0] <= v <= vband[1]):
            continue
        if band is not None:
            if not in_band(h * 360.0, band):
                continue
        else:
            if s > 0.45:                  # achromatic livery: reject anything colourful
                continue
        hits.append((h, s, v))

    if not hits or subject == 0:
        return None, 0.0
    share = len(hits) / float(subject)
    hs = sorted(t[0] for t in hits)
    ss = sorted(t[1] for t in hits)
    vs = sorted(t[2] for t in hits)
    mid = len(hits) // 2
    return (hs[mid], ss[mid], vs[mid]), share


def hexof(h, s, v):
    r, g, b = colorsys.hsv_to_rgb(h, s, v)
    return "%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))


def main():
    from PIL import Image, ImageDraw
    out = {}
    rows = []
    print(f"{'livery':22} {'raw':>8} {'livery':>9}  {'H':>4} {'S':>5} {'V':>5}  {'share':>6}")
    for key, label, stem, band, vband, min_s, sclamp, vclamp in GOODS:
        path = ICONS / f"{stem}.png"
        if not path.exists():
            print(f"{label:22} MISSING {path}")
            continue
        got, share = sample(path, band, vband, min_s)
        if got is None:
            print(f"{label:22} NO PIXELS IN BAND -- needs a look")
            continue
        h, s_raw, v_raw = got
        s = min(max(s_raw, sclamp[0]), sclamp[1])
        v = min(max(v_raw, vclamp[0]), vclamp[1])
        moved = "  (clamped)" if (abs(s - s_raw) > 0.005 or abs(v - v_raw) > 0.005) else ""
        flag = "  <-- thin" if share < 0.02 else ""
        print(f"{label:22} #{hexof(h,s_raw,v_raw)} #{hexof(h,s,v)}  {h*360:4.0f} {s:5.2f} {v:5.2f}"
              f"  {share*100:5.1f}%{flag}{moved}")
        out[key] = {"label": label, "good_icon": stem, "hex": hexof(h, s, v),
                    "hsv": [round(h, 4), round(s, 4), round(v, 4)],
                    "raw_hex": hexof(h, s_raw, v_raw),
                    "subject_share": round(share, 4)}
        rows.append((label, stem, hexof(h, s, v)))

    OUT.write_text(json.dumps({
        "note": "Sampled ONCE from the goods icons by tools/sample_player_colours.py. "
                "Edit by hand freely -- nothing re-samples at runtime.",
        "colours": out,
    }, indent=2) + "\n")
    print(f"\nwrote {OUT}")

    # Contact sheet: icon crop beside its sampled swatch, on the fabric grey the map uses,
    # so the choice can be judged where it will actually be seen.
    cell_h, sw = 96, 150
    sheet = Image.new("RGB", (620, cell_h * len(rows)), (0x85, 0x80, 0x75))
    d = ImageDraw.Draw(sheet)
    for i, (label, stem, hx) in enumerate(rows):
        y = i * cell_h
        ic = Image.open(ICONS / f"{stem}.png").convert("RGB")
        ic.thumbnail((cell_h - 12, cell_h - 12))
        sheet.paste(ic, (6, y + 6))
        d.rectangle([110, y + 6, 110 + sw, y + cell_h - 6], fill=tuple(int(hx[j:j+2], 16) for j in (0, 2, 4)))
        d.text((110 + sw + 14, y + cell_h // 2 - 4), f"{label}   #{hx}", fill=(20, 18, 16))
    SHEET.parent.mkdir(exist_ok=True)
    sheet.save(SHEET)
    print(f"wrote {SHEET}")


if __name__ == "__main__":
    main()
