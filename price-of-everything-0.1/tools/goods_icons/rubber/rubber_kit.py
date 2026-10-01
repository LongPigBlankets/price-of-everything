"""Rubber (g_028): a stack of folded rubber sheets with tan stitching, a pair of wellingtons and a rubber
duck, on the isometric grid.

Reference: assets/icons/goods/medium/g_028_rubber.png (shipped AI art): a squat stack of dark rubber
sheets, thin flat sheets alternating with thicker sheets folded into flat tubes whose rounded ends bulge
at the stack's corners, tan dashed stitching along the top sheet's two front edges and along the folded
layers' sides; two black wellington boots standing side by side in front of the stack's right (+X) face,
toes to the lower right, each with a rolled rim, a dark inside, an ankle crease, a sloped toe and a thick
treaded sole; a yellow rubber duck at the front, facing screen right (its right side, eye and wing toward
the viewer), with an orange beak.
OWNER 2026-09-29: "Then rubber. Both are difficult icons but keep looping with the reviewer until its
done". Owner rulings carried over: the shipped layout on the grid, the set's light, dots on shaded
sides, ink at every junction, one colour per material (the sheets and boots one black rubber), 3 px for
small detail (stitch-free creases, tread ticks, the beak's mouth line), soft goods plump, reuse approved
parts where they exist (none here).
Units: the stack is 1.00 (X) x 1.41 (Y) x ~0.66 (measured off the shipped art); the boots ~1.02 tall; the
duck ~0.5 tall.
"""
import math, bmesh
from mathutils import Vector, Matrix

RB_REVISION = 'rubber_v15'
SMALL_INK = 3
# v4: fitted to the shipped stack's inked silhouette (fit/stack_fit.py, IoU 0.980; X fixes the scale)
STACK_X, STACK_Y = 1.00, 1.4342
# layers from the bottom: (kind, thickness, x inset at the low end, x inset at the high end, y insets)
# v5: the sequence and thicknesses measured on the shipped stack's -Y face (layer lines at the same heights
# in three columns): five sheets, a big fold, a sheet, a big fold, three sheets, a stitched fold, the top
LAYERS = [('thin', 0.0405, 0.020, 0.000, 0.01, 0.00),
          ('thin', 0.0217, 0.000, 0.020, 0.00, 0.02),
          ('thin', 0.0339, 0.010, 0.010, 0.02, 0.00),
          ('thin', 0.0320, 0.000, 0.010, 0.01, 0.01),
          ('thin', 0.0396, 0.010, 0.000, 0.00, 0.00),
          ('fold', 0.1413, -0.060, -0.050, 0.00, 0.01),
          ('thin', 0.0490, 0.000, 0.000, 0.00, 0.01),
          ('fold', 0.1507, -0.070, -0.030, 0.01, 0.00),
          ('thin', 0.0377, 0.010, 0.010, 0.01, 0.00),
          ('thin', 0.0199, 0.000, 0.010, 0.00, 0.01),       # v14: 0.015 moved to the sheet above, so the shipped
          ('thin', 0.0480, 0.010, 0.000, 0.01, 0.00),       # short row there sits on its own band (review v13)
          ('fold', 0.0791, -0.030, -0.030, 0.00, 0.01),
          ('top', 0.0367, 0.000, 0.000, 0.00, 0.00)]
GAP = 0.004
# v8: fitted part by part to the shipped boots (fit/boot_fit2.py: the opening, the rim's top ring, the cuff
# band, the shaft, the foot's panel, the midsole and the outsole of each, read off the ink; mean IoU 0.785):
# shaft centres, and the shape shared by the pair (source/boot_geom.py). The pair turns 9 degrees toward +Y
# as shipped (round goods: not a flat face off the grid).
BOOTS = [(1.2926, 0.4007), (1.2851, 0.702)]
BOOT_GEOM = {'top_z': 0.8382, 'band_h': 0.0402, 'band_out': 0.006, 'ring_w': 0.0324, 'A_t': 0.1863, 'B_t': 0.1167, 'A_a': 0.1577,
             'B_a': 0.109, 'p_sh': 2.0, 'z_ank': 0.2893, 'L_toe': 0.425, 'heel': 0.0799, 'W_foot': 0.1122, 'wk': 0.3253, 'm': 1.0313,
             'n': 0.3266, 'p_ft': 2.8817, 'seam_mid': 0.2876, 'seam_amp': 0.105, 'seam_fb': 0.0269, 'h_out': 0.0531, 'h_mid': 0.0593,
             'welt': 0.0083, 'out_in': 0.004, 'arch0': 0.0, 'arch1': 0.0, 'yaw': 9.0477,
             # v10: the seam as shipped (back-projected off the ink: both boots agree): level across the
             # instep, a steep drop 37 degrees round from the toe, level along the side
             'seam_hi': 0.415, 'seam_lo': 0.247, 'seam_tc': 37.5, 'seam_w': 15.0,
             # v11: a rounded shoulder over a near-vertical riser (review v10)
             'seam_sh': 18.0, 'seam_hs': 0.045, 'seam_rw': 2.5, 'seam_bw': 3.0, 'seam_hb': 0.008,   # v12: a steeper riser, a tight foot
             'sole_bulge': 0.018, 'sole_tuck': 0.012}       # v13: a rounded sole (the shipped toe bulges past a flat wall)
