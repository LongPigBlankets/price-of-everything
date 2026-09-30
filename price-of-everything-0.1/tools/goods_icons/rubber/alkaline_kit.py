"""Alkaline battery (g_070): a starter battery on the isometric grid.

Reference: assets/icons/goods/medium/alkaline_battery.png (shipped AI art): a grey case with a
charcoal lid; a raised panel on the lid leaves two terminal wells at the ends of one long side,
a copper-ringed + post and a grey-ringed - post, a + and a - printed on the lid beside them, and a
green-framed cream label with + and - discs on the long face.
Owner rulings carried over from power (2026-09-29): keep the shipped layout, draw it on the
isometric grid, light it with the set's light, stipple the shaded sides. So the long label face
turns lower right (world +X) and the short end lower left (-Y), as shipped. Under the set's light
the long face is the shade side: the case around the label takes the kit's 2x dot lattice (as on
power) and the label is kept clean so it reads. The end and the lid face the light.
Proportions measured off the shipped art: case 1.00 (X) x 1.55 (Y) x 1.10 (Z); label frame over
0.17-1.38 of the length and 0.21-0.94 of the height; terminal wells about 0.44 square.
"""
import math
from mathutils import Vector

ALK_REVISION = 'alkaline_v4'
CX, CY, CZ = 1.00, 1.55, 1.10               # case: X across the end, Y along the label side, Z up
LID_O, LID_T = 0.035, 0.13                   # lid slab: overhang past the case, thickness
# v1 -> v2: a 0.04 ledge drew as a doubled line; 0.075 reads as the shipped art's ledge.
PAN_M, PAN_T = 0.075, 0.10                   # raised panel: inset from the slab edge, height
WX, W1, W2 = 0.60, 0.415, 1.135              # wells: inner wall x; + well's far y; - well's near y
POSTS = (('plus', 0.79, 0.215), ('minus', 0.79, 1.40))
R_COL, H_COL, R_P0, R_P1, H_POST = 0.09, 0.066, 0.052, 0.044, 0.135
FRAME = (0.17, 1.38, 0.21, 0.94)             # label frame: u (along Y) and v (up) on the +X face
INNER = (0.215, 1.335, 0.255, 0.895)         # its inner border line
BAND = (0.43, 0.81)                          # the cream band across the label (v1 -> v2: 0.42 tall as shipped)
E = 0.004                                    # ink paths sit this far off the surfaces they trace


def alk_outward(pts):
    """Per-vertex outward bisectors of a closed 2D outline, either winding."""
    n = len(pts)
    area = sum(pts[k][0] * pts[(k + 1) % n][1] - pts[(k + 1) % n][0] * pts[k][1] for k in range(n))
    sgn = 1.0 if area > 0 else -1.0          # CCW: outward = (dy, -dx); CW: the opposite
    out = []
    for k in range(n):
        a = Vector(pts[k - 1]); b = Vector(pts[k]); c = Vector(pts[(k + 1) % n])
        d1 = (b - a).normalized(); d2 = (c - b).normalized()
        out.append((Vector((d1.y, -d1.x)) * sgn + Vector((d2.y, -d2.x)) * sgn).normalized())
    return out


