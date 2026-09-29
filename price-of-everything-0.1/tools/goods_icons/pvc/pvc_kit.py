"""PVC (g_033): a strapped bundle of PVC pipes and a PVC window-frame corner, on the isometric grid.

Reference: assets/icons/goods/medium/g_033_pvc.png (shipped AI art): seven cream pipes packed in a
hexagon (two on top, three across the middle, two below), their open ends facing lower left and
the bundle running up to the right, tied with two khaki straps; beside it, lower right, a cream
PVC window-frame corner (an upright member and a bottom member) whose broad face turns to the
right in shade, its cut ends showing the profile's hollow chambers, with a diagonal-cut
double-glazed pane in the corner.
The shipped art is already lit like the set (the pipe ends and tops pale, the right flanks and the
frame's broad face dotted), so its layout is kept as drawn: pipe axes along world +Y (ends facing
-Y), the frame standing in the world YZ plane facing +X. Owner rulings carried over: shipped
layout, isometric grid, the set's light, dots on the shaded sides, ink at every junction.
Units: pipe outer diameter 1.0 (bore 0.8), 3.4 long; frame members 0.6 deep and 0.5 thick.
"""
import math
from mathutils import Vector

PVC_REVISION = 'pvc_v15'
R_O, R_I, PIPE_L = 0.5, 0.40, 3.4
STRAPS = ((0.85, 1.07), (2.15, 2.37))         # strap spans along Y
STRAP_T = 0.03
ZC = 0.5 + math.sqrt(3) / 2 + STRAP_T         # bundle centre height: the bundle rests on its straps
# v2 -> v3: the shipped frame's members are nearly a pipe's diameter, with a stepped profile. One
# profile, (x, h) with h measured in from the frame's outer edge, runs along both members, which
# meet on a 45 degree mitre: a main chambered body, a raised lip on the -X (room) side, a glazing
# bead on the +X side, and the double glazing seated between them.
# OWNER (v4 -> v5): "that PVC isnt right, try using 3 point line for the linework on the
# crosssection of the PVC and also check the glass. it looks nothing like the old version". In the
# shipped art the glass is transparent: only the two panes' cut edges show, as two light strips
# rising from the seat and then slanting up to the top of the upright; and the cut ends show the
# thin-walled, chambered profile in fine lines. So the panes are just their cut-edge bars, and the
# cross-sections (the profile's outline and chambers at both cut ends, and the glass edges) are
# inked at 3 px; the members' long edges keep the set's 6 px.
# v5 -> v6: the shipped profile is about 1.45x taller (lip 1.40, bead 1.13, seat 0.80) and its
# glass edges are light bands, not hairlines.
FX0, FX1 = 1.55, 2.75                         # frame depth along X (its broad face at FX1 faces +X)
FY0, FY1, FZT = 0.60, 3.9, 3.0                # bottom member's front end; the frame's outer back edge; upright's top
# OWNER (v10 -> v11): "the shape is a bit simplistic for the window crossection. can you add an outer
# ridge like the old version used"; (v12 -> v13): "the outer ridge needs to then go back in - look at
# the cross section and try to map that outer ridge's shape". Mapped off the shipped front section and
# the scan down the shipped bottom member (84 : 30 : 108 : 42 px, upper face : ledge : rib : lower face):
# on the outer (+X) face a chunky rib stands out RIB over the middle third of the face, and below it the
# face returns further in than the band above (RECESS), so only a thin strip of it shows under the rib.
# v13's 0.14 rib returning to the upper line was too slight.
# v14 -> v15 (defect review): the rib starts at 0.37, so the 0.12 strip under it (10.8 px, 9 of them ink)
# no longer leaves a 1 px seam inside the outer contour.
RIB, RIB_H, RECESS = 0.20, (0.37, 0.75), 0.08  # rib: how far out (X), its span (h, in from the outer edge); the lower face's set-back
PROFILE = [(FX0, 0.0), (FX1 - RECESS, 0.0), (FX1 - RECESS, RIB_H[0]), (FX1 + RIB, RIB_H[0]), (FX1 + RIB, RIB_H[1]),
           (FX1, RIB_H[1]), (FX1, 1.13), (2.52, 1.13), (2.52, 0.80), (1.97, 0.80), (1.97, 1.40), (FX0, 1.40)]