LUG = (0.11, 0.022, 0.014)       # the outsole's tread: notch spacing along its edge, notch half-width, depth
# v9: fitted to the shipped duck (fit/duck_fit2.py: inked silhouette 0.937, the bill's region 0.727, the neck line
# 1.7 px off the head's edge; the head pinned to the shipped head's circle), in source/duck_geom.py's terms.
# v11 (review v10): the tail raised and the back dipping to the neck (fit/duck_back_fit.py, the top edge 3 px
# off the shipped), the bill longer, flatter and set back with an upturned tip, the chest raised under the chin.
# v12 (review v11): one smooth tail peak (fit/duck_back_fit2.py: the dip behind the head), the bill tapering to a
# point and 11 px longer, its lower lip flat, the chest a little higher.
# v13 (review v12): no dip (it dented the shading); the tail's crest at the shipped peak (fit/duck_tail_fit.py
# on the true 800 px silhouette: the ink-widened fit had hidden the notch), the back falling level to the neck
DUCK_GEOM = {'x': 1.2274, 'y': 0.026, 'yaw': 0.0454, 's': 0.9065, 'rxf': 0.3336, 'rxb': 0.23, 'ry': 0.2095, 'rz': 0.105, 'tail': 0.31, 'tp': 2.5, 'tw': 0.4, 'fb': 0.6987, 'hx': 0.1656, 'hz': 0.4436, 'hr': 0.1432, 'hsz': 1.0, 'hsx': 1.0, 'kd': 1.035, 'kzr': -0.258, 'krx': 0.137, 'kry': 0.0727, 'krz': 0.0402, 'kup': 0.015, 'kw': 0.0176, 'kp': 15.7126, 'dip': 0.0, 'dip_x': -0.0421, 'dip_w': 0.1205, 'chest': 0.03, 'chest_x': 0.2, 'chest_w': 0.08, 'ktaper': 0.72, 'klow_pitch': 1.0, 'klow_len': 0.95, 'klow_h': 0.55, 'tx0': -0.03}
# the shipped duck's strokes in the duck's frame (fit/duck_backproject.py): eye outlines, neck, mouth, wing, feathers
DUCK_STROKES = {'wing': {'part': 'body', 'closed': True, 'pts': [[-0.121, -0.1069, 0.1782], [-0.1138, -0.1042, 0.1762], [-0.1093, -0.1034, 0.1746], [-0.1048, -0.1024, 0.1732], [-0.1003, -0.1012, 0.172], [-0.0959, -0.0997, 0.1709], [-0.0898, -0.0965, 0.1701], [-0.0841, -0.0983, 0.1679], [-0.0783, -0.097, 0.167], [-0.0726, -0.0982, 0.1657], [-0.0657, -0.0971, 0.1651], [-0.0588, -0.0983, 0.1643], [-0.0534, -0.0984, 0.1641], [-0.0466, -0.0987, 0.1641], [-0.0391, -0.0964, 0.165], [-0.032, -0.0985, 0.1649], [-0.0243, -0.0979, 0.1656], [-0.0182, -0.0965, 0.1662], [-0.0123, -0.0948, 0.1668], [-0.0041, -0.0954, 0.1669], [-0.0, -0.093, 0.1675], [0.0057, -0.0905, 0.1681], [0.0132, -0.0902, 0.1682], [0.0183, -0.0873, 0.1688], [0.0237, -0.0868, 0.1689], [0.0301, -0.0834, 0.1695], [0.0353, -0.0826, 0.1696], [0.0421, -0.0814, 0.1698], [0.0485, -0.0826, 0.1694], [0.0537, -0.0814, 0.1696], [0.0604, -0.0822, 0.1694], [0.0673, -0.0829, 0.1692], [0.0743, -0.0833, 0.1692], [0.0817, -0.0862, 0.1686], [0.0893, -0.0889, 0.1682], [0.0972, -0.0914, 0.1679], [0.1052, -0.0935, 0.1678], [0.1115, -0.0964, 0.1674], [0.1177, -0.099, 0.1671], [0.1262, -0.1033, 0.1664], [0.1325, -0.1056, 0.1661], [0.1387, -0.1105, 0.1647], [0.147, -0.114, 0.1636], [0.1528, -0.1185, 0.1616], [0.1565, -0.1214, 0.1601], [0.1619, -0.1256, 0.1576], [0.1671, -0.1295, 0.1548], [0.1703, -0.1321, 0.1527], [0.175, -0.1357, 0.1493], [0.1766, -0.1406, 0.1452], [0.1806, -0.1439, 0.1413], [0.1832, -0.1459, 0.1385], [0.1837, -0.1504, 0.134], [0.1827, -0.1537, 0.1308], [0.1858, -0.1562, 0.1262], [0.1843, -0.1593, 0.1228], [0.1826, -0.1623, 0.1194], [0.1773, -0.1666, 0.1156], [0.1745, -0.1687, 0.1137], [0.1716, -0.1708, 0.1118], [0.165, -0.1742, 0.1095], [0.1619, -0.1761, 0.1075], [0.1545, -0.1787, 0.1067], [0.1508, -0.1799, 0.1062], [0.1432, -0.1824, 0.1053], [0.1389, -0.1829, 0.1064], [0.1313, -0.1851, 0.1055], [0.1269, -0.1855, 0.1065], [0.1192, -0.1876, 0.1056], [0.1148, -0.1878, 0.1066], [0.1069, -0.1897, 0.1058], [0.1026, -0.1898, 0.1068], [0.0946, -0.1914, 0.1062], [0.0866, -0.1929, 0.1057], [0.0823, -0.1928, 0.1068], [0.0742, -0.1941, 0.1064], [0.0701, -0.1947, 0.1062], [0.0617, -0.1949, 0.1073], [0.0574, -0.1945, 0.1085], [0.0493, -0.1954, 0.1083], [0.0413, -0.197, 0.1069], [0.037, -0.1965, 0.1081], [0.0288, -0.197, 0.108], [0.0246, -0.1963, 0.1093], [0.0164, -0.1966, 0.1093], [0.0122, -0.1948, 0.1119], [0.0041, -0.195, 0.1118], [-0.0028, -0.1939, 0.1131], [-0.0083, -0.1927, 0.1144], [-0.0137, -0.1903, 0.1169], [-0.0189, -0.1875, 0.1194], [-0.0241, -0.1858, 0.1206], [-0.0291, -0.1827, 0.1231], [-0.0364, -0.1788, 0.1255], [-0.0412, -0.1765, 0.1268], [-0.0455, -0.1726, 0.1294], [-0.0525, -0.1693, 0.1312], [-0.0564, -0.1649, 0.134], [-0.0605, -0.1619, 0.1358], [-0.0669, -0.1578, 0.1383], [-0.07, -0.1529, 0.1414], [-0.0737, -0.1494, 0.1436], [-0.0793, -0.1447, 0.1467], [-0.0826, -0.1409, 0.1492], [-0.0867, -0.1386, 0.151], [-0.0917, -0.1334, 0.1547], [-0.0945, -0.1294, 0.1575], [-0.0971, -0.1253, 0.1602], [-0.1026, -0.1212, 0.1638], [-0.1061, -0.1183, 0.1665], [-0.1096, -0.1153, 0.1692], [-0.113, -0.1122, 0.1721], [-0.1147, -0.1106, 0.1735]]}, 'feather': {'part': 'body', 'closed': False, 'pts': [[-0.0402, -0.1723, 0.1303], [-0.0325, -0.1721, 0.1313], [-0.0273, -0.1713, 0.1325], [-0.0199, -0.1722, 0.1325], [-0.0148, -0.171, 0.1336], [-0.0073, -0.1698, 0.1348], [-0.0024, -0.17, 0.1348], [0.0035, -0.1683, 0.1359]]}, 'feather2': {'part': 'body', 'closed': False, 'pts': [[0.0284, -0.1941, 0.1119], [0.0319, -0.1908, 0.1158], [0.0357, -0.1893, 0.1171], [0.0389, -0.1855, 0.1209], [0.0422, -0.1827, 0.1234], [0.045, -0.1783, 0.1271], [0.0479, -0.1751, 0.1295], [0.0511, -0.1732, 0.1308], [0.0538, -0.1698, 0.1332], [0.0523, -0.1651, 0.1366]]}, 'eye_near': {'part': 'head', 'closed': True, 'pts': [[0.2707, -0.0851, 0.4907], [0.268, -0.0874, 0.4925], [0.2644, -0.0914, 0.4925], [0.2611, -0.093, 0.496], [0.2593, -0.0937, 0.4978], [0.2553, -0.0945, 0.5029], [0.253, -0.0945, 0.5063], [0.25, -0.0938, 0.5114], [0.2482, -0.0917, 0.5163], [0.2462, -0.0895, 0.5211], [0.2459, -0.0869, 0.5242], [0.2467, -0.0832, 0.5273], [0.2462, -0.0806, 0.5303], [0.2474, -0.0776, 0.5318], [0.2504, -0.0744, 0.5318], [0.2523, -0.0721, 0.5318], [0.256, -0.0694, 0.5303], [0.2587, -0.0676, 0.5288], [0.2622, -0.0664, 0.5258], [0.2657, -0.065, 0.5227], [0.2691, -0.0653, 0.5179], [0.2707, -0.0663, 0.5147], [0.273, -0.0678, 0.5097], [0.2742, -0.0706, 0.5046], [0.2746, -0.0728, 0.5012], [0.2748, -0.0751, 0.4978], [0.274, -0.0787, 0.4942], [0.2724, -0.0819, 0.4925]]}, 'eye_far': {'part': 'head', 'closed': True, 'pts': [[0.2941, 0.0326, 0.4978], [0.2935, 0.0289, 0.5012], [0.2934, 0.0254, 0.5029], [0.2925, 0.0218, 0.5063], [0.2902, 0.0197, 0.5114], [0.2886, 0.0178, 0.5147], [0.2855, 0.019, 0.5195], [0.2835, 0.0187, 0.5227], [0.2809, 0.0214, 0.5258], [0.2782, 0.0239, 0.5288], [0.2749, 0.0278, 0.5318], [0.2737, 0.032, 0.5318], [0.2713, 0.0359, 0.5333], [0.2704, 0.0418, 0.5318], [0.2697, 0.0463, 0.5303], [0.2695, 0.0495, 0.5288], [0.2701, 0.0532, 0.5258], [0.2705, 0.057, 0.5227], [0.2724, 0.0598, 0.5179], [0.2749, 0.0593, 0.5147], [0.2772, 0.0606, 0.5097], [0.2795, 0.0599, 0.5063], [0.2825, 0.0576, 0.5029], [0.2847, 0.0549, 0.5012], [0.2881, 0.0507, 0.4978], [0.29, 0.0459, 0.4978], [0.2918, 0.0428, 0.496], [0.2927, 0.0377, 0.4978]]}, 'mouth': {'part': 'bill', 'closed': False, 'pts': [[0.2914, -0.0672, 0.4246], [0.3001, -0.0694, 0.4297], [0.3064, -0.0702, 0.4325], [0.313, -0.0706, 0.4349], [0.318, -0.0705, 0.4364], [0.3247, -0.0701, 0.4378], [0.3297, -0.0698, 0.4394], [0.3346, -0.0694, 0.4409], [0.341, -0.0689, 0.4436], [0.3458, -0.0682, 0.4452], [0.352, -0.0674, 0.448], [0.3567, -0.0667, 0.4502], [0.3628, -0.0655, 0.453], [0.3673, -0.0645, 0.4553], [0.3716, -0.0635, 0.4581], [0.3773, -0.0612, 0.4587], [0.3815, -0.0599, 0.461], [0.3855, -0.0583, 0.4627], [0.3894, -0.0567, 0.4643], [0.3931, -0.0547, 0.4654], [0.3977, -0.052, 0.4663], [0.4012, -0.05, 0.4678], [0.4042, -0.0476, 0.4681], [0.4081, -0.0447, 0.4693], [0.4106, -0.0422, 0.4694], [0.4136, -0.0389, 0.4698], [0.4159, -0.0353, 0.4692], [0.4184, -0.0308, 0.4688], [0.4196, -0.0262, 0.4673], [0.4198, -0.0206, 0.4648], [0.4174, -0.0117, 0.4598], [0.4235, -0.0142, 0.4672], [0.4274, -0.014, 0.4722]]}, 'neck': {'part': 'head', 'closed': False, 'pts': [[0.1145, -0.1332, 0.4314], [0.1112, -0.1313, 0.4258], [0.1117, -0.1302, 0.4183], [0.1173, -0.1308, 0.4109], [0.1247, -0.1318, 0.4055], [0.1301, -0.1323, 0.4019], [0.1343, -0.1302, 0.393], [0.1368, -0.1271, 0.3843], [0.1471, -0.1274, 0.3809], [0.151, -0.1235, 0.3725], [0.1608, -0.1233, 0.3709], [0.1721, -0.1232, 0.3709], [0.1718, -0.1182, 0.363]]}}
DASH = (0.045, 0.030, 0.012)                     # stitch dash: length, gap, width

