"""A prototype of the game's nameplate (owner's brief), in Blender.

Two plates (--plate), both navy enamel with a thin raised brass rim and slotted brass screws,
as on the current emblem, both lettered in tall, blocky capitals (Impact, as tall and square
as the AI concept's plate):

  hex        one pointy-top hexagon, like a tile of the map: the factory in its top point,
             CARBON, "and" on a brass tab across a brass rule, CAPITAL, and the solar panel
             in its bottom point;
  honeycomb  the emblem's honeycomb (three hexes over four over three): CARBON across the
             two left hexes of the top row, the factory alone in the top-right hex, "and" in
             the middle row, the solar panel alone in the bottom-left hex and CAPITAL across
             the two right hexes of the bottom row; each icon's hex outlined in brass.

CARBON, in one of three ways (--carbon), always on a brass outline:
  heat   dark coal letters with a hint of heat at their feet, as on the AI plate: an ember
         glow along their lower edges, which runs a little way up their cracks;
  forge  each letter a window into a forge, red-hot at its foot through orange and red to
         dark at its top, sparks flying up in it and a few escaping over the plate (drawn
         on the flat glyphs set into their brass edges, which straight on is the same
         picture as a window);
  ember  blocks of coal, each set a little askew, their larger cracks glowing ember-orange.
CAPITAL is raised brass.

On the wide honeycomb (the default) the words are moulded to their rows (--words, owner):
CARBON's tops rise to the top row's points and CAPITAL's feet drop to the bottom row's, and
the plate's only screws are small silver ones either side of each icon (owner).

All the light comes from the right (owner): a low key and a higher fill, so every relief
casts its shadow to the left. The fire is its own light (fire_light). Grime gathers where the relief
meets the face.

Run headless from the repo root (the agent shim adds the background flag), then lay it on
the capsule's navy with its shadow and glow (nameplate_finish.py). Give --out an absolute
path: Blender resolves a relative one against its own start folder.

The plate lies in the XY plane facing +Z and an orthographic camera looks straight down at
it, so it can be laid flat over the key art. Cycles renders it, on the GPU where there is
one, with a transparent background. The typefaces are the Mac's own (Impact, and
Baskerville SemiBold Italic taken out of its font collection with fontTools into a cache,
as Blender reads only a collection's first face); a release wants a licensed or custom face.
"""
import argparse
import json
import math
import os
import random
import subprocess
import sys
import tempfile

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--plate", choices=("hexbar", "single", "hex", "honeycomb", "honeycomb-wide"), default="honeycomb-wide",
                help="hexbar: CARBON on a navy plate, a hex of coal with AND on a silver plaque, CAPITAL on a navy "
                     "plate, in a row (owner); single: one regular hex, CARBON over AND over CAPITAL (owner)")
ap.add_argument("--carbon", choices=("brass", "whitehot", "coals", "heat", "forge", "ember"), default="brass",
                help="brass: raised brass as CAPITAL is (owner); whitehot: solid raised letters glowing white, a "
                     "little melted where they meet the plate (owner, after a player found the coal letters hard "
                     "to read); coals: built of lumps of coal")
ap.add_argument("--and", dest="and_", choices=("coal", "silver", "stamped"), default=None,
                help="AND: built of coal in a bright silver dish sunk into the plate (the wide honeycomb's "
                     "default; owner), raised brushed silver, or stamped into the plate in silver (the single "
                     "hex's default; owner)")
ap.add_argument("--sun", choices=("low", "high"), default="low",
                help="with --light topleft: low (about 39 degrees up, v11; owner's choice) or high (about "
                     "66, lighting the face head-on, v13)")
ap.add_argument("--letters", choices=("octagon", "impact"), default="octagon",
                help="the words' letters: an octagonal alphabet drawn here (owner), or Impact")
ap.add_argument("--hexes", choices=("regular", "tall"), default="regular",
                help="the honeycombs' hexes: regular, every side the same length (owner), or a little "
                     "taller than regular, as the emblem's are (v16)")
ap.add_argument("--top", choices=("coal", "plate"), default="coal",
                help="with the moulded coal CARBON on the wide honeycomb: the top row a slab of coal with "
                     "CARBON burning in it, the navy plate below it (owner), or the top row part of the "
                     "navy plate (v21)")
ap.add_argument("--brass-light", choices=("wide", "corner"), default="wide",
                help="(--light topleft) wide: the brass lit as brightly as CAPITAL's C over the left two "
                     "thirds of the plate, by a lamp that lights only the brass (owner); corner: the one lamp "
                     "over the top left lights everything (v28)")
ap.add_argument("--hexbar-and", choices=("letters", "plaque"), default="letters",
                help="the hex bar's AND: silver letters alone on the coal, as tall as the bar (owner), or engraved "
                     "in a silver plaque (hex bar v1)")
ap.add_argument("--words", choices=("moulded", "boxed"), default="moulded",
                help="with the octagonal letters on the wide honeycomb: moulded to the hexes, CARBON's tops "
                     "to the top row's points and CAPITAL's feet to the bottom row's (owner), or each word "
                     "in a flat box (v15)")
ap.add_argument("--icons", choices=("game", "drawn"), default="game",
                help="the game's own factory and solar farm icons, traced (icon_key.py), or the drawn ones")
ap.add_argument("--light", choices=("right", "topleft"), default="right",
                help="where all the light comes from: the right, or the top left")
ap.add_argument("--res", default=None, help="default: 1900x2200 for the hex, 2200x1900 for the honeycomb")
ap.add_argument("--samples", type=int, default=160)
ap.add_argument("--save", default=None, help="also save the scene to this .blend")
args = ap.parse_args(argv)

SUPP = "/System/Library/Fonts/Supplemental/"
FONT_CACHE = os.path.join(tempfile.gettempdir(), "capsule_nameplate_fonts")
WORD_FONT = SUPP + "Impact.ttf"
AND_FACE = (SUPP + "Baskerville.ttc", "Baskerville SemiBold Italic", SUPP + "BigCaslon.ttf")

BODY_Z0 = -0.30                                # the enamelled plate's underside
RIM_W, RIM_H = 0.17, 0.07                      # the raised brass rim: width, height above the face
# The plate's colours and brass, by the sun (--sun). Low (v11, the owner's choice): the navy
# and brass the plate was tuned in, the brass wholly metal and satin. High (v13): lit head-on,
# the navy and gold deeper so they keep their colour, the brass part metal (see brass_mat).
HIGH = args.sun == "high"
# (low: darker than v11's navy, so the lit plate is near the backdrop's own navy; owner)
NAVY = (0.007, 0.022, 0.064) if HIGH else (0.004, 0.010, 0.022)
BRASS_METAL = 0.55 if HIGH else 1.0
# The coal hexes (--top coal, owner), when they can be drawn: the moulded coal CARBON on the
# wide honeycomb.
TOP_COAL = (args.top == "coal" and args.plate == "honeycomb-wide" and args.carbon == "coals"
            and args.letters == "octagon" and args.words == "moulded")
# the fire's light, as a multiple of how bright it looks; less where the whole of the top row
# burns, or it lights the dark coal round the letters orange, and less again where the whole
# of every letter is white-hot, or it fills their counters with orange
CARBON_LIGHT = 12.0 if TOP_COAL else 6.0 if args.carbon == "whitehot" else 40.0
FIRE_TINT = (1.0, 0.52, 0.20)                  # and warmer: the glow as a whole is orange round its white core
SUN_SHADOWLESS = 0.60                          # coal lumps this far up their letters and lower cast no sun shadow
FIRE_LAMPS = (14, 0.42, 0.15, 120.0)           # the hidden lamps over the fire: how many, height, radius, watts
FIRE_LAMP_UP = 0.22                            # how far up the letters they stand, in the white-hot to red
FIRE_LAMP_Z_COAL = 0.70                        # their height over the coal hexes
FRAME_IN, FRAME_OUT = 0.22, 0.29               # an icon's brass frame: its ring, inset from the icon's hex
# --top coal (owner): how far AND drops to clear the plate's new top edge, how high the coal
# sits (over the rim, which CARBON's feet overhang); and the heat: HEAT_HALF is half a
# stroke, where a letter is white-hot, EMBER_FADE how quickly the cracks' red fades away
# from the letters, down to EMBER_FLOOR of the letters' edge; the field's points to a unit.
AND_DROP, COAL_Z = 0.14, RIM_H + 0.03
LETTER_DEPTH, LETTER_BEVEL, LETTER_GLOW = 0.16, 0.015, 1.4   # the glow as v22's letters' coal had it
LETTER_HALF = 0.16                             # the letters' heat runs over this: white only down their middles
COAL_ROUGH = 0.05                              # how far the coal's edge crumbles in (or, at its foot, spills out)
GROUND_CLEAR = 0.05                            # no dark lump centred nearer a letter than this
# --carbon whitehot (owner): the letters as deep as CAPITAL's, their heat run over HOT_HALF (white
# beyond it, yellowing to orange at the edge), their glow; the melt at their feet, MELT_W out
# from the letter and MELT_H high.
HOT_DEPTH, HOT_BEVEL, HOT_HALF, HOT_GLOW = 0.14, 0.02, 0.10, 1.7   # glow: a smidge down from v26's 2.0 (owner)
HOT_COLOURS = [(0.40, (1.0, 0.45, 0.07)), (0.50, (1.0, 0.66, 0.22)), (0.60, (1.0, 0.86, 0.55)),
               (0.72, (1.0, 0.96, 0.86)), (1.0, (1.0, 0.99, 0.95))]
MELT_W, MELT_H = 0.035, 0.012
# --and coal (owner): AND this much larger, of coal lumps DISH_LUMP apart, in a silver octagonal
# dish DISH_MARGIN round it, its corners cut DISH_CHAMFER, sunk DISH_DEPTH with its lip DISH_LIP
# proud of the face; the dish's wall DISH_WALL thick at the lip, sloping in by DISH_SLOPE to the
# floor, so the side toward the light catches it.
AND_SCALE, DISH_LUMP = 1.2, 0.085
AND_LOOSE = dict(sizes=(0.7, 1.45), shrink=(0.62, 0.86), twist=28.0, jitter=0.16, tilt=0.45)   # (owner: less orderly)
AND_CLEAR = 0.045                              # AND's letters this far inside the dish's floor, top and bottom
DISH_CORNER = 0.035                            # the squarish dish's corners, just taken off
AND_BED_IN = 0.012                             # the black bed under AND's coal, drawn in so the coal hides its edges
LETTER_BEVEL_BRASS = 0.036                     # CARBON's and CAPITAL's bevel (owner: a little wider than v30's 0.025)
# the single hex (--plate single; owner): its half-width, AND's height and the gap from AND to
# the words; and how deep AND is stamped
SINGLE_A, SINGLE_AND_H, SINGLE_WORD_GAP, STAMP_DEPTH = 3.4, 0.62, 0.24, 0.035
HEXBAR_AND = args.hexbar_and
# the hex bar (--plate hexbar; owner): the hex's side and the plates' height; CARBON's letters'
# width; the words' gap from the hex; its coal's lumps; the silver plaque (width, height, cut
# corners), its underside and top; AND's height on it and how deep it is engraved
HEXBAR_S, HEXBAR_LETTER_W, HEXBAR_TEXT_IN = 2.0, 0.93, 0.16
HEX_LUMP = 0.40
HEX_COAL_LOOSE = dict(sizes=(0.8, 1.3), shrink=(0.82, 0.92), twist=8.0, jitter=0.05, tilt=0.35)
PLAQUE, PLAQUE_Z, HEXBAR_AND_H, ENGRAVE = (2.62, 0.95, 0.12), (0.30, 0.36), 0.58, 0.016
HEXBAR_AND_Z, HEXBAR_AND_SIDE = 0.26, 0.08       # the silver letters' underside over the coal; their gap to the dividers
HEXBAR_AND_SCALE = 0.5                           # AND this share of the bar's height and the hex's width (owner: half)
DISH_TO_FRAME_PX = 17                          # the dish's ends this near the icons' frames, in the render's pixels (owner: 15-20)
PLATE_LAMP = ((-5.0, 4.0, 11.0), 11.0, 380.0)   # (--light topleft) the broad lamp over the top left: where, width, watts
BRASS_LAMP = ((-1.8, 0.0, 11.0), (6.8, 7.6), 45.0)
# the single hex (owner: all its brass as bright as that): as bright to a unit of its area,
# over the whole hex and past it
BRASS_LAMP_SINGLE = ((0.0, 0.0, 11.0), (10.0, 11.0), 45.0 / (6.8 * 7.6) * 10.0 * 11.0)   # (--brass-light wide) level over the left two thirds: centre, size, watts
DISH_MARGIN, DISH_CHAMFER, DISH_DEPTH, DISH_LIP, DISH_WALL, DISH_SLOPE = 0.13, 0.30, 0.06, 0.012, 0.035, 0.04
HEAT_HALF, EMBER_FADE, EMBER_FLOOR, HEAT_RES = 0.12, 0.12, 0.10, 120
EMBER_PEAK = 3.0                               # the coal hexes' bed, white-hot
HEAT_COLOURS = [(0.0, (0.30, 0.02, 0.0)), (0.35, (0.62, 0.05, 0.005)), (0.50, (0.90, 0.13, 0.01)),
                (0.625, (1.0, 0.30, 0.03)), (0.75, (1.0, 0.55, 0.10)), (0.87, (1.0, 0.80, 0.35)),
                (1.0, (1.0, 0.95, 0.82))]
SILVER_SCREW_R = 0.065                         # the silver screws by the icons (the old brass ones were 0.10)
SCREW_GAP = 0.03                               # between a silver screw and the icon's frame
BRASS = (0.70, 0.40, 0.075) if HIGH else (0.95, 0.70, 0.24)      # low: more gold than v25's, twice over (owner)
ICON_DIR = os.path.join(os.path.dirname(os.path.realpath(__file__)), "icons")
ICON_BOX, ICON_DEPTH, ICON_BEVEL = 1.21, 0.07, 0.008   # the game icons' fit, relief and bevel
FRAME_H = ICON_DEPTH + 2 * ICON_BEVEL                   # the frames as high as the icons
CREAM = (0.78, 0.70, 0.52)
CARBON = (0.008, 0.008, 0.009)
EMBER = (1.0, 0.30, 0.04)
LETTER_JITTER = (2.5, 1.5)                     # degrees: each coal block's turn and tilt
OUTLINE = 0.065                                # the brass outline round CARBON, world units
HEAT_BAND = 0.20                               # the heat reaches this share up the letters
WORD_STRETCH = 1.60                            # how much taller than its face a word may be drawn
WORD_MARGIN = 0.10                             # a moulded word's gap to the rim
COAL_MARGIN = 0.7 * (RIM_W + WORD_MARGIN)      # CARBON 30% nearer the coal's edges than the plate's (owner)
WORD_GAP = 0.12                                # between a moulded word's letters
WORD_S = 0.143                                 # a moulded word's glyph unit (its stems 1.75 of them)
FOOT_CLEAR = 0.19                              # CARBON's feet over the icons' frames (and CAPITAL's top under)
# The honeycombs' hexes: half-width, and centre to point. Regular (owner), every side the same
# length; or a little taller, as traced from the emblem (carbon-capital-emblem-1400x700.png:
# half-width 77.5 px, centre to point 105 px).
HEX_A = 1.05
HEX_RV = HEX_A * 2 / math.sqrt(3) if args.hexes == "regular" else 1.428


def hex_cell(cx, cy, a, rv):
    """A pointy-top hexagon, counter-clockwise from its lower-right corner: half-width a,
    centre to point rv (a regular one has rv = a * 2 / sqrt(3))."""
    return [(cx + a, cy - rv / 2), (cx + a, cy + rv / 2), (cx, cy + rv), (cx - a, cy + rv / 2),
            (cx - a, cy - rv / 2), (cx, cy - rv)]


def layout_hex():
    """One regular pointy-top hexagon, 8.8 from point to point."""
    r = 4.4
    a = r * math.sqrt(3) / 2
    outline = hex_cell(0, 0, a, r)
    screw_line = inset(outline, RIM_W + 0.30)
    return dict(outline=outline, screws=screw_line, frames=[],
                carbon=(-2.55, 2.55, 0.50, 2.20), capital=(-2.55, 2.55, -2.20, -0.50),
                rule=(-3.45, 3.45, 0.0), tab=(0.0, 0.0),
                icons=[("factory", 0.0, 3.08, 0.92), ("solar", 0.0, -3.08, 0.90)])


def layout_honeycomb():
    """The emblem's honeycomb: rows of three, four and three pointy-top hexes (HEX_A, HEX_RV)."""
    a, rv = HEX_A, HEX_RV
    top, mid, bot = 1.5 * rv, 0.0, -1.5 * rv
    outline = [(4 * a, -rv / 2), (4 * a, rv / 2), (3 * a, rv), (3 * a, top + rv / 2), (2 * a, top + rv),
               (a, top + rv / 2), (0, top + rv), (-a, top + rv / 2), (-2 * a, top + rv), (-3 * a, top + rv / 2),
               (-3 * a, rv), (-4 * a, rv / 2), (-4 * a, -rv / 2), (-3 * a, -rv), (-3 * a, bot - rv / 2),
               (-2 * a, bot - rv), (-a, bot - rv / 2), (0, bot - rv), (a, bot - rv / 2), (2 * a, bot - rv),
               (3 * a, bot - rv / 2), (3 * a, -rv)]
    line = inset(outline, RIM_W + 0.24)
    screws = [line[i] for i in (4, 6, 8, 15, 17, 19)]
    screws += [((line[0][0] + line[1][0]) / 2, 0.0), ((line[11][0] + line[12][0]) / 2, 0.0)]
    return dict(outline=outline, screws=screws,
                frames=[hex_cell(2 * a, top, a, rv), hex_cell(-2 * a, bot, a, rv)],
                carbon=(-2.95, 0.88, 0.98 * rv / 1.428, 2.62 * rv / 1.428),       # boxes set on the taller hexes
                capital=(-0.88, 2.95, -2.62 * rv / 1.428, -0.98 * rv / 1.428),
                rule=(-3.85, 3.85, 0.0), tab=(0.0, 0.0),
                icons=[("factory", 2 * a, top, 0.82), ("solar", -2 * a, bot, 0.82)])


