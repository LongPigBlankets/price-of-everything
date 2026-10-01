"""Power (g_010): an extruded lightning bolt on the isometric grid.

Reference: assets/icons/goods/medium/g_010_power.png (shipped AI art): a golden bolt whose
thickness shows on its LEFT, grey with dots, so it is lit from the right. The set and DS2's
house light are lit from the upper left.
OWNER 2026-09-29, in order: "needs the lighting updated because the old ai icon has shading on
the left side"; "don't flip the power icon, still show it in the same orientation but fix the
lighting"; "i think the perspective is still broken. Need it to follow the isometric
perspective".
So the bolt is drawn like every other good: its face lies in the world XZ plane (facing the
set's front, -Y), its flat edges (the top, the notch step and the step under the upper bar) run
along world X, and it is extruded straight back along world Y. Tracing the shipped outline
(or turning the bolt about Z) took it off the grid and was dropped. The outline keeps the
shipped pose and proportions: notch jutting right, tip at the bottom left, the bars leaning
right. From the fixed camera the thickness then shows on the RIGHT (the shadow step, dotted)
and on the tops (the lit step); the face takes the middle step. One toon material.
"""
import math
from mathutils import Vector

PWR_REVISION = 'power_v13'
# Clockwise outline in the face plane (u along world X, v up), flats along u.
# Placed so that on screen the notch's inner corner sits about a third of the way down and the
# step on the left just past half, as in the shipped art (points further along X draw lower).
# OWNER (v10 -> v11): "now rotate it so it has the same layout as the AI one". The whole bolt
# turns 90 degrees about world Z, staying on the grid: the face is the world YZ plane (facing
# +X), the flats run along world +Y (they draw rising to the right, as in the shipped art) and
# the depth runs back along -X, so the thickness shows on the LEFT and the top face opens up-left,
# the shipped layout. The outline is solved from the shipped art's vertex positions for this
# orientation, each flat pair levelled.
BOLT_UV = [(0.446, 2.594), (1.361, 2.594),     # top edge
           (1.013, 1.685), (1.638, 1.685),     # upper bar's right edge down to the notch, notch step out right
           (0.450, 0.020),                     # lower bar's right edge down to the tip
           (0.713, 1.338), (0.000, 1.338)]     # lower bar's left edge up to the step, step out left
PSI = math.radians(90)            # on the grid: flats along world +Y, face = world YZ plane facing +X
DEPTH = 0.35
H_AX = Vector((round(math.cos(PSI), 12), round(math.sin(PSI), 12), 0.0))       # the face plane's horizontal (world +Y)
N_FACE = Vector((round(math.sin(PSI), 12), round(-math.cos(PSI), 12), 0.0))    # the face normal (world +X, toward the camera side)


def bolt_outline():
    return list(BOLT_UV)


def pw_toon_rgb(name, steps):
    """Toon emission whose flat steps carry their own colour: steps = ((threshold, (r, g, b)), ...)
    in linear light, the last threshold above the shading range. Same shading factor as toon_mat."""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial'); emis = nt.nodes.new('ShaderNodeEmission')
    diff = nt.nodes.new('ShaderNodeBsdfDiffuse'); diff.inputs['Color'].default_value = (1, 1, 1, 1)
    s2r = nt.nodes.new('ShaderNodeShaderToRGB'); ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.interpolation = 'CONSTANT'
    els = ramp.color_ramp.elements
    els[0].position = 0.0; els[0].color = (*steps[0][1], 1)
    els[1].position = steps[0][0]; els[1].color = (*steps[1][1], 1)
    for i in range(2, len(steps)):
        e = els.new(steps[i - 1][0]); e.color = (*steps[i][1], 1)
    nt.links.new(diff.outputs[0], s2r.inputs[0]); nt.links.new(s2r.outputs['Color'], ramp.inputs['Fac'])
    nt.links.new(ramp.outputs['Color'], emis.inputs['Color'])
    emis.inputs['Strength'].default_value = 1.0; nt.links.new(emis.outputs[0], out.inputs[0])
    return m


def build_power():
    """Power v8: the shipped bolt's pose, drawn on the isometric grid, lit by the set's light."""
    setup_icon_rig(); K = Kit(open_collection('ICON_power'))
    # The set's light, this layout: tops s 1.00 (pale), the left thickness faces -Y s ~0.95 (it
    # faces the light: light gold), the face turns toward the shade side, +X, s 0.61 (deeper gold).
    # The shipped art had it the other way round (dark left side, bright face).
    gold = pw_toon_rgb('pwr_bolt', ((0.80, (0.791, 0.366, 0.016)),     # face: deeper gold (230,164,34)
                                    (0.975, (0.871, 0.491, 0.051)),    # left side: light gold (240,186,64), 20+ luma under the top
                                    (9.0, (0.955, 0.658, 0.188))))     # tops: pale gold (250,212,120)
    BOLT = bolt_outline(); n = len(BOLT)
    Z = Vector((0, 0, 1)); back = -N_FACE * DEPTH
    P = [H_AX * a + Z * b for a, b in BOLT]
    vs = [tuple(p) for p in P] + [tuple(p + back) for p in P]
    fs = [tuple(range(n)), tuple(n + k for k in range(n))]
    fs += [(k, (k + 1) % n, n + (k + 1) % n, n + k) for k in range(n)]
    bolt = mesh(K, 'bolt', vs, fs, gold, False)          # flat: every face one tone step
    bolt['part_label'] = 1
    # Ink: the face outline, the back outline and the depth edges, offset a hair outward so
    # the visibility test sees them; hidden stretches drop out.
    e = 0.004
    def outward(k):                                      # in-plane bisector of the outward edge normals
        a = Vector(BOLT[k - 1]); b = Vector(BOLT[k]); c = Vector(BOLT[(k + 1) % n])
        n1 = Vector((-(b - a).y, (b - a).x)).normalized(); n2 = Vector((-(c - b).y, (c - b).x)).normalized()   # clockwise outline: outward = (-dv, du)
        o = (n1 + n2).normalized(); return H_AX * o.x + Z * o.y
    ring = [P[k] + outward(k) * e for k in range(n)]
    tagged_line(K, 'face_edge', [tuple(p + N_FACE * e) for p in ring], 1, 6, True)
    tagged_line(K, 'back_edge', [tuple(p + back - N_FACE * e) for p in ring], 1, 6, True)
    for k, p in enumerate(ring):
        tagged_line(K, 'depth_edge_%d' % k, [tuple(p + N_FACE * e + (back - N_FACE * 2 * e) * (j / 20)) for j in range(21)], 1, 6, False)
    info = contract(K, [bolt.name], 'extruded lightning bolt facing -Y, thickness on the right and top')
    info['revision'] = PWR_REVISION
    info['stipple']['strength'] = 0.38
    # OWNER (v12 -> v13): "now we'll want stippling on the shaded sides". The face (+X, mask 0.53)
    # is this layout's shade side: it takes the kit's 2x lattice, the density the approved icons'
    # shadow faces carry (~9-10 px spacing at 800); the lit tops and left side stay clean.
    info['stipple']['groups'][0]['thresholds'] = [0.65, 0.60, 0.35]
    info['dimensions'] = {'depth': DEPTH, 'psi_degrees': math.degrees(PSI), 'outline': BOLT, 'outline_source': 'drawn on the grid after the shipped pose'}
    return info