VIEW = Vector((1.0, -1.0, 1.0)).normalized()
RIGHT = Vector((1.0, 1.0, 0.0)).normalized()
UP = VIEW.cross(RIGHT).normalized()


def rb_rgb(*c8):
    return tuple((v / 255) / 12.92 if v / 255 <= 0.04045 else ((v / 255 + 0.055) / 1.055) ** 2.4 for v in c8)


RB_SHADE_STEP = 0.65      # v7: the shade colour and the dots cover the same pixels (see plastics v11: the dot mask is
                          # 0.5 + 0.5 N.L, the toon steps on the diffuse factor; factor 0.65 <-> mask 0.575)


def rb_toon(name, shade, mid, lit):
    return pw_toon_rgb(name, ((RB_SHADE_STEP, rb_rgb(*shade)), (0.975, rb_rgb(*mid)), (9.0, rb_rgb(*lit))))


def rb_prism(K, name, outline, y0, y1, mat, label, e=None):
    """An (x, z) outline extruded along Y from y0 to y1, as a closed solid; with its two outlines and its
    sharp long edges as 6 px ink paths."""
    n = len(outline)
    vs = [(x, y0, z) for x, z in outline] + [(x, y1, z) for x, z in outline]
    fs = [tuple(range(n)), tuple(n + k for k in range(n))] + [(k, (k + 1) % n, n + (k + 1) % n, n + k) for k in range(n)]
    ob = mesh(K, name, vs, fs, mat, False); ob['part_label'] = label
    outs = alk_outward(outline); ring = [(x + o.x * E, z + o.y * E) for (x, z), o in zip(outline, outs)]
    tagged_line(K, name + '_front', [(x, y0 - E, z) for x, z in ring], label, 6, True)['ink_width'] = 0
    tagged_line(K, name + '_back', [(x, y1 + E, z) for x, z in ring], label, 6, True)['ink_width'] = 0
    for k in range(n):
        a, b, c = Vector(outline[k - 1]), Vector(outline[k]), Vector(outline[(k + 1) % n])
        if (b - a).angle(c - b, 0.0) > math.radians(35):
            x, z = ring[k]
            tagged_line(K, '%s_long%d' % (name, k), [(x, y0 - E, z), (x, y1 + E, z)], label, 6, False)
    for p in ob.data.polygons:
        p.use_smooth = False
    return ob