SEAT = 0.80                                   # the glass seat, h
# v6 -> v7 (glass, "looks nothing like the old version"): as shipped, the double glazing is cut
# flush with the frame. Its two panes' cut edges rise straight out of the front section, slant up
# to the top of the upright and run flat into the top section; the glass faces are clear, so each
# pane shows only as its cut edge, a light strip the pane's thickness wide with a 3 px line either
# side (v6 drew each pane as a bar, three hairlines). The chambers are real tunnels, open at both
# cut ends (v6 printed them as flat patches). Walls are 0.08 so two 3 px lines keep a tone between.
CHAMBERS = [((1.63, 2.08), (0.08, 0.72)), ((2.17, 2.59), (0.08, 0.72)), ((1.63, 1.89), (0.88, 1.32))]   # the rib is solid
SECTION_INK = 3                               # px, the cross-section linework
PANES = ((2.06, 2.18), (2.31, 2.43))          # the two panes' X spans: 0.12 thick, 0.13 apart, centred in the 1.97-2.52 seat
# (v14 -> v15: pane 0's edge sat 0.05 from the lip's section line, and their two 3 px lines merged)
Z_GLASS, Y_GLASS = 2.05, 2.62                 # the front cut's top; where the slanting cut meets the upright's top

def pvc_pipe(K, name, cx, cz, mat, bore_m, label):
    """A hollow pipe along +Y: a closed ring solid; the bore's faces take the darker material."""
    ob = pw_revolve_y(K, name, [(0.0, R_I), (0.0, R_O), (PIPE_L, R_O), (PIPE_L, R_I)], mat, 128, cx, cz)
    ob.data.materials.append(bore_m)
    mid = (R_I + R_O) / 2
    for p in ob.data.polygons:
        c = p.center
        if math.hypot(c.x - cx, c.z - cz) < mid and 0.01 < c.y < PIPE_L - 0.01:
            p.material_index = 1
    ob['part_label'] = label
    for r, nm in ((R_O + E, 'outer'), (R_I - E, 'bore')):          # the open end's rims
        pts = [(cx + r * math.cos(2 * math.pi * k / 160), -E, cz + r * math.sin(2 * math.pi * k / 160)) for k in range(160)]
        tagged_line(K, '%s_end_%s' % (name, nm), pts, label, 6, True)['ink_width'] = 0
    return ob


def pvc_hull(centres, r, arc=10):
    """The rounded hexagon round circles of radius r at the given (x, z) hexagon vertices (CCW)."""
    cx = sum(c[0] for c in centres) / len(centres); cz = sum(c[1] for c in centres) / len(centres)
    pts = []
    for (x, z) in centres:
        phi = math.atan2(z - cz, x - cx)
        for k in range(arc + 1):
            a = phi - math.pi / 6 + (math.pi / 3) * k / arc
            pts.append((x + r * math.cos(a), z + r * math.sin(a)))
    return pts


def pvc_strap(K, name, centres, y0, y1, mat, label):
    """A flat band hugging the bundle: the ring between the hulls at R_O and R_O + STRAP_T, y0..y1.
    Its two rims are ink paths, so it keeps its outline over pipes that share its label."""
    inner = pvc_hull(centres, R_O - 0.004); outer = pvc_hull(centres, R_O + STRAP_T); n = len(inner)
    loops = [[(x, y0, z) for x, z in outer], [(x, y1, z) for x, z in outer], [(x, y1, z) for x, z in inner], [(x, y0, z) for x, z in inner]]
    vs = [p for loop in loops for p in loop]; fs = []
    for j in range(4):
        a, b = j * n, ((j + 1) % 4) * n
        fs += [(a + k, a + (k + 1) % n, b + (k + 1) % n, b + k) for k in range(n)]
    ob = mesh(K, name, vs, fs, mat, False); ob['part_label'] = label
    rim = pvc_hull(centres, R_O + STRAP_T + E)
    for side, y in (('front', y0 - E), ('back', y1 + E)):
        tagged_line(K, '%s_rim_%s' % (name, side), [(x, y, z) for x, z in rim], label, 6, True)['ink_width'] = 0
    return ob


