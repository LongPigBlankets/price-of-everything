"""Sodium-ion battery (g_060): a battery pack in a slotted steel crate, on the isometric grid.

Reference: assets/icons/goods/medium/g_060_sodium_battery.png (shipped AI art): an open steel crate
with rounded slots in its walls (two rows of tall slots and a row of small ones under them; six
across the short -Y side, seven along the long +X side), white cells in a grid inside, each with a
raised rounded plate on the part of its top without terminals and two terminals along its front
edge, and a charcoal cover over the back half
printed "Na-ion". The lithium battery (g_059) is the same pack with red cells and "Li-ion", so the
builder is shared: build_ion_pack(name, cell colour, text).
The shipped art is already lit like the set (tops pale, the -Y side mid grey, the +X side dark and
dotted), so its layout is kept as drawn: short side lower left (-Y), long side lower right (+X),
cells in front (low Y), cover at the back. Owner rulings carried over: shipped layout, isometric
grid, the set's light, dots on the shaded sides, ink at every junction between parts.
Proportions measured off the shipped art: crate 1.00 (X) x 1.11 (Y) x 0.54 (Z).
"""
import math
from mathutils import Vector

NA_REVISION = 'sodium_v12'
CR = (1.00, 1.11, 0.54)                      # crate outside: X, Y, Z
# v1 -> v2: 0.10-wide slots in a 0.04 wall drew as ink rings; the shipped slots are 0.115 wide
# with 0.04 webs, and a thinner wall keeps the band inside each slot a crescent.
# v5 -> v6 (review): two 6 px lines leave no tone between them under ~0.045, so every feature
# that shows between two lines is at least 0.045 or nothing: cells meet (one line), panels are
# flat, the cover is 0.045 thick, and the rim gets a 0.05 lip.
T_WALL, T_FLOOR = 0.03, 0.03
LIP_W, LIP_H = 0.05, 0.045                   # the rim: a lip 0.05 wide in the wall's top 0.045
SLOT_W, SLOT_R = 0.115, 0.05                 # tall slots: width, corner radius (nearly a stadium)
ROWS = ((0.125, 0.29), (0.325, 0.49))        # tall slot rows (z0, z1); the top row ends under the lip
SMALL = (0.045, 0.09, 0.075)                 # small slot row: z0, z1, width
COLS = (6, 0.157, 7, 0.150)                  # slots across -Y (count, pitch), along +X (count, pitch)
GRID = (3, 3)                                # cells along X, along Y
# OWNER (v8 -> v9): "we seem to have lost the outline of each individual unit in the crate. They
# had rounded corners. And also a plate on top of the cathode-less section". Each cell is its own
# rounded block with its own outline, 0.045 apart (a groove of tone between two lines, not v5's
# 0.03 bar), and carries a raised rounded plate behind its terminals.
CELL_GAP, CELL_R, CELL_TOP = 0.045, 0.03, 0.492       # tops 0.048 under the rim
# The rim hides the cell tops within LIP_W + 0.048 = 0.098 of the near (-Y, +X) walls. The grid
# starts and ends under that shadow so the front row's and the right column's washers stay 0.03
# clear of it (v5's front row fused with the rim line); the hidden margins never show.
GRID_X, GRID_Y = (0.036, 0.914), (0.09, 1.074)
TERM_X, TERM_Y = 0.07, 0.066                 # terminal centres in from a cell's sides, and from its front
# Plate: insets from the cell's left (-X), right (+X) and back (+Y) edges, gap behind the washers,
# height, corner radius. On this camera a raised edge inset by its own height from a -X or +Y edge
# draws on that edge's line (v11's back and left plate edges vanished into the cell outline), so
# those insets clear the 0.02 height by 0.04; the right edge never lines up.
PLATE_IN, PLATE_GAP, PLATE_H, PLATE_R = (0.06, 0.035, 0.06), 0.02, 0.02, 0.025
R_WASH, H_WASH, R_POST, H_POST = 0.028, 0.012, 0.017, 0.045
COVER_Y0, COVER_T = 0.605, 0.045             # the cover, resting on the cells: front edge, thickness (under the rim)
# OWNER (v10 -> v11): "maybe thinner lines for those plates?". The plates are inked in 3 px lines,
# half the set's 6 px interior weight: they share their cell's part label (so no 6 px boundary is
# drawn round them) and carry their own top, foot and side-silhouette paths.
PLATE_INK = 3


def ion_prism_mesh(pts, place, a0, a1, vs, fs):
    """Append a prism: a closed (u, v) outline placed by place(u, v, a) at a = a0 and a = a1."""
    n = len(pts); base = len(vs)
    vs.extend(place(u, v, a0) for u, v in pts); vs.extend(place(u, v, a1) for u, v in pts)
    fs.append(tuple(range(base, base + n))); fs.append(tuple(range(base + n, base + 2 * n)))
    fs.extend((base + k, base + (k + 1) % n, base + n + (k + 1) % n, base + n + k) for k in range(n))