def rb_dashes(K, name, a, b, n_out, mat, label):
    """Tan stitch dashes along the segment a -> b, flat strips lying on the surface whose outward normal
    is n_out (lifted a hair off it)."""
    a, b, n = Vector(a), Vector(b), Vector(n_out).normalized()
    d = (b - a); L = d.length; d.normalize(); w = n.cross(d).normalized()
    dl, dg, dw = DASH; k = 0; s = dg / 2; vs = []; fs = []
    while s + dl <= L:
        p0 = a + d * s + n * 0.002; p1 = a + d * (s + dl) + n * 0.002; base = len(vs)
        vs += [tuple(p0 - w * dw / 2), tuple(p1 - w * dw / 2), tuple(p1 + w * dw / 2), tuple(p0 + w * dw / 2)]
        vs += [tuple(Vector(q) - n * 0.003) for q in vs[base:base + 4]]
        fs += [(base, base + 1, base + 2, base + 3), (base + 7, base + 6, base + 5, base + 4), (base, base + 4, base + 5, base + 1),
               (base + 1, base + 5, base + 6, base + 2), (base + 2, base + 6, base + 7, base + 3), (base + 3, base + 7, base + 4, base)]
        s += dl + dg; k += 1
    if not vs:
        return None
    ob = mesh(K, name, vs, fs, mat, False); ob['part_label'] = label; ob.pass_index = 73; pw_clean_water(ob)
    return ob


DASH2 = (0.039, 0.026, 0.009)      # v11: the shipped pitch (21 px at 800, v10's was 24); v12: 2.7 px thick as shipped
DASH_ARC = (0.022, 0.012, 0.009)   # v13: short dashes round the folds' ends (the shipped arcs carry three)


def rb_stitch(K, name, pts, nrm, mat, label, dash=DASH2, phase=None):
    """v11: tan stitch dashes along a 3D polyline pts (lying on a surface whose outward normal at each point is
    nrm[i]), each dash a thin flat strip following the path, lifted a hair off the surface."""
    P = [Vector(p) for p in pts]; N = [Vector(n).normalized() for n in nrm]
    seg = [(P[i + 1] - P[i]).length for i in range(len(P) - 1)]; L = sum(seg)
    dl, dg, dw = dash
    def at(s):
        s = max(0.0, min(L, s)); i = 0
        while i < len(seg) - 1 and s > seg[i]:
            s -= seg[i]; i += 1
        f = s / max(seg[i], 1e-9); return P[i].lerp(P[i + 1], f), N[i].lerp(N[i + 1], f).normalized(), (P[i + 1] - P[i]).normalized()
    s = dg / 2 if phase is None else phase; vs = []; fs = []
    while s + dl <= L + 1e-9:
        pts_ = []
        for q in range(4):                          # a dash as a 4-segment strip, so it bends with the path
            p, n, t = at(s + dl * q / 3); w = n.cross(t).normalized(); pts_.append((p + n * 0.002, n, w))
        base = len(vs)
        for p, n, w in pts_:
            vs += [tuple(p - w * dw / 2), tuple(p + w * dw / 2)]
        for p, n, w in pts_:
            vs += [tuple(p - w * dw / 2 - n * 0.003), tuple(p + w * dw / 2 - n * 0.003)]
        for q in range(3):
            a, b = base + 2 * q, base + 2 * q + 2; c, d = a + 8, b + 8
            fs += [(a, b, b + 1, a + 1), (c + 1, d + 1, d, c), (a, c, d, b), (a + 1, b + 1, d + 1, c + 1)]
        fs += [(base, base + 1, base + 9, base + 8), (base + 6, base + 14, base + 15, base + 7)]
        s += dl + dg
    if not vs:
        return None
    ob = mesh(K, name, vs, fs, mat, False); ob['part_label'] = label; ob.pass_index = 73; pw_clean_water(ob)
    return ob