def layout_hexbar():
    """CARBON, a hex of coal and CAPITAL in a row (owner): a navy plate on each side, lettered
    in brass, and between them a regular pointy-top hex whose upright sides are as tall as the
    plates (HEXBAR_S), so each plate meets one of them edge to edge and the three are one
    piece: a long bar with the hex's points standing above and below it, one brass rim round
    all of it and brass dividers where the plates meet the hex. The hex is filled with large
    lumps of dark coal, and a silver plaque lies on them with AND on it. The two plates are
    as long as each other, CARBON's letters HEXBAR_LETTER_W wide and CAPITAL's a little
    narrower, as it has the I as well; both words level, top and foot, and the octagonal
    letters as elsewhere."""
    s = HEXBAR_S
    a, rv, h = s * math.sqrt(3) / 2, s, s / 2
    m, g = RIM_W + WORD_MARGIN, WORD_GAP
    span = 6 * HEXBAR_LETTER_W + 5 * g                               # CARBON's length, and CAPITAL's
    w_i = oct_glyph("I")[1] * WORD_S
    w_p = (span - w_i - 6 * g) / 6
    x_in = a + HEXBAR_TEXT_IN                                        # the words' ends by the hex
    W = x_in + span + m                                              # the plates' outer ends
    # each plate's outer end half a regular octagon (owner): its corners cut at 45 degrees,
    # c along each side
    c = h * (2 - math.sqrt(2))
    outline = [(W, -h + c), (W, h - c), (W - c, h), (a, h), (0.0, rv), (-a, h), (-W + c, h), (-W, h - c),
               (-W, -h + c), (-W + c, -h), (-a, -h), (0.0, -rv), (a, -h), (W - c, -h)]

    def cells(x0, widths):
        out = []
        for w_ in widths:
            out.append((x0, x0 + w_))
            x0 += w_ + g
        return out
    y0, y1 = -h + m, h - m
    # the words shaped round the ends (owner): their tops and feet follow the cut corners, the
    # margin kept square to them, level elsewhere; bent where the two meet
    d = m * math.sqrt(2)
    bend = W - c - m * (math.sqrt(2) - 1)                               # where the cut corners begin, margin kept

    # CARBON's C drawn to the plate's end (owner: its stroke even all round, its inner corners
    # at the outer ones' angles): its outer corners the cut ones, a margin in; its inner ones
    # cut at 45 degrees too, a stroke's width (between the stem's and the bars') inside them;
    # its right side, the terminals, the alphabet's C
    s_, t_, oc, a1 = OCT_S * WORD_S, OCT_T * WORD_S, OCT_OC * WORD_S, 3.2 * WORD_S
    X0, X1, xb = -W + m, -W + m + HEXBAR_LETTER_W, -bend
    k_ = xb - X0                                                         # the outer cut, each way
    e2 = (s_ + t_) / 2 * math.sqrt(2)                                    # the stroke across the cut, as a drop
    ya = y1 - k_ - e2 + s_                                               # the inner cut meets the stem
    xc = xb + e2 - t_                                                    # and the bar
    c_letter = [(X1, y1 - a1), (X1, y1 - oc), (X1 - oc, y1), (xb, y1), (X0, y1 - k_), (X0, y0 + k_), (xb, y0),
                (X1 - oc, y0), (X1, y0 + oc), (X1, y0 + a1), (X1 - s_, y0 + a1), (X1 - s_, y0 + t_), (xc, y0 + t_),
                (X0 + s_, y0 + (y1 - ya)), (X0 + s_, ya), (xc, y1 - t_), (X1 - s_, y1 - t_), (X1 - s_, y1 - a1)]
    # CAPITAL stops where the cut corners begin (owner: its L ends there, its foot level)
    w_p = (bend - x_in - w_i - 6 * g) / 6

    def top_(x):
        return min(y1, h - c + (W - abs(x)) - d)

    def foot(x):
        return max(y0, -h + c - (W - abs(x)) + d)
    radiance = BRASS_LAMP[2] / (BRASS_LAMP[1][0] * BRASS_LAMP[1][1])  # the brass lamp as bright as on the honeycomb
    return dict(outline=outline, screws=[], frames=[], icons=[], rule=None, tab=None, silver_and=None,
                carbon=(-x_in - span, -x_in, y0, y1), capital=(x_in, x_in + span, y0, y1),
                moulded=dict(carbon=dict(letters="CARBON", cells=cells(-x_in - span, [HEXBAR_LETTER_W] * 6),
                                         square=((),) * 6, custom={0: [c_letter]}, base=foot, top=top_,
                                         bends=[-bend], roof=None),
                             capital=dict(letters="CAPITAL", cells=cells(x_in, [w_p] * 3 + [w_i] + [w_p] * 3),
                                          square=((),) * 7, base=foot, top=top_, bends=[bend])),
                coal_hex=dict(cell=hex_cell(0.0, 0.0, a, rv), a=a, h=h),
                # the plates' faces, each pulled in from its plate's outline but for its side on
                # the hex, where the divider stands inside the hex instead
                faces=[inset([(-a, h), (-W + c, h), (-W, h - c), (-W, -h + c), (-W + c, -h), (-a, -h)],
                             [RIM_W] * 5 + [0.0]),
                       inset([(a, -h), (W - c, -h), (W, -h + c), (W, h - c), (W - c, h), (a, h)],
                             [RIM_W] * 5 + [0.0])],
                brass_lamp=((0.0, 0.0, 11.0), (2 * W + 4.0, 2 * rv + 4.0), radiance * (2 * W + 4.0) * (2 * rv + 4.0)),
                plate_lamp=((-0.55 * W, h + 2.5, 11.0), 11.0, 380.0))


def layout_single():
    """The simplified logo (owner): one regular pointy-top hex, SINGLE_A from its middle to its
    upright sides; CARBON in its top half, standing on a level line above the middle, its
    letters' tops rising to the hex's top point, and CAPITAL in its bottom half, hanging from
    a level line below it, its feet dropping to the bottom point; AND stamped in silver in the
    middle. No icons, frames or screws. The words are moulded as on the wide honeycomb, but
    to one hex: CARBON's six letters share its width, the point over the gap between R and B,
    so each top is one straight slope; CAPITAL's I stands over the bottom point."""
    a = SINGLE_A
    rv = a * 2 / math.sqrt(3)
    outline = hex_cell(0.0, 0.0, a, rv)
    clear = (RIM_W + WORD_MARGIN) * math.hypot(1.0, rv / (2 * a))    # the rim and margin, measured upright
    roof, roof_bends = zigzag((0.0,), a, rv - clear, -rv / 2)
    floor, floor_bends = zigzag((0.0,), a, -rv + clear, rv / 2)
    reach, i_half, g = a - RIM_W - WORD_MARGIN, oct_glyph("I")[1] * WORD_S / 2, WORD_GAP / 2

    def cells(bounds):
        return [(x0 + (g if k else 0.0), x1 - (g if k < len(bounds) - 2 else 0.0))
                for k, (x0, x1) in enumerate(zip(bounds, bounds[1:]))]
    w6, w3 = 2 * reach / 6, (reach - i_half - g) / 3
    and_h, and_w = SINGLE_AND_H, SINGLE_AND_H * 2.15               # AND's proportions as on the honeycombs
    base = and_h / 2 + SINGLE_WORD_GAP
    return dict(outline=outline, screws=[], frames=[], icons=[], rule=None, tab=None,
                carbon=(-reach, reach, base, rv / 2), capital=(-reach, reach, -rv / 2, -base),
                silver_and=(-and_w / 2, and_w / 2, -and_h / 2, and_h / 2),
                moulded=dict(carbon=dict(letters="CARBON", cells=cells([-reach + w6 * k for k in range(7)]),
                                         square=(("tl", "tr"), ("tl", "tr"), ("tr",), (), ("tl", "tr"), ()),
                                         base=lambda x: base, top=roof, bends=roof_bends,
                                         roof=(rv - clear, -rv / 2, a)),
                             capital=dict(letters="CAPITAL",
                                          cells=cells([-reach, -reach + w3, -reach + 2 * w3, -i_half - g, i_half + g,
                                                       reach - 2 * w3, reach - w3, reach]),
                                          square=(("bl",), (), (), (), (), (), ()),
                                          base=floor, top=lambda x: -base, bends=floor_bends)))


def layout_honeycomb_wide():
    """The emblem's honeycomb with the words across whole rows (owner): CARBON across the top
    row, CAPITAL across the bottom one, and the middle row holding "and" in polished silver
    between the two icons, each alone in its outer hex, outlined in brass, the factory joined
    to its frame; small silver screws either side of each icon, just inside its frame, and no
    others (owner).

    Moulded (--words), the words fill their rows' hexes (owner): CARBON two letters to a hex,
    standing on a level line with their tops rising to each hex's point, and CAPITAL's seven
    across the three hexes, hanging from a level line with their feet dropping to each hex's
    point, both a margin inside the rim. Each letter fills the half of a hex between its point
    and the next hex (or the plate's side), so its top (or foot) is one straight slope and the
    gaps between letters are all alike; CAPITAL's I stands on the middle point, its foot a V.
    So the letters' widths differ a little, the ones against the plate's sides the narrowest."""
    L = layout_honeycomb()
    a, rv = HEX_A, HEX_RV
    top, bot = 1.5 * rv, -1.5 * rv
    centres = (-2 * a, 0.0, 2 * a)
    clear = (RIM_W + WORD_MARGIN) * math.hypot(1.0, rv / (2 * a))    # the rim and margin, measured upright
    roof, roof_bends = zigzag(centres, a, top + rv - clear, -rv / 2)
    floor, floor_bends = zigzag(centres, a, bot - rv + clear, rv / 2)
    reach, i_half = 3 * a - RIM_W - WORD_MARGIN, oct_glyph("I")[1] * WORD_S / 2
    # CARBON stands as low as it can with its outer letters' feet (where their bottom corners'
    # chamfers end) FOOT_CLEAR over the icons' brass frames, and CAPITAL hangs as high
    x_foot = reach - OCT_OC * WORD_S
    foot = rv - (3 * a - x_foot) * rv / (2 * a) - 0.22 * math.hypot(1.0, rv / (2 * a)) + FOOT_CLEAR

    def cells(bounds):
        """Letters between the bounds, the gaps centred on the inner ones."""
        g = WORD_GAP / 2
        return [(x0 + (g if k else 0.0), x1 - (g if k < len(bounds) - 2 else 0.0))
                for k, (x0, x1) in enumerate(zip(bounds, bounds[1:]))]
    # --top coal (owner): the top row a slab of coal with CARBON burning in it, its letters
    # moulded to the hexes top and bottom (owner: the bottom fits in better so), COAL_MARGIN
    # from the slab's edges; the navy plate and its brass rim end at the middle row's top, and
    # AND drops a little to clear it where it dips between the two middle hexes
    coal_top = TOP_COAL
    if coal_top:
        clear_c = COAL_MARGIN * math.hypot(1.0, rv / (2 * a))      # the margin, measured upright
        roof_c, roof_c_bends = zigzag(centres, a, top + rv - clear_c, -rv / 2)
        floor_c = zigzag(centres, a, top - rv + clear_c, rv / 2)[0]
        cells_c = cells((-(3 * a - COAL_MARGIN), -2 * a, -a, 0.0, a, 2 * a, 3 * a - COAL_MARGIN))
        L["coal"] = [(-3 * a, rv), (-2 * a, rv / 2), (-a, rv), (0.0, rv / 2), (a, rv), (2 * a, rv / 2), (3 * a, rv),
                     (3 * a, 2 * rv), (2 * a, top + rv), (a, 2 * rv), (0.0, top + rv), (-a, 2 * rv),
                     (-2 * a, top + rv), (-3 * a, 2 * rv)]
        o = L["outline"]
        L["plate"] = o[:3] + [(2 * a, rv / 2), (a, rv), (0.0, rv / 2), (-a, rv), (-2 * a, rv / 2)] + o[10:]
    L.update(screws=[], frames=[hex_cell(-3 * a, 0.0, a, rv), hex_cell(3 * a, 0.0, a, rv)],
             carbon=(-2.75, 2.75, 1.02 * rv / 1.428, 2.60 * rv / 1.428),
             capital=(-2.75, 2.75, -2.60 * rv / 1.428, -1.02 * rv / 1.428),
             rule=None, tab=None,
             silver_and=(-0.86, 0.86, -0.40 - AND_DROP, 0.40 - AND_DROP) if coal_top else (-0.86, 0.86, -0.40, 0.40),
             # small silver screws either side of each icon, just inside its frame (owner)
             silver_screws=[(cx + side * (a - FRAME_OUT - SCREW_GAP - SILVER_SCREW_R), 0.0)
                            for cx in (-3 * a, 3 * a) for side in (-1, 1)],
             merge=("factory",),                     # the factory joined to its frame (owner)
             icons=[("factory", -3 * a, 0.0, 0.80), ("solar", 3 * a, 0.0, 0.78)],
             # the corners, squared, where C, A, R and O reach into the hexes (owner: the tops of
             # C, A, R and O, and the foot of CAPITAL's C by the plate's side)
             moulded=dict(carbon=dict(letters="CARBON", cells=cells((-reach, -2 * a, -a, 0.0, a, 2 * a, reach)),
                                      square=(("tl", "tr"), ("tl", "tr"), ("tr",), (), ("tl", "tr"), ()),
                                      base=lambda x: foot, top=roof, bends=roof_bends,
                                      roof=(top + rv - clear, -rv / 2, a)),
                          capital=dict(letters="CAPITAL",
                                       cells=cells((-reach, -2 * a, -a, -i_half - WORD_GAP / 2, i_half + WORD_GAP / 2,
                                                    a, 2 * a, reach)),
                                       square=(("bl",), (), (), (), (), (), ()),
                                       base=floor, top=lambda x: -foot, bends=floor_bends)))
    if coal_top:
        # the feet squared too where C, O and B had chamfers, so they reach into the hexes' lower
        # points as the tops do their upper ones (owner)
        L["moulded"]["carbon_coal"] = dict(L["moulded"]["carbon"], cells=cells_c, base=floor_c, top=roof_c,
                                           bends=roof_c_bends, roof=(top + rv - clear_c, -rv / 2, a),
                                           square=(("tl", "tr", "bl", "br"), ("tl", "tr"), ("tr",), ("br",),
                                                   ("tl", "tr", "bl", "br"), ()))
    return L


def framing(outline):
    """The render's size and the camera's width (ortho scale) for a plate's outline: by default
    the honeycombs 2200 wide and as tall as the plate with the same margin as its sides."""
    xs = [p[0] for p in outline]
    ys = [p[1] for p in outline]
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    if args.res:
        res = args.res
    elif args.plate == "hex":
        res = "1900x2200"
    elif h > w:                                                   # portrait: 2200 tall, as wide as it needs
        res = "%dx2200" % round(2200 * (w + 0.1 * h) / (1.1 * h))
    else:
        res = "2200x%d" % round(2200 * (h + 0.1 * w) / (1.1 * w))
    rx, ry = (int(v) for v in res.lower().split("x"))
    return rx, ry, (max(w, h * rx / ry) if rx >= ry else max(h, w * ry / rx)) * 1.10


def clear_scene():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)


def face_file(ttc, face, fallback):
    """One face of a font collection as a font file of its own (cached), or the fallback."""
    out = os.path.join(FONT_CACHE, face.replace(" ", "_") + ".ttf")
    if not os.path.exists(out):
        os.makedirs(FONT_CACHE, exist_ok=True)
        code = ("import sys\nfrom fontTools.ttLib import TTCollection\n"
                "c = TTCollection(sys.argv[1])\n"
                "[f for f in c.fonts if f['name'].getDebugName(4) == sys.argv[2]][0].save(sys.argv[3])\n")
        try:
            subprocess.run(["python3", "-c", code, ttc, face, out], check=True, capture_output=True)
        except (OSError, subprocess.CalledProcessError):
            return fallback
    return out


def inset(outline, d):
    """An outline (counter-clockwise) pulled in by d, each edge moved along its normal; d may
    be a list, one distance to each edge (the edge from point i to point i + 1)."""
    n = len(outline)
    lines = []
    for i in range(n):
        (ax, ay), (bx, by) = outline[i], outline[(i + 1) % n]
        tx, ty = bx - ax, by - ay
        L = math.hypot(tx, ty)
        di = d[i] if isinstance(d, (list, tuple)) else d
        lines.append(((ax - ty / L * di, ay + tx / L * di), (tx, ty)))
    pts = []
    for i in range(n):
        (p, r), (q, s) = lines[i - 1], lines[i]
        den = r[0] * s[1] - r[1] * s[0]
        t = ((q[0] - p[0]) * s[1] - (q[1] - p[1]) * s[0]) / den
        pts.append((p[0] + r[0] * t, p[1] + r[1] * t))
    return pts