def pvc_round(pts, r, n=4):
    """A closed 2D polygon with every corner rounded (a quadratic curve of reach r): thin polygon
    strokes pinhole at sharp corners, so the 3 px section paths turn smoothly."""
    out = []; m = len(pts)
    for k in range(m):
        a, v, b = Vector(pts[k - 1]), Vector(pts[k]), Vector(pts[(k + 1) % m])
        t = min(r, (v - a).length / 2.01, (b - v).length / 2.01)
        s0 = v + (a - v).normalized() * t; s1 = v + (b - v).normalized() * t
        for j in range(n + 1):
            u = j / n; out.append(tuple(s0 * (1 - u) ** 2 + v * 2 * u * (1 - u) + s1 * u * u))
    return out


def pvc_members(K, mat, label):
    """The two mitred frame members from PROFILE, with their ink: the long edges and the mitre seam at
    6 px (both members share a label, so nothing else would draw them) and the cut ends at 3 px."""
    n = len(PROFILE); outs = alk_outward(PROFILE)
    bottom = [(x, FY0, h) for x, h in PROFILE] + [(x, FY1 - h, h) for x, h in PROFILE]
    upright = [(x, FY1 - h, h) for x, h in PROFILE] + [(x, FY1 - h, FZT) for x, h in PROFILE]
    fs = [tuple(range(n)), tuple(n + k for k in range(n))] + [(k, (k + 1) % n, n + (k + 1) % n, n + k) for k in range(n)]
    obs = [mesh(K, 'frame_bottom', bottom, fs, mat, False), mesh(K, 'frame_upright', upright, fs, mat, False)]
    for ob in obs:
        ob['part_label'] = label
    pe = [(x + o.x * E, h + o.y * E) for (x, h), o in zip(PROFILE, outs)]
    ring = pvc_round(pe, 0.02)
    tagged_line(K, 'frame_end', [(x, FY0 - E, h) for x, h in ring], label, SECTION_INK, True)
    tagged_line(K, 'frame_top', [(x, FY1 - h, FZT + E) for x, h in ring], label, SECTION_INK, True)
    pvc_chambers(K, obs, mat, label)
    tagged_line(K, 'frame_mitre', [(x, FY1 - h, h) for x, h in pe], label, 6, True)['ink_width'] = 0
    for k, (x, h) in enumerate(pe):
        tagged_line(K, 'frame_run_b%d' % k, [(x, FY0 - E, h), (x, FY1 - h, h)], label, 6, False)
        tagged_line(K, 'frame_run_u%d' % k, [(x, FY1 - h, h), (x, FY1 - h, FZT + E)], label, 6, False)
    return obs


def pvc_cut(K, ob, boxes, mat):
    """Boolean difference of axis boxes ((x0, x1), (y0, y1), (z0, z1)) from ob, applied in place."""
    vs, fs = [], []
    for (x0, x1), (y0, y1), (z0, z1) in boxes:
        b = len(vs)
        vs += [(x, y, z) for z in (z0, z1) for y in (y0, y1) for x in (x0, x1)]
        fs += [(b, b + 2, b + 3, b + 1), (b + 4, b + 5, b + 7, b + 6), (b, b + 1, b + 5, b + 4),
               (b + 2, b + 6, b + 7, b + 3), (b, b + 4, b + 6, b + 2), (b + 1, b + 3, b + 7, b + 5)]
    cutter = mesh(K, ob.name + '_cutter', vs, fs, None, False)
    mod = ob.modifiers.new('cut', 'BOOLEAN'); mod.operation = 'DIFFERENCE'; mod.solver = 'EXACT'; mod.object = cutter
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    ob.modifiers.remove(mod); old = ob.data; ob.data = me; bpy.data.meshes.remove(old)
    me.materials.clear(); me.materials.append(mat)
    for poly in me.polygons:
        poly.use_smooth = False
    bpy.data.objects.remove(cutter, do_unlink=True)
    return noink(ob)