def rb_fold_frame(x0, x1, y0, y1, z0, t):
    """A fold's rounded ends: centre x of each, the axis height, the radius."""
    r = t / 2
    return x0 + r, x1 - r, z0 + r, r


def rb_on_end(xc, zc, r, y, th, sgn=1, lift=0.0):
    """A point on a fold's rounded end (sgn +1: the +X end) at angle th (0 at its outermost line, +90 at its
    top), and its outward normal."""
    c, s_ = math.cos(th), math.sin(th)
    return (xc + sgn * (r + lift) * c, y, zc + (r + lift) * s_), (sgn * c, 0.0, s_)


def rb_fold_stitching(K, i, x0, x1, y0, y1, z0, t, mat, label):
    """v11: each fold's stitching as the shipped art draws it (its dashes back-projected, review v10):
    the fold under the top sheet: one row along its -Y face that wraps round the front corner and runs
    along its +X end; the big middle fold: a hairpin along its +X end (two rows, a U just short of the far end)
    joined by U-loops on its -Y face at both ends; the bottom fold: a row along its -Y face turning up
    round its -X end, and a row along its +X end."""
    xa, xb, zc, r = rb_fold_frame(x0, x1, y0, y1, z0, t); cap = (0, -1, 0)
    def cap_arc(xc, a0, a1, rho, n=10):
        return [(xc + rho * math.cos(math.radians(a0 + (a1 - a0) * q / n)), y0 - 0.001, zc + rho * math.sin(math.radians(a0 + (a1 - a0) * q / n))) for q in range(n + 1)]
    if t < 0.1 and z0 > 0.6:                          # the fold under the top sheet
        th = math.radians(27); zr = zc + r * math.sin(th)
        xe = xb + r * math.cos(th)
        path = [(xa + 0.06, y0 - 0.001, zr), (xe - 0.004, y0 - 0.001, zr)]
        path = [(xa + 0.06, y0 - 0.001, zr), (xe - 0.004, y0 - 0.001, zr)]
        rb_stitch(K, 'layer%d_stitch_y' % i, path, [cap] * 2, mat, label)
        pts = []; nrm = []
        for y in (y0 + 0.004, y1 - 0.03):
            p, n = rb_on_end(xb, zc, r, y, th); pts.append(p); nrm.append(n)
        rb_stitch(K, 'layer%d_stitch_x' % i, pts, nrm, mat, label, phase=0.004)
    elif t > 0.12 and z0 > 0.3:                       # the big middle fold: a hairpin on its +X end
        tu, tl = math.radians(50), math.radians(0); yt = y1 - 0.09; pts = []; nrm = []     # v12: the return row clear of the contour
        for y in [y0 + 0.004 + (yt - y0 - 0.004) * q / 6 for q in range(7)]:
            p, n = rb_on_end(xb, zc, r, y, tu); pts.append(p); nrm.append(n)
        for q in range(1, 12):                        # the U-turn on the rounded end, short of the far end
            a = math.pi * q / 12; th = (tu + tl) / 2 + (tu - tl) / 2 * math.cos(a); y = yt + 0.05 * math.sin(a)
            p, n = rb_on_end(xb, zc, r, y, th); pts.append(p); nrm.append(n)
        for y in [yt - (yt - y0 - 0.004) * q / 6 for q in range(7)]:
            p, n = rb_on_end(xb, zc, r, y, tl); pts.append(p); nrm.append(n)
        rb_stitch(K, 'layer%d_stitch_x' % i, pts, nrm, mat, label)
        rho = r * 0.72
        u = cap_arc(xb, 50, 0, rho); rb_stitch(K, 'layer%d_stitch_uf' % i, u, [cap] * len(u), mat, label, dash=DASH_ARC, phase=0.004)
        u = cap_arc(xa, 110, 250, r * 0.55); rb_stitch(K, 'layer%d_stitch_ul' % i, u, [cap] * len(u), mat, label, dash=DASH_ARC, phase=0.003)   # v13: three dashes ~10 px in
    elif t > 0.12:                                    # the bottom fold
        rho = r * 0.72; zr = zc - rho * math.sin(math.radians(26.5))
        u = [(xa + 0.02, y0 - 0.001, zr), (xb, y0 - 0.001, zr)]
        rb_stitch(K, 'layer%d_stitch_y' % i, u, [cap] * len(u), mat, label)
        u = cap_arc(xa, 110, 250, r * 0.55); rb_stitch(K, 'layer%d_stitch_ul' % i, u, [cap] * len(u), mat, label, dash=DASH_ARC, phase=0.003)   # v14: three short dashes (review v13)
        pts = []; nrm = []
        for y in (y0 + 0.004, y1 - 0.05):
            p, n = rb_on_end(xb, zc, r, y, math.radians(0)); pts.append(p); nrm.append(n)       # v12: clear of the contour
        rb_stitch(K, 'layer%d_stitch_x' % i, pts, nrm, mat, label, phase=0.004)


def rb_stack(K, rub_m, stitch_m, label_sheets, label_folds):
    hosts = []; z = 0.0
    for i, (kind, t, xi0, xi1, yi0, yi1) in enumerate(LAYERS):
        x0, x1, y0, y1 = xi0, STACK_X - xi1, yi0, STACK_Y - yi1
        z0, z1 = z, z + t
        if kind == 'fold':
            r = t / 2; outline = []
            for k in range(13):                           # the -X end: a half circle
                a = math.radians(90 + 180 * k / 12); outline.append((x0 + r + r * math.cos(a), z0 + r + r * math.sin(a)))
            for k in range(13):                           # the +X end
                a = math.radians(-90 + 180 * k / 12); outline.append((x1 - r + r * math.cos(a), z0 + r + r * math.sin(a)))
            ob = rb_prism(K, 'layer%d' % i, outline, y0, y1, rub_m, label_folds)
            # the fold's inner line (the sheet folded back on itself), 3 px, on the -Y end face
            tagged_line(K, 'layer%d_fold' % i, [(x0 + r * 0.9, y0 - E, z0 + r), (x1 - r * 0.9, y0 - E, z0 + r)], label_folds, SMALL_INK, False)
            rb_fold_stitching(K, i, x0, x1, y0, y1, z0, t, stitch_m, label_folds)
        else:
            outline = [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]
            ob = rb_prism(K, 'layer%d' % i, outline, y0, y1, rub_m, label_sheets)
            if i == 10:                               # v14: the shipped short row by the front corner, on this sheet's own band
                zm = (z0 + z1) / 2
                rb_stitch(K, 'layer10_stitch_y', [(0.70, y0 - 0.001, zm), (0.955, y0 - 0.001, zm)], [(0, -1, 0)] * 2, stitch_m, label_sheets)
            if kind == 'top':
                # v11: as shipped (back-projected): 0.061 in from the -Y edge, 0.032 from the +X edge, round the front
                # corner, from near the -X end to near the far end
                iy, ix, rc = 0.061, 0.032, 0.05; path = [(x0 + 0.042, y0 + iy, z1)]
                cxr, cyr = x1 - ix - rc, y0 + iy + rc
                for q in range(9):
                    a = math.radians(-90 + 90 * q / 8); path.append((cxr + rc * math.cos(a), cyr + rc * math.sin(a), z1))
                path.append((x1 - ix, y1 - 0.012, z1))
                rb_stitch(K, 'top_stitch', path, [(0, 0, 1)] * len(path), stitch_m, label_sheets)
        hosts.append(ob.name)
        z = z1 + GAP
    return hosts, z