def ion_cut(ob, cutter, mat):
    """Boolean difference, applied: ob keeps one closed mesh; the cutter is deleted."""
    mod = ob.modifiers.new('cut', 'BOOLEAN'); mod.operation = 'DIFFERENCE'; mod.solver = 'EXACT'; mod.object = cutter
    bpy.context.view_layer.update()
    ev = ob.evaluated_get(bpy.context.evaluated_depsgraph_get())
    me = bpy.data.meshes.new_from_object(ev)
    ob.modifiers.remove(mod); old = ob.data; ob.data = me; bpy.data.meshes.remove(old)
    me.materials.clear(); me.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = False
    bpy.data.objects.remove(cutter, do_unlink=True)
    return noink(ob)


def ion_slots():
    """Every slot as (wall, u, v, w, h, r): wall '-Y' has u = x, wall '+X' has u = y; v = z."""
    X1, Y1, _ = CR; out = []
    for wall, n, pitch, length in (('-Y', COLS[0], COLS[1], X1), ('+X', COLS[2], COLS[3], Y1)):
        for k in range(n):
            u = length / 2 + (k - (n - 1) / 2) * pitch
            for z0, z1 in ROWS:
                out.append((wall, u, (z0 + z1) / 2, SLOT_W, z1 - z0, SLOT_R))
            out.append((wall, u, (SMALL[0] + SMALL[1]) / 2, SMALL[2], SMALL[1] - SMALL[0], (SMALL[1] - SMALL[0]) / 2 - 0.001))
    return out


def ion_wall_place(wall, depth):
    """Map a wall's (u, v) and a depth into the wall (0 = outer face) to world coordinates."""
    X1 = CR[0]
    if wall == '-Y':
        return lambda u, v, a: (u, a, v)
    return lambda u, v, a: (X1 - a, u, v)


def ion_crate(K, mat, label):
    X1, Y1, Z1 = CR
    crate = noink(K.box('crate', X1 / 2, Y1 / 2, Z1 / 2, X1, Y1, Z1, mat)); crate['part_label'] = label
    top, zl = Z1 + 0.10, Z1 - LIP_H
    cav = K.box('crate_cavity', X1 / 2, Y1 / 2, (T_FLOOR + zl) / 2, X1 - 2 * T_WALL, Y1 - 2 * T_WALL, zl - T_FLOOR)
    ion_cut(crate, cav, mat)
    mouth = K.box('crate_mouth', X1 / 2, Y1 / 2, (zl - 0.01 + top) / 2, X1 - 2 * LIP_W, Y1 - 2 * LIP_W, top - zl + 0.01)
    ion_cut(crate, mouth, mat)
    vs, fs = [], []
    for wall, u, v, w, h, r in ion_slots():
        ion_prism_mesh(rect_points(u, v, w, h, r, 10), ion_wall_place(wall, 0), -0.02, T_WALL + 0.01, vs, fs)
    ion_cut(crate, mesh(K, 'crate_slot_cutters', vs, fs, None, False), mat)
    crate['part_label'] = label
    # Ink: the outer box edges, the rim's inner outline, the cavity's corners, and each slot's
    # outline on the outer face; hidden runs drop out. v2 -> v3: a second ring where the slot's
    # inner edge meets the cells behind swamped every opening; the wall's thickness now shows as a
    # tone crescent (the cells share the crate's label, so no boundary is drawn there).
    xs, ys, zs = (-E, X1 + E), (-E, Y1 + E), (-E, Z1 + E); k = 0
    for y in ys:
        for z in zs:
            tagged_line(K, 'crate_edge%d' % k, [(xs[0], y, z), (xs[1], y, z)], label, 6, False); k += 1
    for x in xs:
        for z in zs:
            tagged_line(K, 'crate_edge%d' % k, [(x, ys[0], z), (x, ys[1], z)], label, 6, False); k += 1
    for x in xs:
        for y in ys:
            tagged_line(K, 'crate_edge%d' % k, [(x, y, zs[0]), (x, y, zs[1])], label, 6, False); k += 1
    # The lip's inner outline on top, its inner face's foot (seen on the far walls above the cells,
    # which share this label) and its inner corners.
    a0, a1, b0, b1 = LIP_W + E, X1 - LIP_W - E, LIP_W + E, Y1 - LIP_W - E
    ring = [(a0, b0), (a1, b0), (a1, b1), (a0, b1)]
    tagged_line(K, 'crate_rim_inner', [(x, y, Z1 + E) for x, y in ring], label, 6, True)['ink_width'] = 0
    tagged_line(K, 'crate_lip_foot', [(x, y, Z1 - LIP_H - E) for x, y in ring], label, 6, True)['ink_width'] = 0
    for k, (x, y) in enumerate(ring):
        tagged_line(K, 'crate_lip_corner%d' % k, [(x, y, Z1 - LIP_H - E), (x, y, Z1 + E)], label, 6, False)
    for k, (wall, u, v, w, h, r) in enumerate(ion_slots()):
        place = ion_wall_place(wall, 0); pts = rect_points(u, v, w - 2 * E, h - 2 * E, r - E, 10)
        tagged_line(K, 'slot%d_outer' % k, [place(p, q, -E) for p, q in pts], label, 6, True)['ink_width'] = 0
    return crate