def alk_box(K, name, x0, x1, y0, y1, z0, z1, mat, label, edges=True):
    """An axis-aligned solid. Its 12 edges go in as ink paths pushed a hair out along both faces
    they border: one material and one label, so nothing else would ink them. Hidden ones drop out."""
    ob = noink(K.box(name, (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2, x1 - x0, y1 - y0, z1 - z0, mat))
    ob['part_label'] = label
    if edges:
        xs, ys, zs = (x0 - E, x1 + E), (y0 - E, y1 + E), (z0 - E, z1 + E)
        k = 0
        for y in ys:
            for z in zs:
                tagged_line(K, '%s_edge%d' % (name, k), [(xs[0], y, z), (xs[1], y, z)], label, 6, False); k += 1
        for x in xs:
            for z in zs:
                tagged_line(K, '%s_edge%d' % (name, k), [(x, ys[0], z), (x, ys[1], z)], label, 6, False); k += 1
        for x in xs:
            for y in ys:
                tagged_line(K, '%s_edge%d' % (name, k), [(x, y, zs[0]), (x, y, zs[1])], label, 6, False); k += 1
    return ob


def alk_panel(K, name, outline, z0, z_foot, z1, mat, label):
    """An XY outline extruded z0..z1 (z0 sunk below the surface it stands on, z_foot). Ink: the top
    outline, the foot where the walls meet that surface, and the vertical corners above it."""
    n = len(outline)
    vs = [(x, y, z0) for x, y in outline] + [(x, y, z1) for x, y in outline]
    fs = [tuple(range(n)), tuple(n + k for k in range(n))] + [(k, (k + 1) % n, n + (k + 1) % n, n + k) for k in range(n)]
    ob = mesh(K, name, vs, fs, mat, False); ob['part_label'] = label
    ring = [Vector(p) + o * E for p, o in zip(outline, alk_outward(outline))]
    # v2 -> v3: the outlines turn sharp corners, where the exporter's polygon strokes leave a
    # pinhole; ink_width 0 strokes them as round-jointed lines of the same 6 px weight.
    for nm, z in (('_top', z1 + E), ('_foot', z_foot + E)):
        tagged_line(K, name + nm, [(p.x, p.y, z) for p in ring], label, 6, True)['ink_width'] = 0
    # A vertical corner shows if a wall beside it faces the camera; an inner (reflex) corner only if
    # both do. Otherwise its tip pokes over the top edge as a tick (v1's - well).
    area = sum(outline[k][0] * outline[(k + 1) % n][1] - outline[(k + 1) % n][0] * outline[k][1] for k in range(n))
    cam = Vector((1.0, -1.0)).normalized()
    for k, p in enumerate(ring):
        a = Vector(outline[k - 1]); b = Vector(outline[k]); c = Vector(outline[(k + 1) % n])
        d1 = (b - a).normalized(); d2 = (c - b).normalized(); sgn = 1.0 if area > 0 else -1.0
        seen1 = Vector((d1.y, -d1.x)).dot(cam) * sgn > 1e-6; seen2 = Vector((d2.y, -d2.x)).dot(cam) * sgn > 1e-6
        convex = (d1.x * d2.y - d1.y * d2.x) * sgn > 0
        if (convex and (seen1 or seen2)) or (not convex and seen1 and seen2):
            tagged_line(K, '%s_corner%d' % (name, k), [(p.x, p.y, z_foot + E), (p.x, p.y, z1 + E)], label, 6, False)
    return ob


def alk_print(K, name, uv, x0, x1, mat, label):
    """A flat printed shape on the +X face: a (u, v) = (y, z) outline, x0..x1 thick, never dotted."""
    n = len(uv)
    vs = [(x0, u, v) for u, v in uv] + [(x1, u, v) for u, v in uv]
    fs = [tuple(range(n)), tuple(n + k for k in range(n))] + [(k, (k + 1) % n, n + (k + 1) % n, n + k) for k in range(n)]
    ob = pw_clean_water(mesh(K, name, vs, fs, mat, False)); ob['part_label'] = label
    return ob


def alk_rect(u0, u1, v0, v1, r, seg=12):
    return rect_points((u0 + u1) / 2, (v0 + v1) / 2, u1 - u0, v1 - v0, r, seg)


def build_alkaline_battery():
    """Alkaline battery v1: the shipped starter battery on the grid, lit by the set's light."""
    setup_icon_rig(); K = Kit(open_collection('ICON_alkaline_battery')); hosts = []
    # Tones under the set's light: tops 1.0, the lit end (-Y) the middle step, the shaded long
    # side (+X) the low step, dotted.
    case_m = pw_toon('alk_case', (0.415, 0.44, 0.515), ((0.70, 0.44), (0.95, 0.80), (9.0, 1.0)))     # end (156,160,172), side (118,122,132)
    lid_m = pw_toon('alk_lid', (0.125, 0.13, 0.145), ((0.70, 0.45), (0.95, 0.70), (9.0, 1.0)))       # top (99,101,106)
    post_m = pw_toon('alk_post', (0.52, 0.55, 0.62), ((0.70, 0.50), (0.95, 0.78), (9.0, 1.0)))
    ring_m = pw_toon('alk_ring', (0.40, 0.42, 0.48), ((0.70, 0.50), (0.95, 0.78), (9.0, 1.0)))
    copper_m = pw_toon('alk_copper', (0.86, 0.25, 0.045), ((0.70, 0.50), (0.95, 0.78), (9.0, 1.0)))
    green_m = pw_flat('alk_label_green', (0.080, 0.262, 0.144))       # (80,140,106): the shipped green, a shade down
    cream_m = pw_flat('alk_label_cream', (0.776, 0.761, 0.638))       # (228,226,209)
    grey_m = pw_flat('alk_label_grey', (0.445, 0.434, 0.392))         # (178,176,168)
    print_m = pw_flat('alk_print', (0.007, 0.012, 0.042))             # ink navy
    L_CASE, L_LID, L_POST, L_COLLAR, L_FRAME, L_CREAM, L_MARK = 1, 2, 3, 4, 5, 6, 7

    case = alk_box(K, 'case', 0.0, CX, 0.0, CY, 0.0, CZ, case_m, L_CASE); hosts.append(case.name)
    LZ1 = CZ + LID_T
    lid = alk_box(K, 'lid', -LID_O, CX + LID_O, -LID_O, CY + LID_O, CZ, LZ1, lid_m, L_LID); hosts.append(lid.name)
    # Raised panel: the slab less a margin, less the two wells at the ends of the label side.
    a0, a1 = -LID_O + PAN_M, CX + LID_O - PAN_M
    b0, b1 = -LID_O + PAN_M, CY + LID_O - PAN_M
    outline = [(a0, b0), (a0, b1), (WX, b1), (WX, W2), (a1, W2), (a1, W1), (WX, W1), (WX, b0)]
    panel = alk_panel(K, 'panel', outline, LZ1 - 0.02, LZ1, LZ1 + PAN_T, lid_m, L_LID); hosts.append(panel.name)
    # Terminals: a two-ring collar (copper on +, grey on -) and a tapered post with a flat top.
    for nm, px, py in POSTS:
        c = (px, py); zc = LZ1 + H_COL
        collar = pw_lathe_z(K, 'collar_' + nm, [(0, LZ1 - 0.01), (R_COL, LZ1 - 0.01), (R_COL, zc), (0, zc)],
                            copper_m if nm == 'plus' else ring_m, c)
        post = pw_lathe_z(K, 'post_' + nm, [(0, zc - 0.01), (R_P0, zc - 0.01), (R_P0, zc), (R_P1, zc + H_POST), (0, zc + H_POST)], post_m, c)
        collar['part_label'] = L_COLLAR; post['part_label'] = L_POST
        hosts += [collar.name, post.name]
        pw_circle_z(K, 'collar_%s_top' % nm, c, zc + E, R_COL + E, L_COLLAR)
        pw_circle_z(K, 'collar_%s_split' % nm, c, LZ1 + H_COL / 2, R_COL + E, L_COLLAR)   # reads as two stacked rings
        pw_circle_z(K, 'post_%s_top' % nm, c, zc + H_POST + E, R_P1 + E, L_POST)
    # The + and - printed on the lid to the right of their posts (as shipped), drawn along the
    # grid; the - is the +'s bar along Y. OWNER (v3 -> v4): "missing the - on the far side".
    for k, (sx, sy) in enumerate(((0.075, 0.02), (0.02, 0.075))):
        m = noink(K.box('lid_plus_%d' % k, 0.93, 0.35, LZ1 + 0.002, sx, sy, 0.004, print_m))
        m['part_label'] = L_LID; m.pass_index = 73
    m = noink(K.box('lid_minus', 0.91, 1.515, LZ1 + 0.002, 0.02, 0.075, 0.004, print_m))
    m['part_label'] = L_LID; m.pass_index = 73
    # Label on the long (+X) face: green frame with an inner border, a cream band, grey tabs above
    # and below it, and + and - discs in the lower corners.
    alk_print(K, 'label_frame', alk_rect(*FRAME, 0.05), CX - 0.002, CX + 0.004, green_m, L_FRAME)
    # As shipped: the tabs are slanted the same way; the band steps down onto the lower tab.
    TAB = 0.35                                   # top of the lower tab
    alk_print(K, 'label_band', [(INNER[0], BAND[0]), (0.545, BAND[0]), (0.51, TAB), (1.06, TAB), (1.094, BAND[0]),
                                (INNER[1], BAND[0]), (INNER[1], BAND[1]), (INNER[0], BAND[1])], CX + 0.002, CX + 0.007, cream_m, L_CREAM)
    alk_print(K, 'label_tab_top', [(0.52, BAND[1]), (1.07, BAND[1]), (1.106, INNER[3]), (0.556, INNER[3])], CX + 0.002, CX + 0.007, grey_m, L_MARK)
    alk_print(K, 'label_tab_bottom', [(0.47, INNER[2]), (1.02, INNER[2]), (1.06, TAB), (0.51, TAB)], CX + 0.002, CX + 0.007, grey_m, L_MARK)
    tagged_line(K, 'label_inner_border', [(CX + 0.012, u, v) for u, v in alk_rect(*INNER, 0.03)], L_FRAME, 6, True)
    for nm, du, sign in (('plus', 0.33, '+'), ('minus', 1.225, '-')):
        dv = (INNER[2] + BAND[0]) / 2
        disc = pw_clean_water(K.cyl('disc_' + nm, CX + 0.0045, du, dv, 0.052, 0.005, cream_m, axis='X', segments=64))
        disc['part_label'] = L_MARK
        for k, (sy, sz) in enumerate([(0.06, 0.016)] + ([(0.016, 0.06)] if sign == '+' else [])):
            m = pw_clean_water(noink(K.box('disc_%s_bar%d' % (nm, k), CX + 0.0085, du, dv, 0.003, sy, sz, print_m)))
            m['part_label'] = L_MARK; m.pass_index = 73
    info = contract(K, hosts, 'starter battery: grey case, charcoal lid with a raised panel and two terminal wells on the label side, collared posts, green-framed label on the long (+X) face')
    info['revision'] = ALK_REVISION
    info['outline']['component_boundaries'] = True
    info['stipple']['strength'] = 0.38
    info['stipple']['groups'][0]['thresholds'] = [0.65, 0.60, 0.35]    # +X faces (mask 0.53) take the 2x lattice, as on power
    info['dimensions'] = {'case': [CX, CY, CZ], 'lid': [LID_O, LID_T], 'panel': [PAN_M, PAN_T], 'wells': [WX, W1, W2],
                          'posts': [list(p) for p in POSTS], 'terminal': [R_COL, H_COL, R_P0, R_P1, H_POST],
                          'label': {'frame': FRAME, 'inner': INNER, 'band': BAND}}
    return info