def rb_front_runs(pts2, min_dot=0.05):
    """Index runs of a closed CCW loop (world x, y) whose outward normal faces the camera: its visible arcs,
    each widened by a sample at both ends to reach the silhouette."""
    n = len(pts2); vis = []
    for k in range(n):
        a = pts2[k - 1]; b = pts2[(k + 1) % n]
        tx, ty = b[0] - a[0], b[1] - a[1]; L = math.hypot(tx, ty) or 1.0
        vis.append((ty / L + tx / L) / math.sqrt(2) > min_dot)      # outward (ty, -tx) . (1, -1)/sqrt2
    k0 = next((k for k in range(n) if not vis[k]), None)
    if k0 is None:
        return [list(range(n)) + [0]]
    runs = []; cur = []
    for i in range(1, n + 1):
        k = (k0 + i) % n
        if vis[k]:
            cur.append(k)
        elif cur:
            runs.append(cur); cur = []
    if cur:
        runs.append(cur)
    return [[(r[0] - 1) % n] + r + [(r[-1] + 1) % n] for r in runs]


def rb_arc_lines(K, name, pts3, label, width=6):
    """Ink the visible arcs of a closed loop of world points."""
    for i, r in enumerate(rb_front_runs([(p[0], p[1]) for p in pts3])):
        ln = tagged_line(K, '%s_%d' % (name, i), [tuple(map(float, pts3[k])) for k in r], label, width, False)
        if width == 6:
            ln['ink_width'] = 0


def rb_ring_solid(K, name, loop_rows, mat, label):
    """A closed solid from rows of equal-length CCW loops (bottom to top), capped at both ends."""
    n = len(loop_rows[0]); vs = [tuple(map(float, p)) for row in loop_rows for p in row]; fs = []
    for j in range(len(loop_rows) - 1):
        fs += [(j * n + k, j * n + (k + 1) % n, (j + 1) * n + (k + 1) % n, (j + 1) * n + k) for k in range(n)]
    fs.append(tuple(reversed(range(n)))); fs.append(tuple((len(loop_rows) - 1) * n + k for k in range(n)))
    ob = mesh(K, name, vs, fs, mat, False); ob['part_label'] = label
    return ob