def link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def slab(name, outline, z0, z1, mat, bevel=0.0, hole=None):
    """An extruded outline, optionally with an inner outline cut out, from z0 up to z1."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    n = len(outline)
    ob_, ot = [bm.verts.new((x, y, z0)) for x, y in outline], [bm.verts.new((x, y, z1)) for x, y in outline]
    if hole is None:
        bm.faces.new(list(reversed(ob_)))
        bm.faces.new(ot)
        for i in range(n):
            bm.faces.new((ob_[i], ob_[(i + 1) % n], ot[(i + 1) % n], ot[i]))
    else:
        ib, it = [bm.verts.new((x, y, z0)) for x, y in hole], [bm.verts.new((x, y, z1)) for x, y in hole]
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((ot[i], ot[j], it[j], it[i]))
            bm.faces.new((ob_[j], ob_[i], ib[i], ib[j]))
            bm.faces.new((ob_[i], ob_[j], ot[j], ot[i]))
            bm.faces.new((ib[j], ib[i], it[i], it[j]))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new(name, me))
    me.materials.append(mat)
    if bevel:
        mod = ob.modifiers.new("bevel", 'BEVEL')
        mod.width, mod.segments, mod.limit_method = bevel, 3, 'ANGLE'
    return ob


def bar(name, p0, p1, width, z0, z1, mat):
    """A straight bar from p0 to p1 (xy), `width` across, from z0 to z1."""
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    L = math.hypot(dx, dy)
    nx, ny = -dy / L * width / 2, dx / L * width / 2
    return slab(name, [(p0[0] - nx, p0[1] - ny), (p1[0] - nx, p1[1] - ny), (p1[0] + nx, p1[1] + ny),
                       (p0[0] + nx, p0[1] + ny)], z0, z1, mat)


def disc(name, x, y, r, z0, z1, mat, n=32, bevel=0.0):
    return slab(name, [(x + r * math.cos(2 * math.pi * i / n), y + r * math.sin(2 * math.pi * i / n))
                       for i in range(n)], z0, z1, mat, bevel)


def dome(name, x, y, z, r, flat, mat):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=28, v_segments=14, radius=r)
    bmesh.ops.scale(bm, vec=(1, 1, flat), verts=bm.verts)
    bmesh.ops.translate(bm, vec=(x, y, z), verts=bm.verts)
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new(name, me))
    me.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = True
    return ob


def screw(name, x, y, z, r, angle, mat):
    """A slotted screw head, as on the emblem: a low dome with a slot cut across it."""
    head = dome(name, x, y, z, r, 0.45, mat)
    ax, ay = math.cos(angle), math.sin(angle)
    slot = bar(name + "_slot", (x - ax * r * 1.2, y - ay * r * 1.2), (x + ax * r * 1.2, y + ay * r * 1.2),
               r * 0.26, z + r * 0.28, z + r, mat)
    cut(head, slot)
    slot.hide_render = slot.hide_viewport = True
    return head


def cut(target, cutter):
    mod = target.modifiers.new(cutter.name, 'BOOLEAN')
    mod.operation, mod.object, mod.solver = 'DIFFERENCE', cutter, 'EXACT'


# ------------------------------------------------------------------ materials
def node_mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    return m, nt, nt.nodes["Principled BSDF"]


def grime(nt, rgb, into, dark=0.22, reach=0.12):
    """Darken a colour where the surface is occluded close by (the crevices round the
    relief), as grime and patina settle there; the result feeds `into`."""
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.only_local = True
    ao.inputs["Distance"].default_value = reach
    curve = nt.nodes.new("ShaderNodeMath")
    curve.operation = 'POWER'
    nt.links.new(ao.outputs["AO"], curve.inputs[0])
    curve.inputs[1].default_value = 1.6
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = 'RGBA'
    nt.links.new(curve.outputs["Value"], mix.inputs["Factor"])
    mix.inputs[6].default_value = (*(c * dark for c in rgb), 1)
    mix.inputs[7].default_value = (*rgb, 1)
    nt.links.new(mix.outputs[2], into)


def brass_mat(name="brass", rough=0.28, tone=1.0, vary=(0.08, 0.12), grain=18.0, metal=1.0):
    """Brass: its roughness varies by `vary` below and above `rough`, in a noise of scale
    `grain`, as wear; a high light turns a wide variation blotchy, so it wants a narrow one.
    Wholly metallic (`metal` 1), a flat face seen head-on reflects only what is above it and
    stays dark while its bevels catch the light; with a share of the light scattered too, it
    is lit the way the enamel beside it is."""
    m, nt, b = node_mat(name)
    b.inputs["Metallic"].default_value = metal
    grime(nt, tuple(c * tone for c in BRASS), b.inputs["Base Color"])
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = grain
    noise.inputs["Detail"].default_value = 8.0
    ramp = nt.nodes.new("ShaderNodeMapRange")
    ramp.inputs["To Min"].default_value = rough - vary[0]
    ramp.inputs["To Max"].default_value = rough + vary[1]
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Value"])
    nt.links.new(ramp.outputs["Result"], b.inputs["Roughness"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.05
    nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def enamel_mat(name, rgb, rough=0.32):
    """Stove enamel: a glossy coat over a colour, with a faint orange peel and grime."""
    m, nt, b = node_mat(name)
    grime(nt, rgb, b.inputs["Base Color"], dark=0.45, reach=0.15)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Coat Weight"].default_value = 0.5
    b.inputs["Coat Roughness"].default_value = 0.12
    peel = nt.nodes.new("ShaderNodeTexNoise")
    peel.inputs["Scale"].default_value = 90.0
    peel.inputs["Detail"].default_value = 2.0
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.04
    nt.links.new(peel.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Coat Normal"])
    return m


def world_y(nt):
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Position"], sep.inputs["Vector"])
    return sep.outputs["Y"]


def height_share(nt, y_foot, y_top, roof=None):
    """How far up its letter each point is, 0 at the feet (y_foot) and 1 at the top: level at
    y_top, or for a moulded word the zigzag roof (y_point, rise, a): y_point over each hex's
    point, at x = 0 and every 2a either side, `rise` higher at the shoulders between."""
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Position"], sep.inputs["Vector"])

    def math_node(op, a_, b_):
        m = nt.nodes.new("ShaderNodeMath")
        m.operation = op
        for sock, v in zip(m.inputs, (a_, b_)):
            if isinstance(v, (int, float)):
                sock.default_value = v
            else:
                nt.links.new(v, sock)
        return m.outputs["Value"]

    if roof:
        y_point, rise, a = roof
        # the distance to the nearest point, |((x + 5a) mod 2a) - a|, x kept positive for the modulo
        d = math_node('ABSOLUTE', math_node('SUBTRACT', math_node('MODULO', math_node('ADD', sep.outputs["X"], 5 * a),
                                                                  2 * a), a), 0.0)
        top = math_node('ADD', math_node('MULTIPLY', d, rise / a), y_point)
    else:
        top = y_top
    return math_node('DIVIDE', math_node('SUBTRACT', sep.outputs["Y"], y_foot),
                     top - y_foot if not roof else math_node('SUBTRACT', top, y_foot))


def carbon_mat(y_foot=None, y_top=None, mode="ember"):
    """Anthracite: black and glassy, broken into facets that each lean their own way (a
    random tilt per Voronoi cell, added to the normal), split by fine fractures and a few
    larger ones. With y_foot/y_top the fractures glow ember-orange, hottest at the letters'
    feet and cooling up them, and some facets near the feet smoulder. In "heat" mode only
    the letters' feet glow instead, as on the AI plate: an ember band along their lower
    edges, flickering, which runs a little way up the larger cracks."""
    m, nt, b = node_mat("carbon")
    b.inputs["Base Color"].default_value = (*CARBON, 1)
    b.inputs["Coat Weight"].default_value = 0.20
    coord = nt.nodes.new("ShaderNodeTexCoord")
    warp = nt.nodes.new("ShaderNodeTexNoise")
    warp.inputs["Scale"].default_value = 2.0
    warp.inputs["Detail"].default_value = 3.0
    wv = nt.nodes.new("ShaderNodeVectorMath")
    wv.operation = 'MULTIPLY_ADD'
    nt.links.new(warp.outputs["Color"], wv.inputs[0])
    wv.inputs[1].default_value = (0.30, 0.30, 0.30)
    nt.links.new(coord.outputs["Object"], wv.inputs[2])

    def voronoi(scale, feature='F1'):
        v = nt.nodes.new("ShaderNodeTexVoronoi")
        v.feature = feature
        v.inputs["Scale"].default_value = scale
        nt.links.new(wv.outputs["Vector"], v.inputs["Vector"])
        return v

    def edge_mask(scale, width):
        v = voronoi(scale, 'DISTANCE_TO_EDGE')
        r = nt.nodes.new("ShaderNodeMapRange")
        r.inputs["From Max"].default_value = width
        r.inputs["To Min"].default_value = 1.0
        r.inputs["To Max"].default_value = 0.0
        nt.links.new(v.outputs["Distance"], r.inputs["Value"])
        return r.outputs["Result"]

    FACET = 7.5
    facets = voronoi(FACET)
    fine, major = edge_mask(FACET, 0.006), edge_mask(1.5, 0.032)
    crack = nt.nodes.new("ShaderNodeMath")
    crack.operation = 'MAXIMUM'
    nt.links.new(major, crack.inputs[0])
    nt.links.new(fine, crack.inputs[1])
    tilt = nt.nodes.new("ShaderNodeVectorMath")
    tilt.operation = 'SUBTRACT'
    nt.links.new(facets.outputs["Color"], tilt.inputs[0])
    tilt.inputs[1].default_value = (0.5, 0.5, 0.5)
    tscale = nt.nodes.new("ShaderNodeVectorMath")
    tscale.operation = 'SCALE'
    nt.links.new(tilt.outputs["Vector"], tscale.inputs[0])
    tscale.inputs["Scale"].default_value = 0.42 if mode != "heat" else 0.20    # heat: calmer, graphite
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    nsum = nt.nodes.new("ShaderNodeVectorMath")
    nsum.operation = 'ADD'
    nt.links.new(geo.outputs["Normal"], nsum.inputs[0])
    nt.links.new(tscale.outputs["Vector"], nsum.inputs[1])
    nrm = nt.nodes.new("ShaderNodeVectorMath")
    nrm.operation = 'NORMALIZE'
    nt.links.new(nsum.outputs["Vector"], nrm.inputs[0])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.7
    bump.inputs["Distance"].default_value = 0.02
    inv = nt.nodes.new("ShaderNodeMath")
    inv.operation = 'SUBTRACT'
    inv.inputs[0].default_value = 1.0
    nt.links.new(crack.outputs["Value"], inv.inputs[1])
    nt.links.new(inv.outputs["Value"], bump.inputs["Height"])
    nt.links.new(nrm.outputs["Vector"], bump.inputs["Normal"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    rough = nt.nodes.new("ShaderNodeMix")
    rough.inputs[2].default_value = 0.38 if mode != "heat" else 0.50
    rough.inputs[3].default_value = 0.95
    nt.links.new(crack.outputs["Value"], rough.inputs["Factor"])
    nt.links.new(rough.outputs[0], b.inputs["Roughness"])
    if y_foot is not None and mode == "heat":
        band = nt.nodes.new("ShaderNodeMapRange")                 # 1 at the feet, 0 up the band
        band.inputs["From Min"].default_value = y_foot
        band.inputs["From Max"].default_value = y_foot + HEAT_BAND * (y_top - y_foot)
        band.inputs["To Min"].default_value = 1.0
        band.inputs["To Max"].default_value = 0.0
        nt.links.new(world_y(nt), band.inputs["Value"])
        hot = nt.nodes.new("ShaderNodeMath")
        hot.operation = 'POWER'
        nt.links.new(band.outputs["Result"], hot.inputs[0])
        hot.inputs[1].default_value = 2.4
        flick = nt.nodes.new("ShaderNodeTexNoise")
        flick.inputs["Scale"].default_value = 5.0
        flick.inputs["Detail"].default_value = 3.0
        fl = nt.nodes.new("ShaderNodeMapRange")
        fl.inputs["From Min"].default_value = 0.3
        fl.inputs["From Max"].default_value = 0.7
        fl.inputs["To Min"].default_value = 0.45
        fl.inputs["To Max"].default_value = 1.0
        nt.links.new(flick.outputs["Fac"], fl.inputs["Value"])
        glow = nt.nodes.new("ShaderNodeMath")
        glow.operation = 'MULTIPLY'
        nt.links.new(hot.outputs["Value"], glow.inputs[0])
        nt.links.new(fl.outputs["Result"], glow.inputs[1])
        reach = nt.nodes.new("ShaderNodeMath")                   # the cracks carry it further up
        reach.operation = 'POWER'
        nt.links.new(band.outputs["Result"], reach.inputs[0])
        reach.inputs[1].default_value = 0.6
        cglow = nt.nodes.new("ShaderNodeMath")
        cglow.operation = 'MULTIPLY'
        nt.links.new(major, cglow.inputs[0])
        nt.links.new(reach.outputs["Value"], cglow.inputs[1])
        total = nt.nodes.new("ShaderNodeMath")
        total.operation = 'MULTIPLY_ADD'
        nt.links.new(cglow.outputs["Value"], total.inputs[0])
        total.inputs[1].default_value = 0.6
        nt.links.new(glow.outputs["Value"], total.inputs[2])
        strength = nt.nodes.new("ShaderNodeMath")
        strength.operation = 'MULTIPLY'
        nt.links.new(total.outputs["Value"], strength.inputs[0])
        strength.inputs[1].default_value = 2.2
        b.inputs["Emission Color"].default_value = (1.0, 0.24, 0.03, 1)             # deep ember
        nt.links.new(strength.outputs["Value"], b.inputs["Emission Strength"])
    elif y_foot is not None:
        # heat: 1 at the letters' feet, falling to a glow near their tops
        heat = nt.nodes.new("ShaderNodeMapRange")
        heat.inputs["From Min"].default_value = y_foot
        heat.inputs["From Max"].default_value = y_top
        heat.inputs["To Min"].default_value = 1.0
        heat.inputs["To Max"].default_value = 0.18
        nt.links.new(world_y(nt), heat.inputs["Value"])
        hot = nt.nodes.new("ShaderNodeMath")
        hot.operation = 'POWER'
        nt.links.new(heat.outputs["Result"], hot.inputs[0])
        hot.inputs[1].default_value = 1.6
        glow = nt.nodes.new("ShaderNodeMath")              # only the larger cracks glow
        glow.operation = 'MULTIPLY'
        nt.links.new(major, glow.inputs[0])
        nt.links.new(hot.outputs["Value"], glow.inputs[1])
        # smouldering facets near the feet: a random share of the cells, fading upward
        cell = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(facets.outputs["Color"], cell.inputs["Color"])
        pick = nt.nodes.new("ShaderNodeMath")
        pick.operation = 'LESS_THAN'
        nt.links.new(cell.outputs[0], pick.inputs[0])
        pick.inputs[1].default_value = 0.14
        foot = nt.nodes.new("ShaderNodeMath")
        foot.operation = 'POWER'
        nt.links.new(heat.outputs["Result"], foot.inputs[0])
        foot.inputs[1].default_value = 6.0
        smoulder = nt.nodes.new("ShaderNodeMath")
        smoulder.operation = 'MULTIPLY'
        nt.links.new(pick.outputs["Value"], smoulder.inputs[0])
        nt.links.new(foot.outputs["Value"], smoulder.inputs[1])
        total = nt.nodes.new("ShaderNodeMath")
        total.operation = 'MULTIPLY_ADD'
        nt.links.new(smoulder.outputs["Value"], total.inputs[0])
        total.inputs[1].default_value = 0.25
        nt.links.new(glow.outputs["Value"], total.inputs[2])
        strength = nt.nodes.new("ShaderNodeMath")
        strength.operation = 'MULTIPLY'
        nt.links.new(total.outputs["Value"], strength.inputs[0])
        strength.inputs[1].default_value = 5.5
        b.inputs["Emission Color"].default_value = (*EMBER, 1)
        nt.links.new(strength.outputs["Value"], b.inputs["Emission Strength"])
    return m


def forge_mat(y_foot, y_top):
    """The forge seen through the cut letters: white-hot at their feet, through yellow,
    orange and red to near black at their tops, the heat rising in tongues (a noise that
    lifts the gradient in places)."""
    m = bpy.data.materials.new("forge")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (1.6, 0.55, 1.0)       # tongues: tall, not wide
    nt.links.new(geo.outputs["Position"], mapping.inputs["Vector"])
    tongues = nt.nodes.new("ShaderNodeTexNoise")
    tongues.inputs["Scale"].default_value = 2.6
    tongues.inputs["Detail"].default_value = 6.0
    tongues.inputs["Roughness"].default_value = 0.6
    nt.links.new(mapping.outputs["Vector"], tongues.inputs["Vector"])
    t = nt.nodes.new("ShaderNodeMapRange")
    t.inputs["From Min"].default_value = y_foot
    t.inputs["From Max"].default_value = y_top
    nt.links.new(world_y(nt), t.inputs["Value"])
    lift = nt.nodes.new("ShaderNodeMath")
    lift.operation = 'MULTIPLY_ADD'
    nt.links.new(tongues.outputs["Fac"], lift.inputs[0])
    lift.inputs[1].default_value = -0.55                          # hot tongues reach up
    nt.links.new(t.outputs["Result"], lift.inputs[2])
    shift = nt.nodes.new("ShaderNodeMath")
    shift.operation = 'ADD'
    nt.links.new(lift.outputs["Value"], shift.inputs[0])
    shift.inputs[1].default_value = 0.22
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    els = ramp.color_ramp.elements
    stops = [(0.00, (1.0, 0.66, 0.18)), (0.12, (1.0, 0.44, 0.04)), (0.30, (0.95, 0.24, 0.015)),
             (0.50, (0.66, 0.07, 0.008)), (0.72, (0.24, 0.02, 0.004)), (0.90, (0.05, 0.005, 0.001))]
    els[0].position, els[0].color = stops[0][0], (*stops[0][1], 1)
    els[1].position, els[1].color = stops[-1][0], (*stops[-1][1], 1)
    for pos, col in stops[1:-1]:
        e = els.new(pos)
        e.color = (*col, 1)
    nt.links.new(shift.outputs["Value"], ramp.inputs["Fac"])
    # brightness falls with the colour: hot light is strong, the dark top hardly glows. Kept
    # low enough that AgX leaves the orange orange (it runs a strong one to white).
    s = nt.nodes.new("ShaderNodeMapRange")
    s.inputs["From Min"].default_value = 0.0
    s.inputs["From Max"].default_value = 0.9
    s.inputs["To Min"].default_value = 1.7
    s.inputs["To Max"].default_value = 0.30
    nt.links.new(shift.outputs["Value"], s.inputs["Value"])
    # sparks: short streaks flying up, a sparse field of points stretched upward, brighter low
    smap = nt.nodes.new("ShaderNodeMapping")
    smap.inputs["Scale"].default_value = (13.0, 3.2, 1.0)
    nt.links.new(geo.outputs["Position"], smap.inputs["Vector"])
    pts = nt.nodes.new("ShaderNodeTexVoronoi")
    pts.inputs["Scale"].default_value = 1.0
    nt.links.new(smap.outputs["Vector"], pts.inputs["Vector"])
    core = nt.nodes.new("ShaderNodeMapRange")
    core.inputs["From Min"].default_value = 0.0
    core.inputs["From Max"].default_value = 0.10
    core.inputs["To Min"].default_value = 1.0
    core.inputs["To Max"].default_value = 0.0
    nt.links.new(pts.outputs["Distance"], core.inputs["Value"])
    keep = nt.nodes.new("ShaderNodeSeparateColor")                 # only some cells hold a spark
    nt.links.new(pts.outputs["Color"], keep.inputs["Color"])
    few = nt.nodes.new("ShaderNodeMath")
    few.operation = 'GREATER_THAN'
    nt.links.new(keep.outputs[0], few.inputs[0])
    few.inputs[1].default_value = 0.52
    spark = nt.nodes.new("ShaderNodeMath")
    spark.operation = 'MULTIPLY'
    nt.links.new(core.outputs["Result"], spark.inputs[0])
    nt.links.new(few.outputs["Value"], spark.inputs[1])
    sp_col = nt.nodes.new("ShaderNodeMix")
    sp_col.data_type = 'RGBA'
    nt.links.new(spark.outputs["Value"], sp_col.inputs["Factor"])
    nt.links.new(ramp.outputs["Color"], sp_col.inputs[6])
    sp_col.inputs[7].default_value = (1.0, 0.80, 0.40, 1)
    nt.links.new(sp_col.outputs[2], em.inputs["Color"])
    sp_str = nt.nodes.new("ShaderNodeMath")
    sp_str.operation = 'MULTIPLY_ADD'
    nt.links.new(spark.outputs["Value"], sp_str.inputs[0])
    sp_str.inputs[1].default_value = 4.0
    nt.links.new(s.outputs["Result"], sp_str.inputs[2])
    nt.links.new(sp_str.outputs["Value"], em.inputs["Strength"])
    return m


def ramp_node(nt, stops):
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    els = ramp.color_ramp.elements
    els[0].position, els[0].color = stops[0][0], (*stops[0][1], 1)
    els[1].position, els[1].color = stops[-1][0], (*stops[-1][1], 1)
    for pos, col in stops[1:-1]:
        e = els.new(pos)
        e.color = (*col, 1)
    return ramp


LAVA_PEAK = 6.0                                # the bed's glow at the letters' feet


FIRE_LIGHT = []                                # each fire material's light multiple (see fire_light)


def fire_light(nt, strength):
    """An emission strength that lights the scene (owner: the glow is a light, so it lights
    and shadows the plate as the sun does, and fills the sun's shadows where it reaches):
    to the camera the fire is as bright as `strength`, as tuned; to every other ray, the
    light it casts and its reflections, CARBON_LIGHT times that. (Cycles samples a light
    with no ray type, so only the camera's view is set apart.)"""
    lp = nt.nodes.new("ShaderNodeLightPath")
    k = nt.nodes.new("ShaderNodeMath")
    k.operation = 'MULTIPLY_ADD'                                   # camera ? 1 : CARBON_LIGHT
    nt.links.new(lp.outputs["Is Camera Ray"], k.inputs[0])
    k.inputs[1].default_value = 1.0 - CARBON_LIGHT
    k.inputs[2].default_value = CARBON_LIGHT
    FIRE_LIGHT.append(k)
    m = nt.nodes.new("ShaderNodeMath")
    m.operation = 'MULTIPLY'
    nt.links.new(strength, m.inputs[0])
    nt.links.new(k.outputs["Value"], m.inputs[1])
    return m.outputs["Value"]


def fire_colour(nt, colour):
    """The fire's colour as seen, and FIRE_TINT warmer in the light it casts."""
    lp = nt.nodes.new("ShaderNodeLightPath")
    warm = nt.nodes.new("ShaderNodeMix")
    warm.data_type, warm.blend_type = 'RGBA', 'MULTIPLY'
    warm.inputs["Factor"].default_value = 1.0
    nt.links.new(colour, warm.inputs[6])
    warm.inputs[7].default_value = (*FIRE_TINT, 1)
    pick = nt.nodes.new("ShaderNodeMix")
    pick.data_type = 'RGBA'
    nt.links.new(lp.outputs["Is Camera Ray"], pick.inputs["Factor"])
    nt.links.new(warm.outputs[2], pick.inputs[6])
    nt.links.new(colour, pick.inputs[7])
    return pick.outputs[2]


def lava_mat(y_foot, y_top, roof=None):
    """The glowing bed under the coal, seen in the cracks between the lumps (owner's
    reference): white-hot at the letters' feet, through yellow and orange to red a quarter
    of the way up, then the red dying away to nothing three quarters of the way up (owner),
    with a slow flicker. Moulded letters (roof) are measured up their own height, so the heat
    slopes with their tops."""
    m = bpy.data.materials.new("lava")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    t = nt.nodes.new("ShaderNodeMapRange")                        # the share of the way up, 0..1
    nt.links.new(height_share(nt, y_foot, y_top, roof), t.inputs["Value"])
    # white to red over the first quarter of the letters' height, red to nothing over the next
    # half (owner)
    ramp = ramp_node(nt, [(0.0, (1.0, 0.95, 0.82)), (0.07, (1.0, 0.78, 0.30)), (0.15, (1.0, 0.46, 0.06)),
                          (0.25, (0.90, 0.13, 0.01)), (0.50, (0.62, 0.05, 0.005)), (0.75, (0.30, 0.02, 0.0)),
                          (1.0, (0.0, 0.0, 0.0))])
    nt.links.new(t.outputs["Result"], ramp.inputs["Fac"])
    nt.links.new(fire_colour(nt, ramp.outputs["Color"]), em.inputs["Color"])
    flick = nt.nodes.new("ShaderNodeTexNoise")
    flick.inputs["Scale"].default_value = 7.0
    fl = nt.nodes.new("ShaderNodeMapRange")
    fl.inputs["From Min"].default_value = 0.3
    fl.inputs["From Max"].default_value = 0.7
    fl.inputs["To Min"].default_value = 0.7
    fl.inputs["To Max"].default_value = 1.15
    nt.links.new(flick.outputs["Fac"], fl.inputs["Value"])
    # its strength by height, a share of LAVA_PEAK: full at the feet, 40% at a quarter of the
    # way up (the red), nothing at three quarters
    s = ramp_node(nt, [(0.0, (1.0, 1.0, 1.0)), (0.25, (0.40, 0.40, 0.40)), (0.75, (0.0, 0.0, 0.0)),
                       (1.0, (0.0, 0.0, 0.0))])
    nt.links.new(t.outputs["Result"], s.inputs["Fac"])
    peak = nt.nodes.new("ShaderNodeMath")
    peak.operation = 'MULTIPLY'
    nt.links.new(s.outputs["Color"], peak.inputs[0])
    peak.inputs[1].default_value = LAVA_PEAK
    st = nt.nodes.new("ShaderNodeMath")
    st.operation = 'MULTIPLY'
    nt.links.new(peak.outputs["Value"], st.inputs[0])
    nt.links.new(fl.outputs["Result"], st.inputs[1])
    nt.links.new(fire_light(nt, st.outputs["Value"]), em.inputs["Strength"])
    return m


def coal_surface(nt, b):
    """Coal: dark and gritty, grey where a face catches the light."""
    grain = nt.nodes.new("ShaderNodeTexNoise")
    grain.inputs["Scale"].default_value = 90.0
    grain.inputs["Detail"].default_value = 8.0
    tone = nt.nodes.new("ShaderNodeMapRange")
    tone.inputs["To Min"].default_value = 0.010
    tone.inputs["To Max"].default_value = 0.030
    nt.links.new(grain.outputs["Fac"], tone.inputs["Value"])
    nt.links.new(tone.outputs["Result"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.60                 # a dull sheen on the facets
    b.inputs["Specular IOR Level"].default_value = 0.30
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.15
    bump.inputs["Distance"].default_value = 0.01
    nt.links.new(grain.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])


def coal_rock_mat(y_foot, y_top, roof=None):
    """The lumps: dark, gritty coal, grey where a face catches the light; the lumps low down
    glow from within on the bed's scale, white-hot at the feet and red a quarter of the way
    up, fading out by halfway (the cracks carry the red on up)."""
    m, nt, b = node_mat("coal_lump")
    coal_surface(nt, b)
    heat = nt.nodes.new("ShaderNodeMapRange")                    # 1 at the feet, 0 halfway up
    heat.inputs["From Max"].default_value = 0.50
    heat.inputs["To Min"].default_value = 1.0
    heat.inputs["To Max"].default_value = 0.0
    nt.links.new(height_share(nt, y_foot, y_top, roof), heat.inputs["Value"])
    hot = nt.nodes.new("ShaderNodeMath")
    hot.operation = 'POWER'
    nt.links.new(heat.outputs["Result"], hot.inputs[0])
    hot.inputs[1].default_value = 1.6
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    blotch = nt.nodes.new("ShaderNodeTexNoise")                  # in world space: one field across
    blotch.inputs["Scale"].default_value = 5.0                    # the word, not a pattern per lump
    nt.links.new(geo.outputs["Position"], blotch.inputs["Vector"])
    bl = nt.nodes.new("ShaderNodeMapRange")
    bl.inputs["From Min"].default_value = 0.30
    bl.inputs["From Max"].default_value = 0.70
    bl.inputs["To Min"].default_value = 0.70
    bl.inputs["To Max"].default_value = 1.0
    nt.links.new(blotch.outputs["Fac"], bl.inputs["Value"])
    glow = nt.nodes.new("ShaderNodeMath")
    glow.operation = 'MULTIPLY'
    nt.links.new(hot.outputs["Value"], glow.inputs[0])
    nt.links.new(bl.outputs["Result"], glow.inputs[1])
    col = ramp_node(nt, [(0.0, (0.60, 0.05, 0.005)), (0.50, (0.95, 0.18, 0.02)), (0.80, (1.0, 0.50, 0.08)),
                         (1.0, (1.0, 0.88, 0.60))])
    nt.links.new(heat.outputs["Result"], col.inputs["Fac"])
    nt.links.new(fire_colour(nt, col.outputs["Color"]), b.inputs["Emission Color"])
    st = nt.nodes.new("ShaderNodeMath")
    st.operation = 'MULTIPLY'
    nt.links.new(glow.outputs["Value"], st.inputs[0])
    st.inputs[1].default_value = 2.6
    nt.links.new(fire_light(nt, st.outputs["Value"]), b.inputs["Emission Strength"])
    return m


def heat_field(polys, box, res=HEAT_RES):
    """The letters' signed distance, in the plate's units, on a grid over box (x0, x1, y0, y1)
    `res` points to a unit: positive inside a letter (its outline and counters, even-odd),
    negative outside. Kept as a float image, packed into the scene, that the coal hexes'
    materials read by position (field_sdf)."""
    x0, x1, y0, y1 = box
    nx, ny = math.ceil((x1 - x0) * res), math.ceil((y1 - y0) * res)
    X, Y = np.meshgrid(x0 + (np.arange(nx) + 0.5) / res, y0 + (np.arange(ny) + 0.5) / res)
    dist = np.full(X.shape, np.inf)
    inside = np.zeros(X.shape, bool)
    for poly in polys:
        P = np.asarray(poly, float)
        for (ax, ay), (bx, by) in zip(P, np.roll(P, -1, axis=0)):
            dx, dy = bx - ax, by - ay
            t = np.clip(((X - ax) * dx + (Y - ay) * dy) / max(dx * dx + dy * dy, 1e-12), 0.0, 1.0)
            dist = np.minimum(dist, np.hypot(X - ax - t * dx, Y - ay - t * dy))
            if dy != 0:
                inside ^= ((ay > Y) != (by > Y)) & (X < ax + (Y - ay) * dx / dy)
    px = np.ones((ny, nx, 4), np.float32)
    px[..., :3] = np.where(inside, dist, -dist)[..., None]
    img = bpy.data.images.new("carbon_heat", nx, ny, alpha=False, float_buffer=True)
    img.colorspace_settings.name = 'Non-Color'
    img.pixels.foreach_set(px.ravel())
    img.file_format = 'OPEN_EXR'
    img.pack()
    sdf = px[..., 0]

    def at(x, y):
        """The signed distance at (x, y), from the grid's nearest point."""
        return float(sdf[min(max(int((y - y0) * res), 0), ny - 1), min(max(int((x - x0) * res), 0), nx - 1)])
    return dict(image=img, x0=x0, y0=y0, w=nx / res, h=ny / res, at=at)


def math_node(nt, op, *ins, clamp=False):
    """A Math node on sockets or numbers; its result."""
    m = nt.nodes.new("ShaderNodeMath")
    m.operation, m.use_clamp = op, clamp
    for sock, v in zip(m.inputs, ins):
        if isinstance(v, (int, float)):
            sock.default_value = v
        else:
            nt.links.new(v, sock)
    return m.outputs["Value"]


def field_sdf(nt, F):
    """The letters' signed distance (heat_field) where the surface is."""
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    uv = nt.nodes.new("ShaderNodeVectorMath")
    uv.operation = 'MULTIPLY_ADD'
    nt.links.new(geo.outputs["Position"], uv.inputs[0])
    uv.inputs[1].default_value = (1.0 / F["w"], 1.0 / F["h"], 0.0)
    uv.inputs[2].default_value = (-F["x0"] / F["w"], -F["y0"] / F["h"], 0.0)
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image, tex.extension, tex.interpolation = F["image"], 'EXTEND', 'Linear'
    nt.links.new(uv.outputs["Vector"], tex.inputs["Vector"])
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tex.outputs["Color"], sep.inputs["Color"])
    return sep.outputs[0]


def heat_w(nt, sdf, half=None):
    """The heat as one number from the letters' signed distance (owner): 1 in the middle of a
    stroke (`half` in, HEAT_HALF unless given), 0.5 at a letter's edge, and away from the
    letters falling off exponentially (over EMBER_FADE) toward 0."""
    w_in = math_node(nt, 'MULTIPLY_ADD', math_node(nt, 'MULTIPLY', sdf, 1.0 / (half or HEAT_HALF), clamp=True),
                     0.5, 0.5)
    far = math_node(nt, 'MAXIMUM', math_node(nt, 'MULTIPLY', sdf, -1.0), 0.0)
    w_out = math_node(nt, 'MULTIPLY', math_node(nt, 'EXPONENT', math_node(nt, 'MULTIPLY', far, -1.0 / EMBER_FADE)), 0.5)
    inside = math_node(nt, 'GREATER_THAN', sdf, 0.0)
    return math_node(nt, 'MULTIPLY_ADD', inside, math_node(nt, 'SUBTRACT', w_in, w_out), w_out)


def ember_bed_mat(F):
    """The glowing bed under the coal hexes, seen in the cracks (owner): in the letters,
    white-hot in the middle of each stroke and red by its edges, its outer quarter; round
    them, red, fading away from the letters but never quite out (EMBER_FLOOR); a slow
    flicker."""
    m = bpy.data.materials.new("ember_bed")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    w = heat_w(nt, field_sdf(nt, F))
    col = ramp_node(nt, HEAT_COLOURS)
    nt.links.new(w, col.inputs["Fac"])
    nt.links.new(fire_colour(nt, col.outputs["Color"]), em.inputs["Color"])
    s = ramp_node(nt, [(0.0, (EMBER_FLOOR * 0.40,) * 3), (0.50, (0.40,) * 3), (0.625, (0.55,) * 3), (1.0, (1.0,) * 3)])
    nt.links.new(w, s.inputs["Fac"])
    flick = nt.nodes.new("ShaderNodeTexNoise")
    flick.inputs["Scale"].default_value = 7.0
    fl = nt.nodes.new("ShaderNodeMapRange")
    fl.inputs["From Min"].default_value, fl.inputs["From Max"].default_value = 0.3, 0.7
    fl.inputs["To Min"].default_value, fl.inputs["To Max"].default_value = 0.7, 1.15
    nt.links.new(flick.outputs["Fac"], fl.inputs["Value"])
    st = math_node(nt, 'MULTIPLY', math_node(nt, 'MULTIPLY', s.outputs["Color"], EMBER_PEAK), fl.outputs["Result"])
    nt.links.new(fire_light(nt, st), em.inputs["Strength"])
    return m


def coal_ground_mat():
    """The dark lumps round CARBON on the coal hexes, coal as coal_rock_mat's."""
    m, nt, b = node_mat("coal_ground")
    coal_surface(nt, b)
    return m


def letter_glow_mat(F):
    """CARBON's letters on the coal hexes: solid, with no cracks (owner), white-hot only in
    the middle of each stroke, through yellow and orange to red in its outer quarter, as the
    bed's (HEAT_COLOURS)."""
    m = bpy.data.materials.new("letter_glow")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    w = heat_w(nt, field_sdf(nt, F), LETTER_HALF)
    col = ramp_node(nt, HEAT_COLOURS)
    nt.links.new(w, col.inputs["Fac"])
    nt.links.new(fire_colour(nt, col.outputs["Color"]), em.inputs["Color"])
    s = ramp_node(nt, [(0.30, (0.25,) * 3), (0.50, (0.40,) * 3), (0.625, (0.55,) * 3), (1.0, (1.0,) * 3)])
    nt.links.new(w, s.inputs["Fac"])
    nt.links.new(fire_light(nt, math_node(nt, 'MULTIPLY', s.outputs["Color"], LETTER_GLOW)), em.inputs["Strength"])
    return m


def rough_outline(outline, rng, spill=()):
    """An outline (counter-clockwise) with a crumbled edge: cut into pieces about a lump's
    third long, each point moved in by up to COAL_ROUGH, or along the edges in `spill` (by
    index) out by up to that, where the coal spills over what it sits on."""
    out = []
    n = len(outline)
    for i in range(n):
        (ax, ay), (bx, by) = outline[i], outline[(i + 1) % n]
        L_ = math.hypot(bx - ax, by - ay)
        nx, ny = (by - ay) / L_, -(bx - ax) / L_                 # outward
        k = max(1, round(L_ / 0.05))
        for j in range(k):
            t = j / k
            d = rng.uniform(0.0, COAL_ROUGH) if i in spill else -rng.uniform(0.0, COAL_ROUGH)
            if j == 0:
                d *= 0.4                                          # corners stay near their places
            out.append((ax + (bx - ax) * t + nx * d, ay + (by - ay) * t + ny * d))
    return out


def white_hot_mat(F):
    """CARBON white-hot (owner): white over the letters, yellowing and then orange only toward
    their edges and down their bevels."""
    m = bpy.data.materials.new("white_hot")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    w = heat_w(nt, field_sdf(nt, F), HOT_HALF)
    col = ramp_node(nt, HOT_COLOURS)
    nt.links.new(w, col.inputs["Fac"])
    nt.links.new(fire_colour(nt, col.outputs["Color"]), em.inputs["Color"])
    s = ramp_node(nt, [(0.40, (0.6,) * 3), (0.55, (0.85,) * 3), (0.70, (1.0,) * 3)])
    nt.links.new(w, s.inputs["Fac"])
    nt.links.new(fire_light(nt, math_node(nt, 'MULTIPLY', s.outputs["Color"], HOT_GLOW)), em.inputs["Strength"])
    return m


def melt_mat(F):
    """The melt round the white-hot letters' feet (owner: a slight melt where they meet the
    metal): scorched dark metal, glowing orange at the letter and cooling through red to
    nothing at its outer edge."""
    m, nt, b = node_mat("melt")
    b.inputs["Base Color"].default_value = (0.03, 0.025, 0.02, 1)
    b.inputs["Metallic"].default_value = 0.6
    b.inputs["Roughness"].default_value = 0.45
    out = math_node(nt, 'MULTIPLY', field_sdf(nt, F), -1.0 / (MELT_W + MELT_H), clamp=True)   # 0 at the letter
    col = ramp_node(nt, [(0.0, (1.0, 0.62, 0.16)), (0.35, (1.0, 0.32, 0.04)), (0.70, (0.75, 0.08, 0.01)),
                         (1.0, (0.2, 0.01, 0.0))])
    nt.links.new(out, col.inputs["Fac"])
    nt.links.new(fire_colour(nt, col.outputs["Color"]), b.inputs["Emission Color"])
    st = ramp_node(nt, [(0.0, (1.6,) * 3), (0.6, (0.6,) * 3), (1.0, (0.0,) * 3)])
    nt.links.new(out, st.inputs["Fac"])
    nt.links.new(fire_light(nt, st.outputs["Color"]), b.inputs["Emission Strength"])
    return m


def dish_silver_mat():
    """The AND dish's bright silver (owner): satin rather than polished, and not wholly metal,
    so its floor, seen head-on, is lit by the sun as the face beside it is instead of
    mirroring the dim sky; fine brushing across it, and its slopes catch the light."""
    m, nt, b = node_mat("dish_silver")
    b.inputs["Base Color"].default_value = (0.86, 0.87, 0.90, 1)
    b.inputs["Metallic"].default_value = 0.88
    coord = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (1.0, 140.0, 1.0)
    nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    streak = nt.nodes.new("ShaderNodeTexNoise")
    streak.inputs["Scale"].default_value = 9.0
    streak.inputs["Detail"].default_value = 10.0
    nt.links.new(mapping.outputs["Vector"], streak.inputs["Vector"])
    rough = nt.nodes.new("ShaderNodeMapRange")
    rough.inputs["To Min"].default_value, rough.inputs["To Max"].default_value = 0.26, 0.40
    nt.links.new(streak.outputs["Fac"], rough.inputs["Value"])
    nt.links.new(rough.outputs["Result"], b.inputs["Roughness"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.10
    nt.links.new(streak.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def frustum(name, bottom, z0, top, z1, mat=None):
    """A solid between two outlines of as many points (counter-clockwise), `bottom` at z0 and
    `top` at z1: sloping sides where they differ."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    vb = [bm.verts.new((x, y, z0)) for x, y in bottom]
    vt = [bm.verts.new((x, y, z1)) for x, y in top]
    bm.faces.new(list(reversed(vb)))
    bm.faces.new(vt)
    n = len(vb)
    for i in range(n):
        bm.faces.new((vb[i], vb[(i + 1) % n], vt[(i + 1) % n], vt[i]))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new(name, me))
    if mat:
        me.materials.append(mat)
    return ob


def clean_poly(poly, tol=1e-4):
    """A polygon without repeated points or points on a straight run (the moulded letters'
    edges are cut into pieces), which inset() cannot offset."""
    pts = list(poly)
    changed = True
    while changed and len(pts) > 3:
        changed = False
        for i in range(len(pts)):
            a, b, c = pts[i - 1], pts[i], pts[(i + 1) % len(pts)]
            ab, bc = math.hypot(b[0] - a[0], b[1] - a[1]), math.hypot(c[0] - b[0], c[1] - b[1])
            if ab < 1e-6 or bc < 1e-6 or \
                    abs((b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])) < tol * ab * bc:
                del pts[i]
                changed = True
                break
    return pts


def offset_poly(poly, d, limit=2.0):
    """A polygon (counter-clockwise) moved out by d (in, where d is negative), its corners
    mitred; but a sharp corner, whose mitre would reach further than `limit` times d, is cut
    off square instead of running out to a spike."""
    n = len(poly)
    out = []
    for i in range(n):
        a, b, c = poly[i - 1], poly[i], poly[(i + 1) % n]
        n0 = ((b[1] - a[1]), -(b[0] - a[0]))                      # outward normals of the two edges
        n1 = ((c[1] - b[1]), -(c[0] - b[0]))
        l0, l1 = math.hypot(*n0), math.hypot(*n1)
        n0, n1 = (n0[0] / l0, n0[1] / l0), (n1[0] / l1, n1[1] / l1)
        bis = (n0[0] + n1[0], n0[1] + n1[1])
        lb = math.hypot(*bis)
        cos_half = lb / 2.0                                       # the cosine of half the turn
        if lb > 1e-9 and 1.0 / cos_half <= limit:
            k = d / (cos_half * lb)                               # along the bisector, to the mitre
            out.append((b[0] + bis[0] * k, b[1] + bis[1] * k))
        else:
            out += [(b[0] + n0[0] * d, b[1] + n0[1] * d), (b[0] + n1[0] * d, b[1] + n1[1] * d)]
    return out


def poly_curve(name, polys):
    """Closed polygons as a 2D curve, filled even-odd (so a polygon inside another is a hole)."""
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions = '2D'
    cu.fill_mode = 'BOTH'
    for poly in polys:
        sp = cu.splines.new('POLY')
        sp.points.add(len(poly) - 1)
        for pt, (x, y) in zip(sp.points, poly):
            pt.co = (x, y, 0.0, 1.0)
        sp.use_cyclic_u = True
    return cu


def brushed_silver_mat():
    """Brushed silver (owner): bright metal with fine streaks running across the letters, in
    its roughness and a faint bump, so it catches the light as a soft sheen."""
    m, nt, b = node_mat("brushed_silver")
    b.inputs["Metallic"].default_value = 1.0
    geo = nt.nodes.new("ShaderNodeNewGeometry")                   # brighter toward the light
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Position"], sep.inputs["Vector"])
    diag = nt.nodes.new("ShaderNodeMath")
    diag.operation = 'SUBTRACT'
    nt.links.new(sep.outputs["X"], diag.inputs[0])
    nt.links.new(sep.outputs["Y"], diag.inputs[1])
    t = nt.nodes.new("ShaderNodeMapRange")
    t.inputs["From Min"].default_value = -1.2
    t.inputs["From Max"].default_value = 1.2
    nt.links.new(diag.outputs["Value"], t.inputs["Value"])
    tint = nt.nodes.new("ShaderNodeMix")
    tint.data_type = 'RGBA'
    tint.inputs[6].default_value = (0.99, 0.99, 1.0, 1)
    tint.inputs[7].default_value = (0.74, 0.75, 0.78, 1)
    nt.links.new(t.outputs["Result"], tint.inputs["Factor"])
    nt.links.new(tint.outputs[2], b.inputs["Base Color"])
    coord = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (1.0, 120.0, 1.0)
    nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    streak = nt.nodes.new("ShaderNodeTexNoise")
    streak.inputs["Scale"].default_value = 9.0
    streak.inputs["Detail"].default_value = 12.0
    nt.links.new(mapping.outputs["Vector"], streak.inputs["Vector"])
    rough = nt.nodes.new("ShaderNodeMapRange")
    rough.inputs["To Min"].default_value = 0.16
    rough.inputs["To Max"].default_value = 0.36
    nt.links.new(streak.outputs["Fac"], rough.inputs["Value"])
    nt.links.new(rough.outputs["Result"], b.inputs["Roughness"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.10
    nt.links.new(streak.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def silver_mat():
    m, nt, b = node_mat("silver")
    b.inputs["Base Color"].default_value = (0.92, 0.92, 0.94, 1)
    b.inputs["Metallic"].default_value = 0.85
    b.inputs["Roughness"].default_value = 0.26             # satin: it catches the key as a broad sheen
    return m


def clip_halfplane(poly, n, c):
    """The part of a convex or simple polygon where n . p <= c (Sutherland-Hodgman)."""
    out = []
    for i in range(len(poly)):
        p, q = poly[i], poly[(i + 1) % len(poly)]
        dp = n[0] * p[0] + n[1] * p[1] - c
        dq = n[0] * q[0] + n[1] * q[1] - c
        if dp <= 0:
            out.append(p)
        if (dp <= 0) != (dq <= 0):
            t = dp / (dp - dq)
            out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
    return out


def poly_area(poly):
    return 0.5 * sum(poly[i][0] * poly[i - 1][1] - poly[i - 1][0] * poly[i][1] for i in range(len(poly)))


def coal_letters(flat, rock, rng, spacing=0.15, shrink=0.80, height=(0.15, 0.25), prefix="coal", tries_per_area=0.0,
                 min_side=0.28, min_round=0.0, loose=None):
    """Each letter of a flat word (its filled glyphs, a mesh) broken into lumps of coal: a
    Voronoi cell per seed scattered over the letter, the letter cut to each cell, each piece
    shrunk a little toward its middle (the cracks between lumps show the bed below), raised
    to a random height with its top tilted and poked into facets, so it is angular. Any flat
    region will do: a large one (the coal hexes round the letters) gets tries_per_area seeds
    tried to a unit of area, if that is more than a letter's 4000, and its triangles and
    seeds are kept in grids so it stays quick. A piece smaller than min_side of the spacing
    squared is left out, so the bed shows there, and so is one thinner than min_round (its
    area over its perimeter squared: a square's is 0.0625, a sliver's small). With `loose` (a
    dict), the coal is less orderly: lumps of mixed sizes (each seed's spacing times a factor
    in sizes), each shrunk by its own amount (a range), turned up to twist degrees, nudged up
    to jitter of the spacing and tilted up to tilt. Returns the lumps."""
    bm = bmesh.new()
    bm.from_mesh(flat.data)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    mw = flat.matrix_world
    # the glyphs: islands of triangles
    comp, letters = {}, []
    for f in bm.faces:
        if f in comp:
            continue
        comp[f] = len(letters)
        stack, tris = [f], []
        while stack:
            g = stack.pop()
            tris.append([tuple((mw @ v.co)[:2]) for v in g.verts])
            for e in g.edges:
                for h in e.link_faces:
                    if h not in comp:
                        comp[h] = comp[f]
                        stack.append(h)
        letters.append(tris)
    bm.free()
    made = []
    for li, tris in enumerate(letters):
        xs = [p[0] for t in tris for p in t]
        ys = [p[1] for t in tris for p in t]
        x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
        B = 2.0 * spacing                                         # the triangles' grid
        grid = {}
        for ti, t in enumerate(tris):
            for gx in range(math.floor(min(p[0] for p in t) / B), math.floor(max(p[0] for p in t) / B) + 1):
                for gy in range(math.floor(min(p[1] for p in t) / B), math.floor(max(p[1] for p in t) / B) + 1):
                    grid.setdefault((gx, gy), []).append(ti)

        def near(ax_, bx_, ay_, by_):
            """The triangles that may meet the box (in their order)."""
            found = set()
            for gx in range(math.floor(ax_ / B), math.floor(bx_ / B) + 1):
                for gy in range(math.floor(ay_ / B), math.floor(by_ / B) + 1):
                    found.update(grid.get((gx, gy), ()))
            return [tris[i] for i in sorted(found)]

        def inside(x, y):
            for (ax, ay), (bx, by), (cx_, cy_) in near(x, x, y, y):
                d = (by - cy_) * (ax - cx_) + (cx_ - bx) * (ay - cy_)
                if abs(d) < 1e-12:
                    continue
                u = ((by - cy_) * (x - cx_) + (cx_ - bx) * (y - cy_)) / d
                v = ((cy_ - ay) * (x - cx_) + (ax - cx_) * (y - cy_)) / d
                if u >= 0 and v >= 0 and u + v <= 1:
                    return True
            return False

        seeds, taken, tries = [], {}, 0                          # taken: the seeds' grid
        grid_s = spacing * (loose["sizes"][1] if loose else 1.0)

        def free(x, y, f):
            gx, gy = math.floor(x / grid_s), math.floor(y / grid_s)
            return all((x - a) ** 2 + (y - b) ** 2 >= (spacing * (f + g) / 2) ** 2
                       for i in (-1, 0, 1) for j in (-1, 0, 1) for a, b, g in taken.get((gx + i, gy + j), ()))
        n_tries = max(4000, int(sum(abs(poly_area(t)) for t in tris) * tries_per_area))
        while tries < n_tries:
            tries += 1
            x, y = rng.uniform(x0, x1), rng.uniform(y0, y1)
            f = rng.uniform(*loose["sizes"]) if loose else 1.0
            if inside(x, y) and free(x, y, f):
                seeds.append((x, y))
                taken.setdefault((math.floor(x / grid_s), math.floor(y / grid_s)), []).append((x, y, f))
        box = [(x0 - 1, y0 - 1), (x1 + 1, y0 - 1), (x1 + 1, y1 + 1), (x0 - 1, y1 + 1)]
        for si, (sx, sy) in enumerate(seeds):
            cell = box
            for tj, (tx, ty) in enumerate(seeds):
                if tj == si or (tx - sx) ** 2 + (ty - sy) ** 2 > (5 * spacing) ** 2:
                    continue
                n = (tx - sx, ty - sy)
                c = n[0] * (sx + tx) / 2 + n[1] * (sy + ty) / 2
                cell = clip_halfplane(cell, n, c)
                if len(cell) < 3:
                    break
            if len(cell) < 3:
                continue
            # the letter cut to the cell: each triangle clipped by the cell's edges
            pieces = []
            for t in near(min(p[0] for p in cell), max(p[0] for p in cell), min(p[1] for p in cell),
                          max(p[1] for p in cell)):
                piece = list(t)
                if poly_area(piece) < 0:
                    piece.reverse()
                for k in range(len(cell)):
                    (ax, ay), (bx, by) = cell[k], cell[(k + 1) % len(cell)]
                    piece = clip_halfplane(piece, (by - ay, -(bx - ax)), (by - ay) * ax - (bx - ax) * ay)
                    if len(piece) < 3:
                        break
                if len(piece) >= 3 and abs(poly_area(piece)) > 1e-7:
                    pieces.append(piece)
            area = sum(abs(poly_area(pc)) for pc in pieces)
            if area < (spacing * min_side) ** 2:
                continue
            me = bpy.data.meshes.new("%s_%d_%d" % (prefix, li, si))
            cb = bmesh.new()
            for pc in pieces:
                try:
                    cb.faces.new([cb.verts.new((x, y, 0.0)) for x, y in pc])
                except ValueError:
                    pass
            bmesh.ops.remove_doubles(cb, verts=cb.verts, dist=1e-5)
            if min_round:
                rim = sum(e.calc_length() for e in cb.edges if len(e.link_faces) == 1)
                if not cb.faces or sum(f.calc_area() for f in cb.faces) < min_round * rim * rim:
                    cb.free()
                    bpy.data.meshes.remove(me)
                    continue
            mx = sum(v.co.x for v in cb.verts) / len(cb.verts)
            my = sum(v.co.y for v in cb.verts) / len(cb.verts)
            k = rng.uniform(*loose["shrink"]) if loose else shrink
            for v in cb.verts:
                v.co.x = mx + (v.co.x - mx) * k
                v.co.y = my + (v.co.y - my) * k
            base_faces = list(cb.faces)
            ret = bmesh.ops.extrude_face_region(cb, geom=base_faces)
            top_v = [g for g in ret["geom"] if isinstance(g, bmesh.types.BMVert)]
            top_f = [g for g in ret["geom"] if isinstance(g, bmesh.types.BMFace)]
            h = rng.uniform(*height)
            bmesh.ops.translate(cb, vec=(0, 0, h), verts=top_v)
            bmesh.ops.reverse_faces(cb, faces=base_faces)
            tv = set(top_v)
            tf = set(top_f)
            inner = [e for e in cb.edges if all(v in tv for v in e.verts) and sum(f in tf for f in e.link_faces) == 2]
            if inner:
                bmesh.ops.dissolve_edges(cb, edges=inner, use_verts=True)
            top_f = [f for f in cb.faces if all(v.co.z > h * 0.5 for v in f.verts)]
            poked = bmesh.ops.poke(cb, faces=top_f)
            for v in poked["verts"]:
                v.co.z += rng.uniform(0.02, 0.07)
                v.co.x += rng.uniform(-0.25, 0.25) * spacing * 0.5
                v.co.y += rng.uniform(-0.25, 0.25) * spacing * 0.5
            tl = loose["tilt"] if loose else 0.25
            ta, tb = rng.uniform(-tl, tl), rng.uniform(-tl, tl)
            for v in cb.verts:
                if v.co.z > 0.01:
                    v.co.z += ta * (v.co.x - mx) + tb * (v.co.y - my)
            if loose:                                                 # turned and nudged off its cell
                th = math.radians(rng.uniform(-loose["twist"], loose["twist"]))
                dx, dy = rng.uniform(-1, 1) * loose["jitter"] * spacing, rng.uniform(-1, 1) * loose["jitter"] * spacing
                cs, sn = math.cos(th), math.sin(th)
                for v in cb.verts:
                    u, w_ = v.co.x - mx, v.co.y - my
                    v.co.x, v.co.y = mx + cs * u - sn * w_ + dx, my + sn * u + cs * w_ + dy
            bmesh.ops.recalc_face_normals(cb, faces=list(cb.faces))
            cb.to_mesh(me)
            cb.free()
            ob = link(bpy.data.objects.new(me.name, me))
            me.materials.append(rock)
            made.append(ob)
    return made


def glow_mat(name, rgb, strength):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*rgb, 1)
    em.inputs["Strength"].default_value = strength
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return m


# ------------------------------------------------------------------ text
# An octagonal alphabet for the three words (owner: the tops and bottoms of letters such as C
# and A octagonal). On a cap height of 10, on Impact's tall, heavy, condensed proportions:
# every curve is a 45-degree chamfer (OC outside, IC round the counters), stems stay square,
# the O an octagon, the A's apex a wide chamfered top, the C's terminals blunt blocks. Only the
# letters the plate spells are drawn.
OCT_H, OCT_S, OCT_T, OCT_OC, OCT_IC, OCT_GAP = 10.0, 1.75, 1.6, 1.5, 0.55, 0.7
RLEG_UPRIGHT = 0.45                            # the share of R's leg, from the foot, that stands upright
OCTAGON = args.letters == "octagon"


def oct_glyph(ch, width=None, square=()):
    """One letter of the octagonal alphabet: (polygons, width, bands), drawn `width` wide if
    given (its stems as they are, its counters wider or narrower). The first polygon is its
    outline, any others its counters. The bands are its horizontal strokes, bottom to top, as
    (y0, y1): a moulded word (moulded_curve) keeps them as drawn and stretches the letter
    between them. `square` names corners of its outline ("tl", "tr", "bl", "br") whose
    chamfers are filled in, so a moulded letter reaches into the hex there (owner)."""
    polys, W, bands = drawn_glyph(ch, width)
    for corner in square:
        polys[0] = square_corner(polys[0], W if corner[1] == "r" else 0.0, OCT_H if corner[0] == "t" else 0.0)
    return polys, W, bands


def square_corner(poly, cx, cy):
    """An outline with the chamfer across its corner (cx, cy) filled in: the chamfer's ends, one
    on each of the sides that meet there, replaced by the corner itself."""
    n = len(poly)
    for i in range(n):
        p, q = poly[i], poly[(i + 1) % n]
        if (p[0] == cx and q[1] == cy or p[1] == cy and q[0] == cx) and (cx, cy) not in (p, q):
            out = list(poly)
            out[i] = (cx, cy)
            del out[(i + 1) % n]
            return out
    raise ValueError("no chamfer at (%g, %g)" % (cx, cy))


def drawn_glyph(ch, width=None):
    """A letter as drawn (oct_glyph)."""
    H, s_, t, oc, ic = OCT_H, OCT_S, OCT_T, OCT_OC, OCT_IC

    def counter(x0, y0, x1, y1, c=ic, left=True):
        """A counter with its corners chamfered (its left ones too, unless left is False)."""
        pts = [(x1 - c, y0), (x1, y0 + c), (x1, y1 - c), (x1 - c, y1)]
        pts += [(x0 + c, y1), (x0, y1 - c), (x0, y0 + c), (x0 + c, y0)] if left else [(x0, y1), (x0, y0)]
        return pts

    if ch == "O":
        W = width or 5.2
        return [[(oc, 0), (W - oc, 0), (W, oc), (W, H - oc), (W - oc, H), (oc, H), (0, H - oc), (0, oc)],
                counter(s_, t, W - s_, H - t)], W, [(0, t + ic), (H - t - ic, H)]
    if ch == "C":
        W, a1 = width or 5.2, 3.2
        return [[(W, H - a1), (W, H - oc), (W - oc, H), (oc, H), (0, H - oc), (0, oc), (oc, 0), (W - oc, 0),
                 (W, oc), (W, a1), (W - s_, a1), (W - s_, t), (s_ + ic, t), (s_, t + ic), (s_, H - t - ic),
                 (s_ + ic, H - t), (W - s_, H - t), (W - s_, H - a1)]], W, [(0, t + ic), (H - t - ic, H)]
    if ch == "D":
        W = width or 5.2
        return [[(0, 0), (W - oc, 0), (W, oc), (W, H - oc), (W - oc, H), (0, H)],
                counter(s_, t, W - s_, H - t, left=False)], W, [(0, t + ic), (H - t - ic, H)]
    if ch == "A":
        W, top, itop, cy0 = width or 5.4, 2.1, 0.8, 2.9
        cy1 = cy0 + t
        return [[(0, 0), (s_, 0), (s_, cy0), (W - s_, cy0), (W - s_, 0), (W, 0), (W, H - top), (W - top, H),
                 (top, H), (0, H - top)],
                [(s_, cy1), (W - s_, cy1), (W - s_, H - t - itop), (W - s_ - itop, H - t), (s_ + itop, H - t),
                 (s_, H - t - itop)]], W, [(0, 0), (cy0, cy1), (H - t - itop, H)]
    if ch in "RP":
        W, yb = (width or 5.2) if ch == "R" else (width or 5.0), 4.3
        bowl = counter(s_, yb + t, W - s_, H - t, left=False)
        if ch == "R":
            # the leg leaves the bowl's lower stroke halfway along it and runs down and out on a
            # diagonal, as thick as a stem, before it drops upright over its lowest RLEG_UPRIGHT
            # (owner: so the R does not read as an A); the bowl's corner above it cut at 45
            # degrees, a notch between them
            yk = RLEG_UPRIGHT * yb
            m = (W / 2 - s_) / (yb - yk)                           # the diagonal's run per unit of drop
            wh = s_ * math.hypot(1.0, m)                           # a stem's thickness, measured across
            xr, yr = W / 2 + wh, yk + (wh - s_) / m
            outer = [(0, 0), (s_, 0), (s_, yb), (W / 2, yb), (W - s_, yk), (W - s_, 0), (W, 0), (W, yr), (xr, yb),
                     (W, yb + (W - xr)), (W, H - oc), (W - oc, H), (0, H)]
        else:
            outer = [(0, 0), (s_, 0), (s_, yb), (W - oc, yb), (W, yb + oc), (W, H - oc), (W - oc, H), (0, H)]
        return [outer, bowl], W, [(0, 0), (yb, yb + t + ic), (H - t - ic, H)]
    if ch == "B":
        W, ym, cw, tm = width or 5.2, 5.2, 0.6, 1.4
        return [[(0, 0), (W - oc, 0), (W, oc), (W, ym - cw), (W - cw, ym), (W, ym + cw), (W, H - oc), (W - oc, H),
                 (0, H)],
                counter(s_, t, W - s_, ym - tm / 2, left=False),
                counter(s_, ym + tm / 2, W - s_, H - t, left=False)], W, \
            [(0, t + ic), (ym - tm / 2 - ic, ym + tm / 2 + ic), (H - t - ic, H)]
    if ch == "N":
        W = width or 5.4
        return [[(0, 0), (s_, 0), (s_, H * 0.55), (W - s_, 0), (W, 0), (W, H), (W - s_, H), (W - s_, H * 0.45),
                 (s_, H), (0, H)]], W, [(0, 0), (H, H)]
    if ch == "I":
        W = width or 1.9
        return [[(0, 0), (W, 0), (W, H), (0, H)]], W, [(0, 0), (H, H)]
    if ch == "T":
        W = width or 5.0
        x0 = (W - s_) / 2
        return [[(x0, 0), (x0 + s_, 0), (x0 + s_, H - t), (W, H - t), (W, H), (0, H), (0, H - t), (x0, H - t)]], W, \
            [(0, 0), (H - t, H)]
    if ch == "L":
        W = width or 4.4
        return [[(0, 0), (W, 0), (W, t), (s_, t), (s_, H), (0, H)]], W, [(0, t), (H, H)]
    raise ValueError("the octagonal alphabet has no %r" % ch)


def oct_curve(name, body, spacing=1.0):
    """A word in the octagonal alphabet as a 2D filled curve: cap height 1, centred on x = 0,
    its baseline at y = 0, as a font curve at size 1 would stand."""
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions = '2D'
    cu.fill_mode = 'BOTH'
    glyphs = [oct_glyph(ch) for ch in body]
    total = sum(g[1] for g in glyphs) + OCT_GAP * spacing * (len(glyphs) - 1)
    x = -total / 2.0
    for polys, w, _ in glyphs:
        for poly in polys:
            sp = cu.splines.new('POLY')
            sp.points.add(len(poly) - 1)
            for pt, (px, py) in zip(sp.points, poly):
                pt.co = ((x + px) / OCT_H, py / OCT_H, 0.0, 1.0)
            sp.use_cyclic_u = True
        x += w + OCT_GAP * spacing
    return cu


LEVEL = {"A": (1,)}                            # strokes kept level: A's crossbar (owner, both words)
ZONE_MIN = 0.35                                # squeezed, the gaps between strokes keep this share


def oct_knots(bands):
    """A letter's strokes (bands) as knots up its glyph, (height, g, stroke): g is the share of
    the letter's extra height a knot rises by, 0 at its foot and 1 at its top, and a stroke
    between them rides at its middle's share of the height, so that stretched, its strokes
    keep their thickness and only the gaps between them stretch."""
    knots = []
    for k, (y0, y1) in enumerate(bands):
        g = 0.0 if y0 == 0 else 1.0 if y1 == OCT_H else (y0 + y1) / 2.0 / OCT_H
        knots += [(y0, g, k), (y1, g, k)]
    return knots


def knot_heights(knots, T, s):
    """The knots' heights over a letter's foot when it stands T high at s a glyph unit. The
    gaps between its strokes take up the difference from its drawn height (by their knots'
    shares, g); squeezed so far that a gap would fall below ZONE_MIN of its drawn size, the
    gaps stop there and the strokes thin to make up the rest."""
    e = T - OCT_H * s
    segs = list(zip(knots, knots[1:]))
    rigid = sum((k1[0] - k0[0]) * s for k0, k1 in segs if k1[1] == k0[1])
    e_min = max([-(1.0 - ZONE_MIN) * (k1[0] - k0[0]) * s / (k1[1] - k0[1]) for k0, k1 in segs if k1[1] > k0[1]]
                or [e])
    ez = max(e, e_min)
    r = 1.0 + (e - ez) / rigid if rigid else 1.0
    hs = [0.0]
    for k0, k1 in segs:
        h = (k1[0] - k0[0]) * s
        hs.append(hs[-1] + (h * r if k1[1] == k0[1] else h + (k1[1] - k0[1]) * ez))
    return hs


def zigzag(centres, a, y_point, rise):
    """The edge a row of pointy-top hexes makes along its top or bottom, as y of x: y_point at
    each hex's point (over its centre) and `rise` higher at its shoulders, a to either side;
    and the xs where it bends."""
    def f(x):
        return y_point + rise * min(min(abs(x - c) for c in centres), a) / a
    return f, sorted({round(c + k * a, 6) for c in centres for k in (-1, 0, 1)})


def moulded_curve(name, row):
    """A word moulded to its row of hexes (owner) as a 2D filled curve, in the plate's own
    units: each letter drawn as wide as its cell (row["cells"], one per letter, in x) at
    WORD_S a glyph unit, standing on row["base"] with its top at row["top"] (functions of x,
    either or both of them the row's zigzag edge), and stretched or squeezed between its
    strokes to fill that height (knot_heights). A stroke in LEVEL is set level, at the height
    it takes in the letter's middle. Edges are cut where the zigzag bends, and all but the
    upright ones into short pieces, so the straight pieces follow the stretch."""
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions = '2D'
    cu.fill_mode = 'BOTH'
    base, top, bends, s = row["base"], row["top"], row["bends"], WORD_S
    spans, outlines = [], []
    for ch, (x, x1) in zip(row["letters"], row["cells"]):
        if len(spans) in row.get("custom", {}):                    # a letter drawn in place, as it is given
            for j, poly in enumerate(row["custom"][len(spans)]):
                sp = cu.splines.new('POLY')
                sp.points.add(len(poly) - 1)
                for pt, (wx, wy) in zip(sp.points, poly):
                    pt.co = (wx, wy, 0.0, 1.0)
                sp.use_cyclic_u = True
                outlines.append(1 if j == 0 else 0)
            spans.append((x, x1))
            continue
        polys, _, bands = oct_glyph(ch, (x1 - x) / s, row["square"][len(spans)])
        knots = oct_knots(bands)
        level = LEVEL.get(ch, ())
        xm = (x + x1) / 2.0
        mid = [base(xm) + h for h in knot_heights(knots, top(xm) - base(xm), s)]

        def y_at(wx, gy):
            ys = [base(wx) + h for h in knot_heights(knots, top(wx) - base(wx), s)]
            ys = [mid[k] if kn[2] in level else y for k, (kn, y) in enumerate(zip(knots, ys))]
            for k in range(len(knots) - 1):
                (k0y, _, _), (k1y, _, _) = knots[k], knots[k + 1]
                if k0y <= gy <= k1y and k1y > k0y:
                    return ys[k] + (ys[k + 1] - ys[k]) * (gy - k0y) / (k1y - k0y)
            return ys[0] if gy <= knots[0][0] else ys[-1]

        for poly in polys:
            pts = []
            for i in range(len(poly)):
                (px, py), (qx, qy) = poly[i], poly[(i + 1) % len(poly)]
                ts = {0.0}
                if qx != px:
                    ts.update(t for t in (((b - x) / s - px) / (qx - px) for b in bends) if 0 < t < 1)
                    n = math.ceil(math.hypot(qx - px, qy - py) / 0.3)
                    ts.update(k / n for k in range(1, n))
                    if qy != py:
                        ts.update(t for t in ((kn[0] - py) / (qy - py) for kn in knots) if 0 < t < 1)
                for t in sorted(ts):
                    gx, gy = px + (qx - px) * t, py + (qy - py) * t
                    wx = x + gx * s
                    pts.append((wx, y_at(wx, gy)))
            sp = cu.splines.new('POLY')
            sp.points.add(len(pts) - 1)
            for pt, (wx, wy) in zip(sp.points, pts):
                pt.co = (wx, wy, 0.0, 1.0)
            sp.use_cyclic_u = True
            outlines.append(1 if poly is polys[0] else 0)
        spans.append((x, x1))
    cu["outlines"] = outlines                                  # 1 for a letter's outline, 0 for a counter
    return cu


def text_mesh(name, body, font, size, x, y, depth, bevel, mat, align_y='BOTTOM_BASELINE', base=0.0,
              offset=0.0, spacing=1.0, weld=False, resolution=None, bevel_res=3):
    """A line of text standing on z = base (its baseline at y), turned to a mesh. `offset`
    fattens the glyphs; `weld` joins caps and walls into one closed solid (a boolean cutter
    needs that)."""
    if OCTAGON and font is not None and font == globals().get("word_font"):
        cu = oct_curve(name, body, spacing)                  # the octagonal alphabet (owner)
        cu.transform(Matrix.Scale(size, 4))
        if align_y == 'CENTER':
            cu.transform(Matrix.Translation((0.0, -size / 2.0, 0.0)))
    else:
        cu = bpy.data.curves.new(name, 'FONT')
        cu.body = body
        cu.font = font
        cu.size = size
        cu.align_x, cu.align_y = 'CENTER', align_y
        cu.space_character = spacing
    return curve_mesh(name, cu, x, y, depth, bevel, mat, base, offset, weld, resolution, bevel_res)


def curve_mesh(name, cu, x, y, depth, bevel, mat, base=0.0, offset=0.0, weld=False, resolution=None, bevel_res=3):
    """A 2D curve extruded `depth`, bevelled and set on z = base at (x, y), turned to a mesh."""
    cu.extrude = depth / 2.0
    cu.bevel_depth = bevel
    cu.bevel_resolution = bevel_res          # 0: a flat 45-degree chamfer
    cu.offset = offset
    if resolution:                          # a low resolution makes the curves straight facets
        cu.resolution_u = resolution
    ob = link(bpy.data.objects.new(name, cu))
    ob.location = (x, y, base + depth / 2.0 + bevel)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    me.transform(ob.matrix_world)
    bpy.data.objects.remove(ob, do_unlink=True)
    if weld:
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(me)
        bm.free()
    mob = link(bpy.data.objects.new(name, me))
    me.materials.clear()
    if mat is not None:
        me.materials.append(mat)
    return mob


def extent(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    return (min(v.x for v in vs), max(v.x for v in vs), min(v.y for v in vs), max(v.y for v in vs))


def word(name, body, font, box, depth, bevel, mat, base=0.0, offset=0.0, spacing=1.09, fit=None,
         resolution=None, stretch=None, bevel_res=3):
    """A word fitted into box (x0, x1, y0, y1): as wide as the box, and as tall as it too so
    long as that stretches the face by no more than WORD_STRETCH; centred in it. `fit` reuses
    another word's fit (its scale and move), so an outline matches its word. Returns the
    word and the fit."""
    if fit is None:
        probe = text_mesh("probe", body, font, 1.0, 0, 0, 0.01, 0.0, None, spacing=spacing, resolution=resolution)
        x0, x1, y0, y1 = extent(probe)
        bpy.data.objects.remove(probe, do_unlink=True)
        sx = min((box[1] - box[0]) / (x1 - x0), (box[3] - box[2]) / (y1 - y0))
        sx = (box[1] - box[0]) / (x1 - x0) if stretch is None else sx
        sy = min((box[3] - box[2]) / (y1 - y0), sx * (WORD_STRETCH if stretch is None else stretch))
        fit = (Matrix.Translation(((box[0] + box[1]) / 2 - (x0 + x1) / 2 * sx,
                                   (box[2] + box[3]) / 2 - (y0 + y1) / 2 * sy, 0.0))
               @ Matrix.Diagonal((sx, sy, 1.0, 1.0)), sx)
    ob = text_mesh(name, body, font, 1.0, 0, 0, depth, bevel, mat, base=base, offset=offset / fit[1],
                   spacing=spacing, resolution=resolution, bevel_res=bevel_res)
    ob.data.transform(fit[0])
    return ob, fit


def fit_size(font, body, cap_h, max_w, spacing):
    """The size at which `body` stands cap_h tall, or max_w wide if that is smaller."""
    probe = text_mesh("probe", body, font, 1.0, 0, 0, 0.01, 0.0, None, spacing=spacing)
    x0, x1, y0, y1 = extent(probe)
    bpy.data.objects.remove(probe, do_unlink=True)
    return min(cap_h / (y1 - y0), max_w / (x1 - x0))


def letters_of(ob):
    """Split a word's mesh into one object per letter. A glyph comes out as several islands
    (its caps, walls and bevels do not share vertices), so the islands whose outlines
    overlap by most of the smaller one are joined into one letter."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    comp, parts = {}, []
    for f in bm.faces:
        if f in comp:
            continue
        comp[f] = len(parts)
        stack, faces = [f], []
        while stack:
            g = stack.pop()
            faces.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h not in comp:
                        comp[h] = comp[f]
                        stack.append(h)
        parts.append(faces)

    def box(faces):
        xs = [v.co.x for f in faces for v in f.verts]
        ys = [v.co.y for f in faces for v in f.verts]
        return min(xs), max(xs), min(ys), max(ys)

    boxes = [box(f) for f in parts]
    group = list(range(len(parts)))

    def root(i):
        while group[i] != i:
            group[i] = group[group[i]]
            i = group[i]
        return i

    for i in range(len(parts)):
        for j in range(i + 1, len(parts)):
            a, b = boxes[i], boxes[j]
            ox = min(a[1], b[1]) - max(a[0], b[0])
            oy = min(a[3], b[3]) - max(a[2], b[2])
            if ox > 0 and oy > 0:
                small = min((a[1] - a[0]) * (a[3] - a[2]), (b[1] - b[0]) * (b[3] - b[2]))
                if ox * oy > 0.5 * small:
                    group[root(i)] = root(j)
    merged = {}
    for i, faces in enumerate(parts):
        merged.setdefault(root(i), []).extend(faces)
    out = []
    for k, faces in enumerate(merged.values()):
        nb = bmesh.new()
        vmap = {}
        for f in faces:
            vs = []
            for v in f.verts:
                if v not in vmap:
                    vmap[v] = nb.verts.new(v.co)
                vs.append(vmap[v])
            try:
                nf = nb.faces.new(vs)
                nf.smooth = f.smooth
            except ValueError:
                pass
        me = bpy.data.meshes.new("%s_%d" % (ob.name, k))
        nb.to_mesh(me)
        nb.free()
        me.materials.append(ob.data.materials[0])
        out.append(link(bpy.data.objects.new(me.name, me)))
    bm.free()
    bpy.data.objects.remove(ob, do_unlink=True)
    return out


def set_askew(letters, seed=11):
    """Each coal block turned and tilted a little about its own centre, then set down again."""
    rng = random.Random(seed)
    turn, tilt = LETTER_JITTER
    for lob in letters:
        vs = lob.data.vertices
        c = Vector((sum(v.co.x for v in vs), sum(v.co.y for v in vs), sum(v.co.z for v in vs))) / len(vs)
        R = (Matrix.Rotation(math.radians(rng.uniform(-turn, turn)), 4, 'Z')
             @ Matrix.Rotation(math.radians(rng.uniform(-tilt, tilt)), 4, 'X')
             @ Matrix.Rotation(math.radians(rng.uniform(-tilt, tilt)), 4, 'Y'))
        lob.data.transform(Matrix.Translation(c) @ R @ Matrix.Translation(-c))
        z0 = min(v.co.z for v in vs)
        lob.data.transform(Matrix.Translation((0, 0, -z0 - 0.01)))


# ------------------------------------------------------------------ icons
def factory_icon(ox, oy, z0, h, mat, window_mat):
    """The emblem's factory: a sawtooth-roofed shed with a chimney, and smoke from it."""
    shape = [(0, 0), (1.25, 0), (1.25, 0.72), (0.95, 0.45), (0.95, 0.72), (0.65, 0.45), (0.65, 0.72),
             (0.35, 0.45), (0.26, 0.45), (0.26, 1.15), (0.08, 1.15), (0.08, 0.45), (0, 0.45)]
    slab("icon_factory", [(ox + x, oy + y) for x, y in shape], z0, z0 + h, mat, bevel=0.012)
    for k, (cx, cy, r) in enumerate(((0.22, 1.30, 0.09), (0.37, 1.42, 0.11), (0.56, 1.47, 0.12))):
        disc("icon_smoke%d" % k, ox + cx, oy + cy, r, z0, z0 + h * 0.8, mat, bevel=0.012)
    for k in range(4):                                         # a row of windows in the shed
        x = ox + 0.42 + 0.21 * k
        slab("icon_window%d" % k, [(x, oy + 0.14), (x + 0.12, oy + 0.14), (x + 0.12, oy + 0.30), (x, oy + 0.30)],
             z0 + h - 0.02, z0 + h + 0.005, window_mat)


def solar_icon(ox, oy, z0, h, mat):
    """The emblem's solar panel: a gridded panel on a post, and the sun above it."""
    panel = [(ox + 0.05, oy + 0.38), (ox + 1.10, oy + 0.38), (ox + 1.26, oy + 0.90), (ox + 0.21, oy + 0.90)]
    inner = inset(panel, 0.055)
    slab("icon_panel", panel, z0, z0 + h, mat, bevel=0.01, hole=inner)
    a0, a1, a2, a3 = inner
    for k in range(1, 4):                                     # three bars across the panel
        f = k / 4.0
        p = (a0[0] + (a1[0] - a0[0]) * f, a0[1] + (a1[1] - a0[1]) * f)
        q = (a3[0] + (a2[0] - a3[0]) * f, a3[1] + (a2[1] - a3[1]) * f)
        bar("icon_grid_v%d" % k, p, q, 0.035, z0, z0 + h * 0.8, mat)
    mid0 = ((a0[0] + a3[0]) / 2, (a0[1] + a3[1]) / 2)
    mid1 = ((a1[0] + a2[0]) / 2, (a1[1] + a2[1]) / 2)
    bar("icon_grid_h", mid0, mid1, 0.035, z0, z0 + h * 0.8, mat)
    bar("icon_post", (ox + 0.62, oy + 0.03), (ox + 0.62, oy + 0.40), 0.08, z0, z0 + h, mat)
    bar("icon_base", (ox + 0.38, oy + 0.03), (ox + 0.86, oy + 0.03), 0.06, z0, z0 + h, mat)
    sx, sy = ox + 1.22, oy + 1.28
    disc("icon_sun", sx, sy, 0.12, z0, z0 + h, mat, bevel=0.01)
    for k in range(8):
        a = 2 * math.pi * k / 8
        bar("icon_ray%d" % k, (sx + 0.17 * math.cos(a), sy + 0.17 * math.sin(a)),
            (sx + 0.26 * math.cos(a), sy + 0.26 * math.sin(a)), 0.035, z0, z0 + h * 0.8, mat)


# ------------------------------------------------------------------ build
clear_scene()
scene = bpy.context.scene
rng = random.Random(3)
# Polished: under the high sun a flat brass face would catch the light as a broad sheen and
# turn cream if it were rough; polished, it sends that reflection away from the camera and
# stays gold, while its worn, rougher patches still glint.
# Part metal, so the sun lights a brass face as it lights the enamel beside it and the chamfers
# shade by the same light (owner: the lighting on CAPITAL looked odd, lit rims round dark faces).
if HIGH:
    brass = brass_mat(rough=0.26, vary=(0.03, 0.05), grain=36.0, metal=BRASS_METAL)
    brass_dark = brass_mat("brass_dark", rough=0.32, tone=0.70, vary=(0.03, 0.05), grain=36.0, metal=BRASS_METAL)
else:
    # a little shinier than v26 (owner): smoother, with narrower wear
    brass = brass_mat(rough=0.21, vary=(0.05, 0.08))
    brass_dark = brass_mat("brass_dark", rough=0.32, tone=0.70, vary=(0.05, 0.08))
navy = enamel_mat("navy_enamel", NAVY)
cream = enamel_mat("cream_enamel", CREAM, rough=0.28)
soot = enamel_mat("soot", (0.02, 0.02, 0.025), rough=0.6)
L = {"hexbar": layout_hexbar, "single": layout_single, "hex": layout_hex, "honeycomb": layout_honeycomb,
     "honeycomb-wide": layout_honeycomb_wide}[args.plate]()
AND_STYLE = args.and_ or ("stamped" if args.plate == "single" else "coal")
SOLID = args.carbon in ("coals", "whitehot", "brass")         # CARBON with no brass outline
ANGULAR = 1 if SOLID else None                                 # blockier, angular letters

outline = L["outline"]                                         # the whole plate, for the frame
COAL_TOP = "coal" in L
plate_outline = L["plate"] if COAL_TOP else outline            # the navy and its rim
face = inset(plate_outline, RIM_W)
plate_ob = slab("plate_body", face, BODY_Z0, 0.0, navy)
if L.get("faces"):
    # The rim and the dividers one piece of brass (the hex bar): the plate's outline less the
    # plates' faces and the hex's, filled even-odd, bevelled all round within its outline.
    # Made separately, the rim's bevel and the dividers' pinched where they met, into dark holes.
    holes = L["faces"] + [inset(L["coal_hex"]["cell"], RIM_W)]
    curve_mesh("plate_rim", poly_curve("plate_rim", [plate_outline] + holes), 0.0, 0.0,
               RIM_H - BODY_Z0 - 2 * 0.03, 0.03, brass, base=BODY_Z0, offset=-0.03, bevel_res=3)
else:
    slab("plate_rim", plate_outline, BODY_Z0, RIM_H, brass, bevel=0.03, hole=face)
for k, (x, y) in enumerate(L["screws"]):
    screw("screw%d" % k, x, y, 0.0, 0.10, rng.uniform(0, math.pi), brass)
frame_obs = []
for k, cell in enumerate(L["frames"]):                         # an icon's hex, outlined in brass
    frame_obs.append(slab("frame%d" % k, inset(cell, FRAME_IN), 0.0, FRAME_H, brass, bevel=0.008,
                          hole=inset(cell, FRAME_OUT)))

word_font = bpy.data.fonts.load(WORD_FONT)
and_font = bpy.data.fonts.load(face_file(*AND_FACE))
pad = (OUTLINE if not SOLID else 0.0) + 0.02                  # the outline stays in the box
cbox = L["carbon"]
cbox_in = (cbox[0] + pad, cbox[1] - pad, cbox[2] + pad, cbox[3] - pad)

# CAPITAL: raised brass.
# Flat chamfers, so each side's chamfer is one face the light lands on evenly: lit at the top
# left, shaded at the bottom right (owner).
MOULD = OCTAGON and args.words == "moulded" and "moulded" in L and SOLID
roof = None
glowing = set()                                                # the fire's objects, by name
cap_bevel, cap_res = 0.032 if HIGH else LETTER_BEVEL_BRASS, 0 if (ANGULAR and HIGH) else 3
cap_in = 0.0 if HIGH else LETTER_BEVEL_BRASS - 0.025          # the wider bevel kept within the letters' v30 outline
if MOULD:
    M = L["moulded"]
    CROW = M["carbon_coal"] if COAL_TOP else M["carbon"]
    curve_mesh("CAPITAL", moulded_curve("CAPITAL", M["capital"]), 0.0, 0.0, 0.16, cap_bevel, brass,
               bevel_res=cap_res, offset=-cap_in)
    carbon_curve = moulded_curve("CARBON_bed", CROW)
    spans = CROW["cells"]
    cx0, cx1, y_foot, roof = spans[0][0], spans[-1][1], CROW["base"](0.0), CROW["roof"]
    y_top = min(CROW["top"](x) for span in spans for x in span)
    print("MOULDED CARBON %.2f..%.2f high; letters %s wide" % (
        y_top - y_foot, max(CROW["top"](x) for span in spans for x in span) - y_foot,
        " ".join("%.2f" % (x1 - x0) for M_ in (CROW, M["capital"]) for x0, x1 in M_["cells"])))
else:
    word("CAPITAL", "CAPITAL", word_font, L["capital"], 0.16, cap_bevel, brass, resolution=ANGULAR,
         bevel_res=cap_res)

    # CARBON, on its brass outline.
    probe, fit = word("probe", "CARBON", word_font, cbox_in, 0.01, 0.0, None, resolution=ANGULAR)
    cx0, cx1, y_foot, y_top = extent(probe)
    bpy.data.objects.remove(probe, do_unlink=True)
if not SOLID:
    word("CARBON_outline", "CARBON", word_font, cbox_in, 0.03, 0.006, brass, offset=OUTLINE, fit=fit)
if args.carbon == "coals" and COAL_TOP:
    # The top row a slab of coal with CARBON burning in it (owner): the letters solid and
    # glowing white, with no cracks, and round them coal lumps over a glowing bed across all
    # three hexes, cut along the letters' outlines. The heat is by the distance from the
    # letters' edges (heat_field): the letters red only at their very edges; round them the
    # lumps dark and the cracks red, fading away from the letters but never quite out.
    polys = [[(pt.co.x, pt.co.y) for pt in sp.points] for sp in carbon_curve.splines]
    xs = [p[0] for p in L["coal"]]
    ys = [p[1] for p in L["coal"]]
    F = heat_field(polys, (min(xs) - 0.05, max(xs) + 0.05, min(ys) - 0.05, max(ys) + 0.05))
    # the slab's edge crumbled (owner: a little rougher), spilling over the rim along its foot
    edge = rough_outline(L["coal"], random.Random(12), spill=range(6))
    bed = curve_mesh("CARBON_bed", poly_curve("coal_hexes", [edge]), 0.0, 0.0, 0.0, 0.0, ember_bed_mat(F),
                     base=0.004)
    letters = curve_mesh("CARBON", carbon_curve, 0.0, 0.0, LETTER_DEPTH, LETTER_BEVEL, letter_glow_mat(F), bevel_res=2)
    # the ground: the slab less the letters (even-odd)
    ground_flat = curve_mesh("coal_ground", poly_curve("coal_ground", [edge] + polys), 0.0, 0.0, 0.0, 0.0, None)
    ground = coal_letters(ground_flat, coal_ground_mat(), random.Random(9), prefix="coal_ground", tries_per_area=3000,
                          min_side=0.5, min_round=0.035)          # no fragments or slivers by the letters
    bpy.data.objects.remove(ground_flat, do_unlink=True)
    # no slivers of dark coal in the narrow gaps between letters, nor in a letter's notch (as
    # by R's leg), where a lump's middle is nearer the letter than GROUND_CLEAR: the bed
    # shows there, red
    gaps = [(a_[1], b_[0]) for a_, b_ in zip(CROW["cells"], CROW["cells"][1:])]
    kept = []
    for ob in ground:
        vs = ob.data.vertices
        mx, my = sum(v.co.x for v in vs) / len(vs), sum(v.co.y for v in vs) / len(vs)
        if (any(g0 <= mx <= g1 for g0, g1 in gaps) and CROW["base"](mx) <= my <= CROW["top"](mx)
                or F["at"](mx, my) > -GROUND_CLEAR):
            bpy.data.objects.remove(ob, do_unlink=True)
        else:
            kept.append(ob)
    ground = kept
    for ob in [bed, letters] + ground:                         # the slab sits on top, over the rim
        ob.location.z += COAL_Z
    glowing.update((bed.name, letters.name))
    print("COAL lumps: %d round the letters" % len(ground))
    # The fire's light (owner): hidden lamps in a level row low over the slab, where the
    # plate's CARBON would stand (owner: v22 lit the plate better than lamps following the
    # moulded feet up the slab), high enough to clear the coal.
    n, z, r, watts = FIRE_LAMPS
    for i in range(n):
        x = cx0 + (i + 0.5) * (cx1 - cx0) / n
        lamp = bpy.data.lights.new("fire_lamp%d" % i, 'POINT')
        lamp.energy, lamp.color, lamp.shadow_soft_size = watts, FIRE_TINT, r
        lamp_ob = link(bpy.data.objects.new(lamp.name, lamp))
        lamp_ob.location = (x, M["carbon"]["base"](x) + 0.05, FIRE_LAMP_Z_COAL)
        lamp_ob.visible_camera = lamp_ob.visible_glossy = False
elif args.carbon == "brass":
    # CARBON in raised brass, as CAPITAL is (owner): the same letters, moulded to the top row,
    # and lit as CAPITAL is, the brass lamp over the plate's left two thirds included.
    curve_mesh("CARBON", carbon_curve, 0.0, 0.0, 0.16, cap_bevel, brass, bevel_res=cap_res, offset=-cap_in)
elif args.carbon == "whitehot":
    # CARBON white-hot (owner, after a player found the coal letters hard to read, their top
    # halves most): solid raised letters as CAPITAL's, the same shapes as the coal ones,
    # glowing white and yellowing to orange only at their edges; and where they meet the
    # plate a little of them melted, a low rounded skirt round each letter's foot glowing
    # orange-red at the letter and cooling to scorched dark.
    polys = [[(pt.co.x, pt.co.y) for pt in sp.points] for sp in carbon_curve.splines]
    xs = [p[0] for poly in polys for p in poly]
    ys = [p[1] for poly in polys for p in poly]
    F = heat_field(polys, (min(xs) - 0.12, max(xs) + 0.12, min(ys) - 0.12, max(ys) + 0.12))
    # the melt's outline: each letter's outline pushed out and each counter drawn in by MELT_W
    # (Blender's own curve offset closed B's small counters up and filled them with melt)
    melt_polys = [offset_poly(clean_poly(poly), MELT_W if is_outline else -MELT_W)
                  for poly, is_outline in zip(polys, carbon_curve["outlines"])]
    melt = curve_mesh("CARBON_melt", poly_curve("CARBON_melt", melt_polys), 0.0, 0.0, MELT_H, MELT_H, melt_mat(F))
    letters = curve_mesh("CARBON", carbon_curve, 0.0, 0.0, HOT_DEPTH, HOT_BEVEL, white_hot_mat(F), bevel_res=2)
    glowing.update((letters.name, melt.name))
    # the fire's light (owner): hidden lamps in a row just below the letters' feet, lighting
    # the plate, AND and the frames (over the letters, they lit hot spots in their counters)
    n, z, r, watts = FIRE_LAMPS
    for i in range(n):
        x = cx0 + (i + 0.5) * (cx1 - cx0) / n
        lamp = bpy.data.lights.new("fire_lamp%d" % i, 'POINT')
        lamp.energy, lamp.color, lamp.shadow_soft_size = watts, FIRE_TINT, r
        lamp_ob = link(bpy.data.objects.new(lamp.name, lamp))
        lamp_ob.location = (x, y_foot - 0.06, z)
        lamp_ob.visible_camera = lamp_ob.visible_glossy = False
elif args.carbon == "coals":
    # The letters built of lumps of coal over a glowing bed, as in the owner's reference; no
    # brass outline (owner).
    if MOULD:
        bed = curve_mesh("CARBON_bed", carbon_curve, 0.0, 0.0, 0.0, 0.0, lava_mat(y_foot, y_top, roof), base=0.004)
    else:
        bed, _ = word("CARBON_bed", "CARBON", word_font, cbox_in, 0.0, 0.0, lava_mat(y_foot, y_top), base=0.004,
                      fit=fit, resolution=ANGULAR)
    lumps = len(coal_letters(bed, coal_rock_mat(y_foot, y_top, roof), random.Random(8)))
    # the lumps that glow, in the lower part of their letters (the heat is gone by halfway up)
    top_at = CROW["top"] if MOULD else (lambda x: y_top)
    for ob in scene.objects:
        if ob.name.startswith("coal_"):
            vs = ob.data.vertices
            mx, my = sum(v.co.x for v in vs) / len(vs), sum(v.co.y for v in vs) / len(vs)
            if (my - y_foot) / (top_at(mx) - y_foot) < SUN_SHADOWLESS:
                glowing.add(ob.name)
    glowing.add(bed.name)
    print("COAL lumps:", lumps, "glowing:", len(glowing) - 1)
    # The whole word's fire as one wide light (owner): hidden lamps in a row over the glowing
    # coal, a little above it, so its light reaches across the plate rather than skimming it:
    # it fades the sun's shadows round the letters' upper halves and casts its own, the
    # dark coal's up and away from it, AND's down, the frames' into their hexes. Unseen, and
    # not in reflections: the coal's own light (fire_light) gives the glints. Strong, as the
    # navy enamel shows little of an orange light, so they light only what is round the
    # coal, not the coal itself, which would lose its dark top (light linking, below).
    n, z, r, watts = FIRE_LAMPS
    for i in range(n):
        x = cx0 + (i + 0.5) * (cx1 - cx0) / n
        lamp = bpy.data.lights.new("fire_lamp%d" % i, 'POINT')
        lamp.energy, lamp.color, lamp.shadow_soft_size = watts, FIRE_TINT, r
        lamp_ob = link(bpy.data.objects.new(lamp.name, lamp))
        lamp_ob.location = (x, y_foot + FIRE_LAMP_UP * (top_at(x) - y_foot), z)
        lamp_ob.visible_camera = lamp_ob.visible_glossy = False
    # Light out of the letters (owner): the fire itself is the light (fire_light), so the
    # white-hot feet light the plate, AND and the coal round them, and cast shadows.
elif args.carbon == "forge":
    # Each letter a window into the forge, edged in raised brass: the forge lies on the
    # glyph itself, drawn flat on its outline.
    word("CARBON_forge", "CARBON", word_font, cbox_in, 0.0, 0.0, forge_mat(y_foot, y_top),
         base=0.03 + 2 * 0.006 + 0.002, fit=fit)
    # A few sparks escape over the plate above the letters: streaks and specks, orange.
    me = bpy.data.meshes.new("sparks")
    bm = bmesh.new()
    me.materials.append(glow_mat("spark_orange", (1.0, 0.40, 0.06), 1.7))
    me.materials.append(glow_mat("spark_yellow", (1.0, 0.62, 0.18), 1.5))
    for k in range(18):
        x = rng.uniform(cx0 + 0.3, cx1 - 0.3)
        y = y_top + 0.08 + 0.45 * rng.random() ** 1.4
        z = RIM_H + 0.05
        speck = rng.random() < 0.4
        Ls = 0.025 if speck else rng.uniform(0.05, 0.12) * (1.0 - 0.6 * (y - y_top) / 0.55)
        ang = math.radians(90 + rng.uniform(-35, 35))
        w = rng.uniform(0.012, 0.018)
        dx, dy = math.cos(ang) * Ls, math.sin(ang) * Ls
        nx, ny = -math.sin(ang) * w, math.cos(ang) * w
        taper = 1.0 if speck else 0.3
        vs = [bm.verts.new((x - nx, y - ny, z)), bm.verts.new((x + dx - nx * taper, y + dy - ny * taper, z)),
              bm.verts.new((x + dx + nx * taper, y + dy + ny * taper, z)), bm.verts.new((x + nx, y + ny, z))]
        f = bm.faces.new(vs)
        f.material_index = k % 2
    bm.to_mesh(me)
    bm.free()
    link(bpy.data.objects.new("sparks", me))
else:
    coal_word, _ = word("CARBON", "CARBON", word_font, cbox_in, 0.24, 0.02,
                        carbon_mat(y_foot, y_top, mode=args.carbon), fit=fit)
    coal = letters_of(coal_word)
    if args.carbon == "ember":
        set_askew(coal)

# The rule across the middle, with the "and" tab on it; the two icons where the plate puts them.
if L.get("rule"):
    x0, x1, ry = L["rule"]
    bar("rule", (x0, ry), (x1, ry), 0.07, 0.0, 0.04, brass)
if L.get("tab"):
    TAB_W, TAB_H, TAB_Z = 1.50, 0.72, 0.06
    tx, ty = L["tab"]
    slab("and_tab", [(tx - TAB_W / 2, ty - TAB_H / 2), (tx + TAB_W / 2, ty - TAB_H / 2),
                     (tx + TAB_W / 2, ty + TAB_H / 2), (tx - TAB_W / 2, ty + TAB_H / 2)], 0.0, TAB_Z, brass_dark,
         bevel=0.02)
    for k, rx in enumerate((tx - TAB_W / 2 + 0.15, tx + TAB_W / 2 - 0.15)):
        dome("tab_rivet%d" % k, rx, ty, TAB_Z, 0.05, 0.5, brass)
    text_mesh("and", "and", and_font, 0.60, tx, ty, 0.05, 0.008, cream, align_y='CENTER', base=TAB_Z)
if L.get("silver_and") and AND_STYLE == "coal":
    # AND of coal in a bright silver octagonal dish sunk into the plate (owner), a little
    # larger than the silver AND was. The plate cut to take the dish; the dish's floor
    # DISH_DEPTH down, its lip just proud of the face, its wall sloping in so the side toward
    # the light (the bottom right, facing up and left) catches it and the other falls in
    # shade; the letters' coal on a black bed in it, casting its shadows on the floor.
    x0, x1, y0, y1 = L["silver_and"]
    ax, ay = (x0 + x1) / 2, (y0 + y1) / 2
    hw, hh = (x1 - x0) / 2 * AND_SCALE, (y1 - y0) / 2 * AND_SCALE
    # squarish (owner): its ends square to the icons' frames and as tall as their upright
    # sides, so AND, its proportions kept, fitted inside the floor that leaves
    ring = inset([cell for cell in L["frames"] if cell[0][0] > ax][0], FRAME_IN)
    x_side = min(p[0] for p in ring)
    Y = max(abs(p[1] - ay) for p in ring if abs(p[0] - x_side) < 1e-6)
    k_and = min(1.0, (Y - DISH_WALL - DISH_SLOPE - AND_CLEAR) / hh)
    hw, hh = hw * k_and, hh * k_and
    # its ends DISH_TO_FRAME_PX from the icons' frames at the ends of the row (owner), the
    # letters their own size in the middle of it
    fx, _, fo = framing(outline)
    px = fx / fo                                               # the render's pixels to a unit
    frame_in = min(min(p[0] for p in inset(cell, FRAME_IN)) for cell in L["frames"] if cell[0][0] > ax)
    X, c = frame_in - ax - DISH_TO_FRAME_PX / px, DISH_CORNER
    print("DISH %.3f x %.3f, its ends %.3f (%d px) from the frames; AND %.2f of its v31 size" % (
        2 * X, 2 * Y, frame_in - ax - X, DISH_TO_FRAME_PX, k_and))
    def dish_outline(d):
        """The dish's outline pulled in by d, drawn afresh: pulling the outline in with inset()
        crossed its small corners over once d was larger than they are, and the hollow cut
        away the whole dish."""
        X_, Y_, c_ = X - d, Y - d, max(c - d * (math.sqrt(2) - 1), 0.004)
        return [(ax + x, ay + y) for x, y in ((X_, -Y_ + c_), (X_, Y_ - c_), (X_ - c_, Y_), (-X_ + c_, Y_), (-X_, Y_ - c_),
                                              (-X_, -Y_ + c_), (-X_ + c_, -Y_), (X_ - c_, -Y_))]
    dish = dish_outline(0.0)
    hole = slab("dish_cut", dish, -DISH_DEPTH - 0.05, 0.05, navy)
    cut(plate_ob, hole)
    hole.hide_render = hole.hide_viewport = True
    tray = slab("and_dish", dish, -DISH_DEPTH - 0.04, DISH_LIP, dish_silver_mat())
    lip_z = DISH_LIP + 0.02                                    # the hollow's top, above the lip
    slope = DISH_SLOPE * (lip_z + DISH_DEPTH) / (DISH_LIP + DISH_DEPTH)
    hollow = frustum("and_dish_hollow", dish_outline(DISH_WALL + DISH_SLOPE), -DISH_DEPTH,
                     dish_outline(DISH_WALL + DISH_SLOPE - slope), lip_z)
    cut(tray, hollow)
    hollow.hide_render = hollow.hide_viewport = True
    bev = tray.modifiers.new("bevel", 'BEVEL')                 # after the hollow, so its edges are rounded too
    bev.width, bev.segments, bev.limit_method = 0.008, 3, 'ANGLE'
    and_bed = node_mat("and_bed")
    and_bed[2].inputs["Base Color"].default_value = (0.015, 0.014, 0.013, 1)
    and_bed[2].inputs["Roughness"].default_value = 0.8
    bed, _ = word("AND_bed", "AND", word_font, (ax - hw, ax + hw, ay - hh, ay + hh), 0.0, 0.0, and_bed[0],
                  base=-DISH_DEPTH + 0.003, spacing=1.08, resolution=ANGULAR)
    and_coal = coal_letters(bed, coal_ground_mat(), random.Random(21), spacing=DISH_LUMP, height=(0.06, 0.17),
                            prefix="coal_and", loose=AND_LOOSE)
    # the coal cut from the letters as drawn, the black bed under it then drawn in a little, so
    # the loose coal hides its edges
    bpy.data.objects.remove(bed, do_unlink=True)
    bed, _ = word("AND_bed", "AND", word_font, (ax - hw, ax + hw, ay - hh, ay + hh), 0.0, 0.0, and_bed[0],
                  base=-DISH_DEPTH + 0.003, spacing=1.08, resolution=ANGULAR, offset=-AND_BED_IN)
    for ob in and_coal:
        ob.location.z -= DISH_DEPTH
    print("AND coal lumps:", len(and_coal))
elif L.get("silver_and") and AND_STYLE == "stamped":
    # AND stamped into the plate in silver (owner): the letters pressed STAMP_DEPTH into the
    # navy, their floors bright silver; the cut walls round them catch the light on the side
    # away from it and shade the silver on the side toward it, as a stamping does.
    cutter, fit_ = word("AND_stamp", "AND", word_font, L["silver_and"], STAMP_DEPTH + 0.08, 0.0, None,
                        base=-STAMP_DEPTH, spacing=1.08, resolution=ANGULAR)
    cb_ = bmesh.new()
    cb_.from_mesh(cutter.data)
    bmesh.ops.remove_doubles(cb_, verts=cb_.verts, dist=1e-4)        # one closed solid, for the cut
    bmesh.ops.recalc_face_normals(cb_, faces=list(cb_.faces))
    cb_.to_mesh(cutter.data)
    cb_.free()
    cut(plate_ob, cutter)
    cutter.hide_render = cutter.hide_viewport = True
    word("AND", "AND", word_font, L["silver_and"], 0.004, 0.0, dish_silver_mat(), base=-STAMP_DEPTH,
         spacing=1.08, resolution=ANGULAR, fit=fit_)
elif L.get("silver_and"):
    # AND in capitals, the words' own blocky, angular face, raised in brushed silver and
    # bevelled so its edges catch the light (owner).
    word("AND", "AND", word_font, L["silver_and"], 0.08, 0.026, brushed_silver_mat(), spacing=1.08,
         resolution=ANGULAR)
if L.get("coal_hex"):
    # The hex of coal (owner): brass dividers where the plates meet it (part of the rim); a black
    # bed and large lumps of dark coal, none of them glowing; on them AND in silver
    # (HEXBAR_AND): its letters alone, or engraved in a silver plaque.
    CH = L["coal_hex"]
    a_, h_ = CH["a"], CH["h"]
    coal_area = inset(CH["cell"], RIM_W)
    bed_m = node_mat("hex_coal_bed")
    bed_m[2].inputs["Base Color"].default_value = (0.012, 0.011, 0.010, 1)
    bed_m[2].inputs["Roughness"].default_value = 0.85
    curve_mesh("hex_coal_bed", poly_curve("hex_coal_bed", [coal_area]), 0.0, 0.0, 0.0, 0.0, bed_m[0], base=0.004)
    flat = curve_mesh("hex_coal_flat", poly_curve("hex_coal_flat", [coal_area]), 0.0, 0.0, 0.0, 0.0, None)
    lumps_ = coal_letters(flat, coal_ground_mat(), random.Random(31), spacing=HEX_LUMP, height=(0.14, 0.30),
                          prefix="coal_hex", min_side=0.3, loose=HEX_COAL_LOOSE)
    bpy.data.objects.remove(flat, do_unlink=True)
    if HEXBAR_AND == "letters":
        # AND in raised silver letters lying straight on the coal, no plate under them (owner),
        # HEXBAR_AND_SCALE of the bar's height and the hex's width, in its middle;
        # the lumps under them pressed down beneath them, those between left standing
        x_and = (a_ - RIM_W - HEXBAR_AND_SIDE) * HEXBAR_AND_SCALE
        and_ob, _ = word("AND", "AND", word_font, (-x_and, x_and, -h_ * HEXBAR_AND_SCALE, h_ * HEXBAR_AND_SCALE),
                         0.10, 0.02, brushed_silver_mat(), base=HEXBAR_AND_Z, spacing=1.08, resolution=ANGULAR)
        from mathutils.bvhtree import BVHTree
        dg_ = bpy.context.evaluated_depsgraph_get()
        tree = BVHTree.FromObject(and_ob, dg_)
        for ob in lumps_:
            vs = ob.data.vertices
            if any(tree.ray_cast(Vector((v.co.x, v.co.y, 5.0)), Vector((0.0, 0.0, -1.0)))[0] is not None
                   for v in vs if v.co.z > HEXBAR_AND_Z - 0.01):
                top_ = max(v.co.z for v in vs)
                for v in vs:
                    v.co.z *= (HEXBAR_AND_Z - 0.01) / top_
    else:
        # AND engraved in a silver plaque lying on the coal, filled with the plates' navy
        # enamel; the lumps under its edges pressed down to its underside
        PW, PH, PC = PLAQUE
        plaque_poly = [(PW / 2, -PH / 2 + PC), (PW / 2, PH / 2 - PC), (PW / 2 - PC, PH / 2), (-PW / 2 + PC, PH / 2),
                       (-PW / 2, PH / 2 - PC), (-PW / 2, -PH / 2 + PC), (-PW / 2 + PC, -PH / 2), (PW / 2 - PC, -PH / 2)]
        z0, z1 = PLAQUE_Z
        for ob in lumps_:
            vs = ob.data.vertices
            if (min(v.co.x for v in vs) < PW / 2 and max(v.co.x for v in vs) > -PW / 2 and
                    min(v.co.y for v in vs) < PH / 2 and max(v.co.y for v in vs) > -PH / 2):
                top_ = max(v.co.z for v in vs)
                if top_ > z0 - 0.01:
                    for v in vs:
                        v.co.z *= (z0 - 0.01) / top_
        plaque = slab("and_plaque", plaque_poly, z0, z1, dish_silver_mat(), bevel=0.015)
        and_box = (-HEXBAR_AND_H * 2.15 / 2, HEXBAR_AND_H * 2.15 / 2, -HEXBAR_AND_H / 2, HEXBAR_AND_H / 2)
        cutter, fit_ = word("AND_engrave", "AND", word_font, and_box, ENGRAVE + 0.06, 0.0, None, base=z1 - ENGRAVE,
                            spacing=1.08, resolution=ANGULAR)
        cb_ = bmesh.new()
        cb_.from_mesh(cutter.data)
        bmesh.ops.remove_doubles(cb_, verts=cb_.verts, dist=1e-4)
        bmesh.ops.recalc_face_normals(cb_, faces=list(cb_.faces))
        cb_.to_mesh(cutter.data)
        cb_.free()
        cut(plaque, cutter)
        cutter.hide_render = cutter.hide_viewport = True
        word("AND", "AND", word_font, and_box, 0.004, 0.0, navy, base=z1 - ENGRAVE, spacing=1.08, resolution=ANGULAR,
             fit=fit_)
    print("HEX coal lumps:", len(lumps_))
if L.get("silver_screws"):
    silver = silver_mat()
    for k, (x, y) in enumerate(L["silver_screws"]):
        screw("silver_screw%d" % k, x, y, 0.0, SILVER_SCREW_R, rng.uniform(0, math.pi), silver)
ICON_H = 0.06
ICON_SIZE = {"factory": (1.25, 1.59), "solar": (1.48, 1.54)}   # each icon's own width and height
def game_icon(name, cx, cy, box, depth, bevel, mat):
    """One of the game's own icons (icon_key.py keyed it to one colour and traced it), raised
    in relief like the lettering: its outline, holes and all, extruded and bevelled, fitted
    into a square `box` on a side and centred on (cx, cy), standing on the face."""
    J = json.load(open(os.path.join(ICON_DIR, name + ".json")))
    k = box / max(J["width"], J["height"])
    cu = bpy.data.curves.new("icon_" + name, 'CURVE')
    cu.dimensions = '2D'
    cu.fill_mode = 'BOTH'
    cu.extrude = depth / 2.0
    cu.bevel_depth = bevel
    cu.bevel_resolution = 2
    for poly in J["polygons"]:
        sp = cu.splines.new('POLY')
        sp.points.add(len(poly) - 1)
        for pt, (x, y) in zip(sp.points, poly):
            pt.co = (x * k, y * k, 0.0, 1.0)
        sp.use_cyclic_u = True
    ob = link(bpy.data.objects.new("icon_" + name, cu))
    ob.location = (cx, cy, depth / 2.0 + bevel)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    me.transform(ob.matrix_world)
    bpy.data.objects.remove(ob, do_unlink=True)
    mob = link(bpy.data.objects.new("icon_" + name, me))
    me.materials.clear()
    me.materials.append(mat)
    return mob


def fit_in(points, poly):
    """The largest scale k, and the move t, at which the points, scaled by k and moved by t,
    all lie in the convex polygon poly (counter-clockwise). By halving k: at each, the moves
    that fit are the polygon pulled in, edge by edge, by the points' reach past it."""
    edges = []
    for i in range(len(poly)):
        (ax, ay), (bx, by) = poly[i], poly[(i + 1) % len(poly)]
        L_ = math.hypot(bx - ax, by - ay)
        n = ((by - ay) / L_, -(bx - ax) / L_)                   # outward
        edges.append((n, n[0] * ax + n[1] * ay, max(n[0] * x + n[1] * y for x, y in points)))

    def moves(k):
        reg = [(-50.0, -50.0), (50.0, -50.0), (50.0, 50.0), (-50.0, 50.0)]
        for n, c, reach in edges:
            reg = clip_halfplane(reg, n, c - k * reach)
            if len(reg) < 3:
                return []
        return reg if abs(poly_area(reg)) > 1e-14 else []

    lo, hi = 0.0, 50.0
    for _ in range(60):
        mid = (lo + hi) / 2
        lo, hi = (mid, hi) if moves(mid) else (lo, mid)
    reg = moves(lo)
    return lo, (sum(p[0] for p in reg) / len(reg), sum(p[1] for p in reg) / len(reg))


def merge_icon(name, cell, frame, mat):
    """A game icon joined to its frame as one piece of brass (owner: the factory meets its
    frame in three places): grown as large as it fits in the frame's ring, reaching halfway
    into it where it touches, as high as the frame. Each keeps its own chamfer, as the other
    icon and frame have (owner: bevelled after the union, the icon's many short traced edges
    kept the bevel from taking, and it looked flat); then the two are unioned and baked
    into one mesh, so the icon runs into the ring."""
    J = json.load(open(os.path.join(ICON_DIR, name + ".json")))
    k, (tx, ty) = fit_in([p for poly in J["polygons"] for p in poly], inset(cell, (FRAME_IN + FRAME_OUT) / 2))
    cu = bpy.data.curves.new("icon_" + name, 'CURVE')
    cu.dimensions = '2D'
    cu.fill_mode = 'BOTH'
    for poly in J["polygons"]:
        sp = cu.splines.new('POLY')
        sp.points.add(len(poly) - 1)
        for pt, (x, y) in zip(sp.points, poly):
            pt.co = (tx + x * k, ty + y * k, 0.0, 1.0)
        sp.use_cyclic_u = True
    icon = curve_mesh("icon_" + name, cu, 0.0, 0.0, ICON_DEPTH, ICON_BEVEL, mat, weld=True, bevel_res=2)
    union = frame.modifiers.new("icon", 'BOOLEAN')                # after the frame's own bevel
    union.operation, union.object, union.solver = 'UNION', icon, 'EXACT'
    bpy.context.view_layer.update()
    baked = bpy.data.meshes.new_from_object(frame.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    frame.modifiers.clear()
    frame.data = baked
    frame.name = baked.name = "frame_" + name
    bpy.data.objects.remove(icon, do_unlink=True)
    print("MERGED %s into its frame at %.3f of its height: %d faces" % (name, k, len(baked.polygons)))


for i, (kind, cx, cy, scale) in enumerate(L["icons"]):
    if args.icons == "game":
        if kind in L.get("merge", ()):
            merge_icon(kind, L["frames"][i], frame_obs[i], brass)
        else:
            game_icon(kind, cx, cy, ICON_BOX, ICON_DEPTH, ICON_BEVEL, brass)
        continue
    before = set(scene.objects)
    if kind == "factory":
        factory_icon(0.0, 0.0, 0.0, ICON_H, brass, soot)
    else:
        solar_icon(0.0, 0.0, 0.0, ICON_H, brass)
    iw, ih = ICON_SIZE[kind]
    M = (Matrix.Translation((cx - iw / 2 * scale, cy - ih / 2 * scale, 0.0))
         @ Matrix.Diagonal((scale, scale, 1.0, 1.0)))
    for ob in scene.objects:
        if ob not in before and ob.type == 'MESH':
            ob.data.transform(M)


# ------------------------------------------------------------------ light and camera
def area(name, loc, size_, energy, colour):
    lamp = bpy.data.lights.new(name, 'AREA')
    lamp.size, lamp.energy, lamp.color = size_, energy, colour
    ob = link(bpy.data.objects.new(name, lamp))
    ob.location = loc
    ob.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    return ob


# All of the light from one side (--light): a broad, low key, and a softer, higher fill from
# the same side, which the enamel mirrors as a sheen on that side and which keeps the bevels
# facing away from going dead black. From the right, every shadow falls left; from the top
# left, down and to the right. The world is a dim warm grey, which the metals mirror.
if args.light == "right":
    area("key", (13.0, 1.5, 4.2), 6.0, 5200.0, (1.0, 0.93, 0.82))
    area("fill", (7.5, 0.5, 8.0), 8.0, 1100.0, (0.85, 0.90, 1.0))
else:
    # From the top left, the same warm light that crosses the key art's map: strong, and near
    # enough that it falls off across the plate, bright at its top left and dimmer at its
    # bottom right; the fill kept low for contrast.
    # A sun: it lands evenly on the whole plate (owner), from the top left and high (about 66
    # degrees), so it lights the plate's face directly (owner), warm, with short, soft shadows
    # down and to the right; a low fill from the same side keeps the enamel's sheen.
    sun_data = bpy.data.lights.new("key", 'SUN')
    sun_data.energy = 4.0 if HIGH else 5.2
    sun_data.color, sun_data.angle = (1.0, 0.88, 0.70), math.radians(6.0)
    sun_ob = link(bpy.data.objects.new("key", sun_data))
    toward = (-0.33, 0.25, 0.91) if HIGH else (-0.62, 0.47, 0.63)       # 66 or 39 degrees up
    sun_ob.rotation_euler = Vector(toward).to_track_quat('Z', 'Y').to_euler()
    area("fill", (-6.0, 4.5, 8.0), 8.0, 650.0, (0.85, 0.90, 1.0))
    # More light over the whole plate (owner: stronger at the top left and reaching further
    # along it): a broad round warm lamp high over the plate's top-left quarter, the sun's
    # colour. The navy is too dark and the brass too metal to show a low light from the side,
    # but seen from straight above they mirror this one: a soft sheen on the enamel and gold
    # on the brass, strongest at the top left and fading across the plate, where its light
    # still reaches.
    pos, size_, watts = L.get("plate_lamp") or PLATE_LAMP
    lamp_ob = area("plate_lamp", pos, size_, watts, (1.0, 0.88, 0.70))
    lamp_ob.data.shape = 'DISK'
    if args.brass_light == "wide":
        # The brass as bright as CAPITAL's C over the left two thirds of the plate (owner). The
        # C is that colour because, fully metal and seen from straight above, its flat face
        # mirrors the lamp hanging over it; so a flat lamp as bright hangs level over the left
        # two thirds, and every brass face under it mirrors the same, the right third still
        # falling off to the deeper gold. It lights only the brass (light linking, below), or
        # the navy under it would take a grey sheen; the round lamp keeps the navy's.
        (bx, by, bz), (sx, sy), bw = L.get("brass_lamp") or (BRASS_LAMP_SINGLE if args.plate == "single"
                                                               else BRASS_LAMP)
        brass_lamp = bpy.data.lights.new("brass_lamp", 'AREA')
        brass_lamp.shape, brass_lamp.size, brass_lamp.size_y = 'RECTANGLE', sx, sy
        brass_lamp.energy, brass_lamp.color = bw, (1.0, 0.88, 0.70)
        link(bpy.data.objects.new("brass_lamp", brass_lamp)).location = (bx, by, bz)   # facing straight down
# The sun's shadows where the fire shines (owner: the glow is a light as well): its light would
# fill the shadows the glowing coal casts from the sun, but the navy enamel reflects almost
# none of its orange, so they stayed dark beside white-hot coal. So the glowing lumps and the
# bed cast no shadow from the sun or the fill (shadow linking); the dark coal above them, and
# everything else, still do.
if glowing:
    blockers = bpy.data.collections.new("sun_blockers")
    for ob in scene.objects:
        if ob.type == 'MESH':
            blockers.objects.link(ob)
    for ob, co in zip(blockers.objects, blockers.collection_objects):
        co.light_linking.link_state = 'EXCLUDE' if ob.name in glowing else 'INCLUDE'
    for ob in scene.objects:
        if ob.type == 'LIGHT':
            ob.light_linking.blocker_collection = blockers
    lit = bpy.data.collections.new("fire_lit")                 # what the fire's lamps light
    for ob in scene.objects:
        if ob.type == 'MESH' and not ob.name.startswith("coal_") and ob.name not in glowing:
            lit.objects.link(ob)
    for ob in scene.objects:
        if ob.name.startswith("fire_lamp"):
            ob.light_linking.receiver_collection = lit
if "brass_lamp" in scene.objects:
    # the wide lamp lights the brass alone (and the hex bar's silver AND, whose flat faces, fully
    # metal, would otherwise mirror the dark above them and read grey), the round one the rest
    BRASS_LAMP_LIGHTS = ("brass", "brass_dark") + (("brushed_silver",) if L.get("coal_hex") else ())
    brassy = {ob.name for ob in scene.objects if ob.type == 'MESH' and
              any(m and m.name.split(".")[0] in BRASS_LAMP_LIGHTS for m in ob.data.materials)}
    only_brass, but_brass = bpy.data.collections.new("brass_lit"), bpy.data.collections.new("plate_lit")
    for ob in scene.objects:
        if ob.type == 'MESH':
            (only_brass if ob.name in brassy else but_brass).objects.link(ob)
    scene.objects["brass_lamp"].light_linking.receiver_collection = only_brass
    scene.objects["plate_lamp"].light_linking.receiver_collection = but_brass
    print("BRASS lit by the wide lamp:", len(brassy))
world = bpy.data.worlds.new("world")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.12, 0.11, 0.10, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 0.8

res_x, res_y, ortho = framing(outline)
cam_data = bpy.data.cameras.new("cam")
cam_data.type = 'ORTHO'
cam_data.ortho_scale = ortho
cam = link(bpy.data.objects.new("cam", cam_data))
cam.location = (0.0, 0.0, 30.0)
scene.camera = cam
scene.render.resolution_x, scene.render.resolution_y = res_x, res_y
scene.render.film_transparent = True
scene.render.engine = 'CYCLES'
scene.cycles.samples = args.samples
scene.cycles.use_denoising = True
try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = 'METAL'
    prefs.get_devices()
    for d in prefs.devices:
        d.use = True
    scene.cycles.device = 'GPU'
except (KeyError, TypeError, AttributeError):
    scene.cycles.device = 'CPU'
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - Medium High Contrast'
scene.render.filepath = args.out
with open(os.path.splitext(args.out)[0] + ".light.json", "w") as f:    # for nameplate_finish.py
    f.write('{"light": "%s", "sun": "%s"}' % (args.light, args.sun))
if args.save:
    bpy.ops.wm.save_as_mainfile(filepath=args.save)
bpy.ops.render.render(write_still=True)
# The glow pass: the same frame with every light and the world off, so only what glows (the
# fire, the sparks) shows; nameplate_finish.py blooms from it, and the lit brass, however
# bright, is left alone.
for ob in scene.objects:
    if ob.type == 'LIGHT':
        ob.data.energy = 0.0
for k in FIRE_LIGHT:                        # the fire as seen, not the light it casts
    k.inputs[1].default_value, k.inputs[2].default_value = 1.0, 0.0
scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.0
scene.cycles.samples = min(args.samples, 48)
scene.render.filepath = os.path.splitext(args.out)[0] + ".glow.png"
bpy.ops.render.render(write_still=True)
print("NAMEPLATE", args.plate, args.carbon, scene.render.filepath, "fonts:", word_font.name, "/", and_font.name,
      "carbon x %.2f..%.2f feet %.2f top %.2f" % (cx0, cx1, y_foot, y_top))