def ion_block(K, name, x0, x1, y0, y1, z0, z1, mat, label, top_only=False):
    """A solid box whose 12 edges are ink paths (alkaline's alk_box). top_only: just the top
    outline, for cells whose sides show only through the slots (v3 -> v4: their side edges drew
    stray bars inside the openings)."""
    if not top_only:
        return alk_box(K, name, x0, x1, y0, y1, z0, z1, mat, label)
    ob = alk_box(K, name, x0, x1, y0, y1, z0, z1, mat, label, edges=False)
    tagged_line(K, name + '_top', [(x0 - E, y0 - E, z1 + E), (x1 + E, y0 - E, z1 + E), (x1 + E, y1 + E, z1 + E), (x0 - E, y1 + E, z1 + E)], label, 6, True)['ink_width'] = 0
    return ob


def ion_rounded(K, name, outline, z0, z1, mat, label):
    """A rounded-corner block from an XY outline: closed prism, ink on its top outline. Its foot and
    sides are drawn by the part labels or hidden (a cell's sides show only in the grooves and slots)."""
    vs, fs = [], []
    ion_prism_mesh(outline, lambda u, v, a: (u, v, a), z0, z1, vs, fs)
    ob = mesh(K, name, vs, fs, mat, False); ob['part_label'] = label
    ring = [Vector(p) + o * E for p, o in zip(outline, alk_outward(outline))]
    tagged_line(K, name + '_top', [(p.x, p.y, z1 + E) for p in ring], label, 6, True)['ink_width'] = 0
    return ob


def ion_plate(K, name, outline, z0, z_foot, z1, mat, label, width):
    """A raised rounded plate inked by its own paths at `width` px: the top outline, the foot where
    it meets the surface at z_foot, and the two vertical silhouettes (where the outline's normal is
    square to the view, +X -Y). Hidden runs drop out."""
    vs, fs = [], []
    ion_prism_mesh(outline, lambda u, v, a: (u, v, a), z0, z1, vs, fs)
    ob = mesh(K, name, vs, fs, mat, False); ob['part_label'] = label
    outs = alk_outward(outline)
    ring = [Vector(p) + o * E for p, o in zip(outline, outs)]
    tagged_line(K, name + '_top', [(p.x, p.y, z1 + E) for p in ring], label, width, True)
    tagged_line(K, name + '_foot', [(p.x, p.y, z_foot + E) for p in ring], label, width, True)
    diag = Vector((1.0, 1.0)).normalized()
    for side, sgn in (('right', 1.0), ('left', -1.0)):
        k = max(range(len(outs)), key=lambda i: outs[i].dot(diag) * sgn)
        tagged_line(K, '%s_%s' % (name, side), [(ring[k].x, ring[k].y, z_foot + E), (ring[k].x, ring[k].y, z1 + E)], label, width, False)
    return ob