def rb_boot(K, name, cx, cy, rub_m, dark_m, label, rim_label, inner=0):
    """v8: a wellington built from source/boot_geom.py, fitted part by part to the shipped boots (the opening,
    the rim's top ring, the cuff band, the shaft, the foot's panel, the midsole, the outsole): the upper lofted
    from the sole to the cuff (shaft, instep, toe), the cuff band and its top ring round a dark opening, a
    midsole on a lugged outsole. Ink on the seam where the foot's panel meets the shaft, the ring's front
    edge and the midsole/outsole split (their visible arcs); the cuff's foot, the opening and the sole's top
    come from the label boundaries (the cuffs and soles carry rim_label)."""
    G = BOOT_GEOM; Wf = bg_frame(G, cx, cy); cols = 72
    hs = bg_h_sole(G); zt = G['top_z']; zb = zt - G['band_h']; ho = G['h_out']
    def w1(x, y, z):
        return tuple(map(float, Wf(np.array([x]), np.array([y]), z)[0]))
    # the upper
    zs = list(bg_levels(G, 48)); zs[0] = hs - 0.004
    rows = []
    for z in zs:
        x, y, _ = bg_section(G, max(z, hs), cols); rows.append(Wf(x, y, z))
    up = rb_ring_solid(K, name, rows, rub_m, label)
    for p in up.data.polygons:
        p.use_smooth = True
    hosts = [up.name]
    # the seam: where the foot's panel meets the shaft
    cs = 360; th = 2 * np.pi * np.arange(cs) / cs; seam = []          # v11: a sample per degree (5 degrees kinked the shoulder)
    for k in range(cs):
        z = float(np.clip(bg_seam_z(G, th[k]), hs + 0.01, zb - 0.01))
        x, y, _ = bg_section(G, z, cs, grow=E); seam.append(w1(x[k], y[k], z))
    rb_arc_lines(K, name + '_seam', seam, label)
    # the cuff band and its top ring (a small 45 degree chamfer between them), round the opening
    c2 = 96
    xo, yo, _ = bg_section(G, zb, c2, grow=G['band_out']); xc, yc, _ = bg_section(G, zb, c2, grow=G['band_out'] - 0.004)
    xi, yi, _ = bg_section(G, zb, c2, grow=G['band_out'] - G['ring_w'])
    prof = [Wf(xi, yi, zb - 0.01), Wf(xo, yo, zb - 0.01), Wf(xo, yo, zt - 0.004), Wf(xc, yc, zt), Wf(xi, yi, zt)]
    n = c2; vs = [tuple(map(float, p)) for row in prof for p in row]; fs = []
    for j in range(len(prof)):
        j2 = (j + 1) % len(prof)
        fs += [(j * n + k, j * n + (k + 1) % n, j2 * n + (k + 1) % n, j2 * n + k) for k in range(n)]
    rim = mesh(K, name + '_rim', vs, fs, rub_m, False); rim['part_label'] = rim_label; hosts.append(rim.name)
    xe, ye, _ = bg_section(G, zb, c2, grow=G['band_out'] + E)
    rb_arc_lines(K, name + '_rim_edge', [w1(xe[k], ye[k], zt - 0.003) for k in range(c2)], rim_label)
    # the dark opening, a hair below the ring
    xd, yd, _ = bg_section(G, zb, 48, grow=G['band_out'] - G['ring_w'] + 0.002)
    hole = rb_ring_solid(K, name + '_opening', [Wf(xd, yd, zt - 0.009), Wf(xd, yd, zt - 0.003)], dark_m, label)
    pw_clean_water(hole); hole.pass_index = 73
    # the midsole (a welt proud of the upper) on the outsole (a hair in, its edge notched into lugs)
    xs_, ys_, _ = bg_sole_outline(G, c2)
    bul = G.get('sole_bulge', 0.0); hm = hs - ho; rows_ = []
    for fz, g in ((0.0, -0.004), (0.35, bul), (0.7, bul * 0.75), (1.0, 0.0)):     # v13: a rounded midsole
        xg, yg, th_ = bg_sole_outline(G, c2, grow=g)
        if inner and g > 0:
            # v15 (saved-scene check: the two midsoles met): the near boot's midsole bulges less on its inner side, the
            # side that faces the far boot and away from the camera
            xh, yh, _ = bg_sole_outline(G, c2, grow=g * 0.3); wi = np.clip((inner * np.sin(th_) - 0.2) / 0.4, 0, 1)
            xg, yg = xg * (1 - wi) + xh * wi, yg * (1 - wi) + yh * wi
        rows_.append(Wf(xg, yg, ho + hm * fz))
    mid = rb_ring_solid(K, name + '_midsole', rows_, rub_m, rim_label); hosts.append(mid.name)
    xs2, ys2, _ = bg_sole_outline(G, c2, grow=E - 0.004)
    rb_arc_lines(K, name + '_sole_split', [w1(xs2[k], ys2[k], ho) for k in range(c2)], rim_label)
    c3 = 144; xq, yq, _ = bg_sole_outline(G, c3, grow=-G['out_in'])
    xqb, yqb, _ = bg_sole_outline(G, c3, grow=-G['out_in'] - G.get('sole_tuck', 0.0))   # v13: the outsole tucks in underneath
    seg = np.hypot(np.diff(np.append(xq, xq[0])), np.diff(np.append(yq, yq[0]))); s = np.concatenate([[0.0], np.cumsum(seg)[:-1]])
    sp, hw, dp = LUG
    d = np.abs(((s + sp / 2) % sp) - sp / 2); zb_ = dp * np.clip(1 - (d / hw) ** 2, 0, 1)
    top = Wf(xq, yq, ho + 0.002); bot = np.array([w1(xqb[k], yqb[k], float(zb_[k])) for k in range(c3)])
    ctr = Wf(np.array([xq.mean()]), np.array([yq.mean()]), 0.0)[0]
    vs = [tuple(map(float, p)) for p in bot] + [tuple(map(float, p)) for p in top] + [tuple(map(float, ctr))]
    fs = [(k, (k + 1) % c3, c3 + (k + 1) % c3, c3 + k) for k in range(c3)] + [tuple(c3 + k for k in range(c3))]
    fs += [(2 * c3, (k + 1) % c3, k) for k in range(c3)]
    out = mesh(K, name + '_outsole', vs, fs, rub_m, False); out['part_label'] = rim_label; hosts.append(out.name)
    return hosts