def pvc_chambers(K, members, mat, label):
    """Hollow the members: each chamber a tunnel along its member, open at the cut ends, meeting its
    twin at the mitre. Ink at 3 px: each mouth's rim on both cut faces and the tunnels' inner
    corners (hidden runs drop out, so only the stretch seen through a mouth draws)."""
    bottom, upright = members
    pvc_cut(K, bottom, [((a, b), (FY0 - 0.1, FY1 + 0.1), (c, d)) for (a, b), (c, d) in CHAMBERS], mat)
    pvc_cut(K, upright, [((a, b), (FY1 - d, FY1 - c), (-0.1, FZT + 0.1)) for (a, b), (c, d) in CHAMBERS], mat)
    for k, ((a, b), (c, d)) in enumerate(CHAMBERS):
        rim = pvc_round([(a - E, c - E), (b + E, c - E), (b + E, d + E), (a - E, d + E)], 0.02)
        tagged_line(K, 'chamber%d_front' % k, [(x, FY0 - E, h) for x, h in rim], label, SECTION_INK, True)
        tagged_line(K, 'chamber%d_top' % k, [(x, FY1 - h, FZT + E) for x, h in rim], label, SECTION_INK, True)
        for j, (x, h) in enumerate(((a + E, c + E), (b - E, c + E), (b - E, d - E), (a + E, d - E))):
            tagged_line(K, 'chamber%d_run_b%d' % (k, j), [(x, FY0, h), (x, FY1 - h, h)], label, SECTION_INK, False)
            tagged_line(K, 'chamber%d_run_u%d' % (k, j), [(x, FY1 - h, h), (x, FY1 - h, FZT)], label, SECTION_INK, False)


def pvc_pane(K, name, x0, x1, mat, label):
    """One pane of the double glazing, shown by its cut edge only: an open strip x0..x1 along the
    cut, up the front section, slanting to the upright's top and flat into its groove, with a 3 px
    line along each side."""
    # A hair inside the cut planes, its ends running down into the seat and back into the upright's
    # groove, so each pane is seated in the frame (not just touching its faces).
    path = [Vector((FY0 + 0.001, SEAT - 0.03)), Vector((FY0 + 0.001, Z_GLASS)), Vector((Y_GLASS, FZT - 0.001)), Vector((FY1 - SEAT + 0.03, FZT - 0.001))]
    vs = [(x, p.x, p.y) for p in path for x in (x0, x1)]
    fs = [(2 * k, 2 * k + 1, 2 * k + 3, 2 * k + 2) for k in range(len(path) - 1)]
    ob = pw_clean_water(mesh(K, name, vs, fs, mat, False)); ob['part_label'] = label
    offs = []
    for k in range(len(path)):
        segs = []
        if k > 0:
            d = (path[k] - path[k - 1]).normalized(); segs.append(Vector((-d.y, d.x)))
        if k < len(path) - 1:
            d = (path[k + 1] - path[k]).normalized(); segs.append(Vector((-d.y, d.x)))
        n = sum(segs, Vector((0.0, 0.0))).normalized()
        offs.append(n / max(0.3, n.dot(segs[0])))
    for side, x in (('a', x0 - E), ('b', x1 + E)):
        tagged_line(K, '%s_edge_%s' % (name, side), [(x, p.x + o.x * E, p.y + o.y * E) for p, o in zip(path, offs)], label, SECTION_INK, False)
    return ob