def build_ion_pack(name, cell_rgb, text, revision):
    setup_icon_rig(); K = Kit(open_collection('ICON_' + name)); hosts = []
    crate_m = pw_toon(name + '_crate', (0.60, 0.62, 0.63), ((0.70, 0.34), (0.95, 0.62), (9.0, 1.0)))     # top (203,206,207), -Y (164), +X (125)
    cell_m = pw_toon(name + '_cell', cell_rgb, ((0.70, 0.50), (0.95, 0.88), (9.0, 1.0)))    # v6: the slot windows read white (-Y ~218)
    term_m = pw_toon(name + '_terminal', (0.40, 0.41, 0.43), ((0.70, 0.40), (0.95, 0.70), (9.0, 1.0)))       # v6: top (170,172,176), as shipped
    plate_m = pw_toon(name + '_cover', (0.095, 0.11, 0.11), ((0.70, 0.45), (0.95, 0.70), (9.0, 1.0)))    # top (86,93,93) as shipped
    text_m = pw_flat(name + '_print', (0.86, 0.86, 0.84))
    L_CRATE, L_TERMINAL, L_COVER = 1, 4, 5
    L_CELL = L_CRATE                                   # cells draw their own edges; see ion_crate

    crate = ion_crate(K, crate_m, L_CRATE); hosts.append(crate.name)
    X1, Y1, Z1 = CR; nx, ny = GRID
    cw = (GRID_X[1] - GRID_X[0] - (nx - 1) * CELL_GAP) / nx; cd = (GRID_Y[1] - GRID_Y[0] - (ny - 1) * CELL_GAP) / ny
    for i in range(nx):
        for j in range(ny):
            x0 = GRID_X[0] + i * (cw + CELL_GAP); y0 = GRID_Y[0] + j * (cd + CELL_GAP); nm = 'cell_%d%d' % (i, j)
            hosts.append(ion_rounded(K, nm, alk_rect(x0, x0 + cw, y0, y0 + cd, CELL_R), T_FLOOR, CELL_TOP, cell_m, L_CELL).name)
            ty = y0 + TERM_Y; pf = ty + R_WASH + PLATE_GAP
            if pf < COVER_Y0:                              # the plate behind the terminals; one reaching the cover runs under it
                hosts.append(ion_plate(K, nm + '_plate', alk_rect(x0 + PLATE_IN[0], x0 + cw - PLATE_IN[1], pf, y0 + cd - PLATE_IN[2], PLATE_R),
                                       CELL_TOP - 0.003, CELL_TOP, CELL_TOP + PLATE_H, cell_m, L_CELL, PLATE_INK).name)
            if ty + R_WASH > COVER_Y0:
                continue                                   # terminals under the cover are left out
            for s, tx in (('a', x0 + TERM_X), ('b', x0 + cw - TERM_X)):
                # v2 -> v3: one outlined peg (washer and post as one turned part); at ~0.03 across,
                # separate outlines for washer, post and its top filled the terminal with ink.
                term = pw_lathe_z(K, '%s_terminal_%s' % (nm, s), [(0, CELL_TOP - 0.004), (R_WASH, CELL_TOP - 0.004), (R_WASH, CELL_TOP + H_WASH),
                                  (R_POST, CELL_TOP + H_WASH), (R_POST, CELL_TOP + H_WASH + H_POST), (0, CELL_TOP + H_WASH + H_POST)], term_m, (tx, ty))
                term['part_label'] = L_TERMINAL; hosts.append(term.name)
    # The cover over the back of the pack, resting on the panels, with the chemistry printed on it.
    c0, c1 = LIP_W + 0.005, X1 - LIP_W - 0.005
    cz0 = CELL_TOP - 0.002; cz1 = cz0 + COVER_T
    hosts.append(ion_block(K, 'cover', c0, c1, COVER_Y0, Y1 - LIP_W - 0.005, cz0, cz1, plate_m, L_COVER).name)
    word = formula_mesh(K.col, 'cover_print', text, text_m, 0.58, 0.16, chemical=False)
    cx, cy = (c0 + c1) / 2, (COVER_Y0 + Y1 - LIP_W) / 2
    for v in word.data.vertices:                           # baseline along +X, letters up along +Y
        v.co = Vector((cx + v.co.x, cy + v.co.y, cz1 + 0.002))
    word['part_label'] = L_COVER; pw_clean_water(noink(word))
    info = contract(K, hosts, 'battery pack: slotted steel crate, %d rounded cells with raised plates and front terminals, charcoal cover printed "%s"' % (nx * ny, text))
    info['revision'] = revision
    info['outline']['component_boundaries'] = True
    info['stipple']['strength'] = 0.38
    info['stipple']['groups'][0]['thresholds'] = [0.65, 0.60, 0.35]    # +X faces (mask 0.53) take the 2x lattice
    info['dimensions'] = {'crate': list(CR), 'walls': [T_WALL, T_FLOOR], 'lip': [LIP_W, LIP_H], 'slots': {'width': SLOT_W, 'rows': ROWS, 'small': SMALL, 'cols': COLS},
                          'cells': {'grid': GRID, 'span': [GRID_X, GRID_Y], 'size': [round(cw, 4), round(cd, 4)], 'top': CELL_TOP, 'gap': CELL_GAP, 'corner': CELL_R,
                                    'terminals': [TERM_X, TERM_Y], 'plate': [PLATE_IN, PLATE_GAP, PLATE_H, PLATE_R], 'plate_ink_px': PLATE_INK},
                          'cover': [COVER_Y0, COVER_T], 'text': text}
    return info


def build_sodium_battery():
    """Sodium-ion battery v1: the shipped pack on the grid, white cells, "Na-ion" cover."""
    return build_ion_pack('sodium_battery', (0.80, 0.81, 0.80), 'Na-ion', NA_REVISION)