def rb_duck(K, body_m, beak_m, dark_m, label, beak_label):
    """v9: the duck built from source/duck_geom.py, fitted to the shipped duck (its inked silhouette, its bill's
    region and its neck line, the head pinned to the shipped head's circle): it faces +X, 45 degrees off the
    viewer, so both eyes show as shipped; the bill tipped up. Its eyes, neck line, mouth line, wing and
    feathers are the shipped strokes carried onto the surfaces through the camera (DUCK_STROKES)."""
    D = DUCK_GEOM; place = dg_place(D)
    def sphere_mesh(name, fn, mat, lab, u=64, v=32):
        bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=1.0)
        co = np.array([tuple(q.co) for q in bm.verts]); W = place(*fn(D, co[:, 0], co[:, 1], co[:, 2]))
        for q, p in zip(bm.verts, W):
            q.co = Vector(tuple(map(float, p)))
        me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
        ob = noink(K.obj(name, me, mat, True)); ob['part_label'] = lab
        for p in ob.data.polygons:
            p.use_smooth = True
        return ob
    # v15 (saved-scene check): the body's hidden rear rests against the stack's bottom fold instead of passing
    # into it (a soft duck against soft sheets; those faces all face away from the camera)
    zb5 = sum(t_ + GAP for _, t_, *_r in LAYERS[:5]); t5 = LAYERS[5][1]; r5 = t5 / 2; zc5 = zb5 + r5
    xc5 = STACK_X - LAYERS[5][3] - r5
    def body_fn(D_, x, y, z):
        X, Y, Z = dg_body_local(D_, x, y, z)
        W = place(X, Y, Z); wx_, wy_, wz_ = W[..., 0], W[..., 1], W[..., 2]
        dz = np.clip(np.abs(wz_ - zc5) / r5, 0, 1); xmin = xc5 + r5 * np.sqrt(1 - dz * dz) + 0.004
        hit = (wy_ > -0.004) & (np.abs(wz_ - zc5) < r5) & (wx_ < xmin)
        X = np.where(hit, X + (xmin - wx_) / D_['s'], X)
        return X, Y, Z
    body = sphere_mesh('duck_body', body_fn, body_m, label)
    head = sphere_mesh('duck_head', dg_head_local, body_m, label)
    # v15 (saved-scene check: the pinned head sat 0.1 above the body in depth): a neck peg joining them, laid along the
    # camera's line of sight behind the head, through the lower-left of its disc (0.65 radii down, 0.30 left: the most
    # central line that reaches the body, 0.415 behind the head's centre), 0.2 radii thick; on screen it lies wholly
    # inside the head's disc, so it never shows
    vloc = np.array([-1.0, 1.0, -1.0]) / math.sqrt(3.0); hc = np.array([D['hx'], 0.0, D['hz']])
    down = np.array([1.0, -1.0, -2.0]) / math.sqrt(6.0); right = np.array([1.0, 1.0, 0.0]) / math.sqrt(2.0)
    uoff = (0.65 * down - 0.30 * right) * D['hr']; a0, a1 = hc + uoff, hc + uoff + vloc * (0.415 + 0.04); pr = D['hr'] * 0.2
    u_ = right; w_ = down
    ring = [(math.cos(2 * math.pi * k / 16), math.sin(2 * math.pi * k / 16)) for k in range(16)]
    nv = [a_ + (u_ * c + w_ * s_) * pr for a_ in (a0, a1) for c, s_ in ring]
    nW = place(*np.array(nv).T); vs_n = [tuple(map(float, p)) for p in nW]
    fs_n = [tuple(reversed(range(16))), tuple(16 + k for k in range(16))] + [(k, (k + 1) % 16, 16 + (k + 1) % 16, 16 + k) for k in range(16)]
    neck = mesh(K, 'duck_neck', vs_n, fs_n, body_m, False); neck['part_label'] = label
    # v12 (review v11: dots under the chin read as a collar): no stipple on the head (the shipped head has none) or on
    # the chest just under it; the shade dots stay on the lower body, as shipped
    pw_clean_water(head)
    yw = math.radians(D['yaw']); cw_, sw_ = math.cos(yw), math.sin(yw)
    attr = body.data.attributes.get('icon_stipple_clear') or body.data.attributes.new('icon_stipple_clear', 'FLOAT', 'CORNER')
    for poly in body.data.polygons:
        c = poly.center; dx, dy = c.x - D['x'], c.y - D['y']
        lx = (dx * cw_ + dy * sw_) / D['s']; lz = c.z / D['s']
        clear = 1.0 if (lx > 0.02 and lz > D['rz'] * D['fb'] + 0.02) else 0.0
        for li in poly.loop_indices:
            attr.data[li].value = clear
    beak = sphere_mesh('duck_beak', dg_bill_local, beak_m, beak_label)
    lower = sphere_mesh('duck_beak_lower', lambda D_, x, y, z: dg_bill_local(D_, x, y, z, True), beak_m, beak_label, 48, 24)
    kx, kz = dg_bill_centre(D)
    centres = {'body': np.array([0.0, 0.0, D['rz'] * D['fb']]), 'head': np.array([D['hx'], 0.0, D['hz']]), 'bill': np.array([kx, 0.0, kz])}
    def lifted(pts, part, d):
        P = np.array(pts, float); n = P - centres[part]; n /= np.linalg.norm(n, axis=1, keepdims=True)
        return place(*(P + n * d / D['s']).T)
    for nm in ('eye_near', 'eye_far'):
        st = DUCK_STROKES[nm]; W = lifted(st['pts'], 'head', 0.003); c = W.mean(0)
        vs = [tuple(map(float, p)) for p in W] + [tuple(map(float, c))]; n = len(W)
        eye = mesh(K, 'duck_' + nm, vs, [(n, k, (k + 1) % n) for k in range(n)], dark_m, False)
        eye['part_label'] = label; eye.pass_index = 73; pw_clean_water(eye)
    for nm, lab in (('neck', label), ('mouth', beak_label), ('wing', label), ('feather', label), ('feather2', label)):
        if nm not in DUCK_STROKES:
            continue
        st = DUCK_STROKES[nm]; W = lifted(st['pts'], st['part'], E)
        tagged_line(K, 'duck_' + nm, [tuple(map(float, p)) for p in W], lab, 6, st['closed'])['ink_width'] = 0
    return [body.name, head.name, beak.name, lower.name, neck.name]


def build_rubber():
    """Rubber v1: the shipped stack of folded sheets, the wellingtons and the duck on the grid."""
    setup_icon_rig(); K = Kit(open_collection('ICON_rubber')); hosts = []
    rub_m = rb_toon('rb_rubber', (44, 44, 47), (58, 58, 61), (78, 78, 81))
    stitch_m = pw_flat('rb_stitch', rb_rgb(226, 182, 100))
    dark_m = pw_flat('rb_inside', rb_rgb(30, 30, 28))
    duck_m = rb_toon('rb_duck', (214, 160, 70), (236, 190, 90), (248, 214, 124))
    beak_m = rb_toon('rb_beak', (192, 96, 48), (222, 122, 62), (238, 152, 92))
    L_SHEETS, L_FOLDS, L_BOOT_A, L_BOOT_B, L_SOLE, L_DUCK, L_BEAK = 1, 2, 3, 4, 5, 6, 7

    sh, top_z = rb_stack(K, rub_m, stitch_m, L_SHEETS, L_FOLDS); hosts += sh
    for i, (bx, by) in enumerate(BOOTS):
        hosts += rb_boot(K, 'boot%d' % i, bx, by, rub_m, dark_m, (L_BOOT_A, L_BOOT_B)[i], L_SOLE, inner=1 if i == 0 else 0)
    hosts += rb_duck(K, duck_m, beak_m, pw_flat('rb_eye', rb_rgb(20, 30, 60)), L_DUCK, L_BEAK)

    info = contract(K, hosts, 'a stack of folded dark rubber sheets with tan stitching; a pair of black wellingtons; a yellow rubber duck')
    info['revision'] = RB_REVISION
    info['outline']['component_boundaries'] = True
    info['stipple']['strength'] = 0.38
    info['stipple']['groups'][0]['thresholds'] = [0.575, 0.50, 0.30]
    info['stipple']['groups'][0]['labels'] = [1, 2, 3, 4, 5, 6]      # v11: no dots on the bill (a lone dot read as dirt)
    info['dimensions'] = {'stack': [STACK_X, STACK_Y, round(top_z, 3)], 'layers': LAYERS, 'boots': BOOTS, 'boot': BOOT_GEOM, 'lug': LUG, 'duck': DUCK_GEOM, 'dash': DASH}
    return info