def build_pvc():
    """PVC v1: the shipped pipe bundle and window corner, on the grid, lit by the set's light."""
    setup_icon_rig(); K = Kit(open_collection('ICON_pvc')); hosts = []
    pipe_m = pw_toon('pvc_pipe', (0.62, 0.59, 0.51), ((0.70, 0.45), (0.95, 0.78), (9.0, 1.0)))
    bore_m = pw_toon('pvc_bore', (0.36, 0.34, 0.28), ((0.70, 0.60), (0.95, 0.85), (9.0, 1.0)))
    strap_m = pw_toon('pvc_strap', (0.40, 0.37, 0.24), ((0.70, 0.45), (0.95, 0.78), (9.0, 1.0)))
    # OWNER (v9 -> v10): "check that the PVC tubes and the slice of window have the same colour".
    # One PVC material for both, as shipped (pipe tops about (196,189,172), frame faces about
    # (192,185,167)); v9's paler frame misread a highlighted face as white PVC.
    frame_m = pipe_m
    glass_m = pw_flat('pvc_glass', (0.617, 0.760, 0.838))               # (206,226,236), the panes' cut edges
    L_CENTRE, L_RING_A, L_RING_B = 1, 2, 3
    # v7 -> v8: the glass also crosses the second strap, so the straps join the frame's label too
    # (their rims are ink paths); a label change there drew a 6 px box on the glass.
    L_STRAP = L_RING_A
    # The frame and its glass share the right-hand pipe's label (and the straps', above): the glass
    # crosses in front of that pipe, and a label change there would ring each thin glass edge with
    # a 6 px boundary. The frame's own edges are all ink paths, so it keeps its outline.
    L_FRAME = L_RING_A

    # Pipes: the centre one and a ring of six whose labels alternate, so every pipe keeps its own
    # outline where it meets a neighbour.
    ring = [(math.cos(k * math.pi / 3), ZC + math.sin(k * math.pi / 3)) for k in range(6)]
    hosts.append(pvc_pipe(K, 'pipe_c', 0.0, ZC, pipe_m, bore_m, L_CENTRE).name)
    for k, (x, z) in enumerate(ring):
        hosts.append(pvc_pipe(K, 'pipe_%d' % k, x, z, pipe_m, bore_m, L_RING_A if k % 2 == 0 else L_RING_B).name)
    for k, (y0, y1) in enumerate(STRAPS):
        hosts.append(pvc_strap(K, 'strap_%d' % k, ring, y0, y1, strap_m, L_STRAP).name)

    # Window-frame corner: two mitred members of the stepped profile; one label, so their broad +X
    # faces read as one L.
    hosts += [ob.name for ob in pvc_members(K, frame_m, L_FRAME)]
    # Double glazing, as shipped: two panes shown by their cut edges.
    for k, (x0, x1) in enumerate(PANES):
        pvc_pane(K, 'pane_%d' % k, x0, x1, glass_m, L_FRAME)

    info = contract(K, hosts, 'seven hollow PVC pipes in a strapped hexagonal bundle; a PVC window-frame corner, its chambered profile cut at both ends (3 px section lines) and its double glazing shown by the two panes\' cut edges')
    info['revision'] = PVC_REVISION
    info['outline']['component_boundaries'] = True
    info['stipple']['strength'] = 0.38
    info['stipple']['groups'][0]['thresholds'] = [0.65, 0.60, 0.35]
    info['dimensions'] = {'pipe': [R_O, R_I, PIPE_L], 'bundle_centre_z': ZC, 'straps': STRAPS, 'frame': [FX0, FX1, FY0, FY1, FZT], 'rib': [RIB, RIB_H, RECESS], 'profile': PROFILE, 'chambers': CHAMBERS, 'section_ink_px': SECTION_INK, 'panes': PANES, 'glass_cut': [Z_GLASS, Y_GLASS],}
    return info
