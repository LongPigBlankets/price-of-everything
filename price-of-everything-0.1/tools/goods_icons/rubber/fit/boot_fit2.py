"""Region fit of the two wellingtons (source/boot_geom.py) to the shipped boots' parts, read off the ink:
opening, rim ring, cuff band, shaft, foot panel, midsole, outsole of each boot (ref_boot_parts_half.npy).
The model is painted back to front (back faces culled, quads sorted by depth), its regions shrunk by the
shipped ink's half widths (interior lines ~5 px@800, the outline ~9 px@800), and scored by the parts' IoU
outside the duck. The stack's camera (stack_fit.json)."""
import json, math, sys, time
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt, binary_dilation
sys.path.insert(0, '../source')
from boot_geom import *
from rfit_common import project, PX800, DUCK

CAM = json.load(open('stack_fit.json'))['C']
REFP = np.load('ref_boot_parts_half.npy')
H, W = REFP.shape
WY, WX = slice(320, 840), slice(480, 900)          # the boots' window (half-res)
REFW = REFP[WY, WX]
CARE = ~binary_dilation(DUCK, iterations=8)[WY, WX]
VIEWV = np.array([1.0, -1.0, 1.0]) / math.sqrt(3)
LAB = dict(opening=1, ring=2, band=3, shaft=4, foot=5, midsole=6, welt=6, outsole=7)
NAMES = {1: 'opening', 2: 'ring', 3: 'band', 4: 'shaft', 5: 'foot', 6: 'midsole', 7: 'outsole'}
WEIGHT = {1: 1.0, 2: 0.5, 3: 0.7, 4: 1.5, 5: 1.5, 6: 1.0, 7: 0.7}
R_INT = 2.5 / PX800            # half an interior shipped line
R_OUT = 4.5 / PX800            # half the shipped outline


def paint(G, B, shape=(H, W), win=True):
    img = Image.new('L', (shape[1], shape[0]), 0); d = ImageDraw.Draw(img)
    ox, oy = (WX.start, WY.start) if win else (0, 0)
    if win:
        img = Image.new('L', (WX.stop - WX.start, WY.stop - WY.start), 0); d = ImageDraw.Draw(img)
    for (cx, cy, off) in B:                                     # far boot first
        quads, top = bg_parts(G, cx, cy)
        labs = np.array([LAB[l] for l, _ in quads]); Q = np.array([q for _, q in quads])
        n = np.cross(Q[:, 2] - Q[:, 0], Q[:, 3] - Q[:, 1]); c = Q.mean(1)
        out = c - np.column_stack([np.full(len(c), cx), np.full(len(c), cy), c[:, 2]])
        n *= np.sign((n * out).sum(1) + 1e-12)[:, None]
        welt = labs == 6
        welt &= np.array([l == 'welt' for l, _ in quads])
        n[welt] = (0, 0, 1)
        vis = n @ VIEWV > 0
        order = np.argsort((c @ VIEWV)[vis]); Qv = Q[vis][order]; Lv = labs[vis][order]
        P2 = project(Qv, CAM) - (ox, oy)
        for q, v in zip(P2, Lv):
            d.polygon([(float(a), float(b)) for a, b in q], fill=int(v + off))
        for l, ring in top:
            d.polygon([(float(a), float(b)) for a, b in project(ring, CAM) - (ox, oy)], fill=LAB[l] + off)
    return np.array(img)


def shrink(Lm):
    """The model's regions as the shipped art draws them: less half a line at each part boundary, less half
    the outline where the boots meet anything else."""
    bnd = np.zeros(Lm.shape, bool)
    bnd[:-1] |= Lm[:-1] != Lm[1:]; bnd[1:] |= Lm[:-1] != Lm[1:]
    bnd[:, :-1] |= Lm[:, :-1] != Lm[:, 1:]; bnd[:, 1:] |= Lm[:, :-1] != Lm[:, 1:]
    d_b = distance_transform_edt(~bnd); d_o = distance_transform_edt(Lm > 0)
    return np.where((d_b > R_INT) & (d_o > R_OUT), Lm, 0)


def boots_of(P):
    return [(P['b1x'], P['b1y'], 10), (P['b0x'], P['b0y'], 0)]


def score(P, detail=False):
    G = {k: P[k] for k in BOOT_G}
    Lm = shrink(paint(G, boots_of(P)))
    tot = 0.0; wsum = 0.0; det = {}
    for off in (0, 10):
        for v, w in WEIGHT.items():
            a = (Lm == v + off) & CARE; b = (REFW == v + off) & CARE
            u = (a | b).sum()
            if u == 0:
                continue
            j = (a & b).sum() / u; det[NAMES[v] + ('_far' if off else '_near')] = round(float(j), 3)
            tot += w * j; wsum += w
    return (tot / wsum, det) if detail else tot / wsum


def view(P, path):
    G = {k: P[k] for k in BOOT_G}
    Lm = shrink(paint(G, boots_of(P)))
    cols = {1: (240, 110, 200), 2: (220, 240, 80), 3: (150, 160, 90), 4: (80, 140, 180), 5: (130, 70, 150), 6: (150, 240, 210), 7: (220, 60, 200)}
    def rgb(L):
        o = np.zeros(L.shape + (3,), np.uint8)
        for v, c in cols.items():
            o[L == v] = c; o[L == v + 10] = tuple(int(x * 0.75) for x in c)
        return o
    a = rgb(REFW); b = rgb(Lm)
    diff = np.zeros_like(a); same = (Lm == REFW) & (Lm > 0); diff[same] = (60, 110, 60)
    diff[(Lm != REFW) & ((Lm > 0) | (REFW > 0))] = (230, 80, 80); diff[~CARE] = (70, 70, 90)
    Image.fromarray(np.concatenate([a, b, diff], 1)).save(path)


KEYS = ['top_z', 'band_h', 'ring_w', 'A_t', 'B_t', 'A_a', 'B_a', 'z_ank', 'L_toe', 'heel', 'W_foot', 'wk', 'm', 'n',
        'p_ft', 'seam_mid', 'seam_amp', 'seam_fb', 'h_out', 'h_mid', 'welt', 'arch0', 'arch1', 'yaw', 'b0x', 'b0y', 'b1x', 'b1y']
LO = dict(top_z=0.6, band_h=0.02, ring_w=0.008, A_t=0.10, B_t=0.07, A_a=0.09, B_a=0.06, z_ank=0.15, L_toe=0.25, heel=0.0,
          W_foot=0.07, wk=-0.3, m=1.0, n=0.3, p_ft=2.0, seam_mid=0.10, seam_amp=0.0, seam_fb=-0.1, h_out=0.03, h_mid=0.02,
          welt=0.0, arch0=-0.25, arch1=-0.1, yaw=-25, b0x=0.9, b0y=0.2, b1x=0.9, b1y=0.5)
HI = dict(top_z=1.0, band_h=0.09, ring_w=0.04, A_t=0.24, B_t=0.18, A_a=0.22, B_a=0.16, z_ank=0.5, L_toe=0.6, heel=0.08,
          W_foot=0.18, wk=0.4, m=5.0, n=1.5, p_ft=3.5, seam_mid=0.4, seam_amp=0.12, seam_fb=0.1, h_out=0.08, h_mid=0.09,
          welt=0.03, arch0=0.2, arch1=0.3, yaw=25, b0x=1.6, b0y=0.7, b1x=1.6, b1y=1.0)

if __name__ == '__main__':
    P = dict(BOOT_G); P.update(b0x=1.2636, b0y=0.4425, b1x=1.2424, b1y=0.7233)
    if len(sys.argv) > 1 and sys.argv[1].endswith('.json'):
        P.update(json.load(open(sys.argv[1])))
    t0 = time.time(); s, det = score(P, True); print('start %.4f (%.2fs)' % (s, time.time() - t0), det, flush=True)
    view(P, 'boot_fit2_start.png')
    keys = [k for k in KEYS]; lo = np.array([LO[k] for k in keys]); hi = np.array([HI[k] for k in keys])
    keys = keys + ['d_ground']; lo = np.append(lo, -0.05); hi = np.append(hi, 0.05)
    P['d_ground'] = 0.0
    def unpack(x):
        Q = dict(P); Q.update({k: float(v) for k, v in zip(keys, np.clip(x, lo, hi))})
        d = Q.pop('d_ground')                # the boots taller at the bottom, the rest fixed on screen
        for k, sgn in (('b0x', 1), ('b0y', -1), ('b1x', 1), ('b1y', -1), ('top_z', 1), ('z_ank', 1), ('seam_mid', 1)):
            Q[k] += sgn * d
        return Q
    # first place the boots (a small grid on the pair's shift), then everything
    best = (s, P)
    for dx in np.linspace(-0.08, 0.08, 5):
        for dy in np.linspace(-0.08, 0.08, 5):
            Q = dict(P, b0x=P['b0x'] + dx, b1x=P['b1x'] + dx, b0y=P['b0y'] + dy, b1y=P['b1y'] + dy); v = score(Q)
            if v > best[0]:
                best = (v, Q)
    P = best[1]; print('grid %.4f' % best[0], flush=True)
    from best_powell import best_powell
    x0 = np.clip([P[k] for k in keys], lo, hi)
    rounds = int(sys.argv[2]) if len(sys.argv) > 2 else 3
    x0, _ = best_powell(lambda x: -score(unpack(x)), x0, lo, hi, rounds, log=lambda m: print(m, flush=True))
    P = unpack(x0); s, det = score(P, True)
    out = sys.argv[3] if len(sys.argv) > 3 else 'boot_fit2'
    json.dump(P, open(out + '.json', 'w'), indent=1); view(P, out + '.png')
    print('final %.4f' % s, det); print({k: round(v, 4) for k, v in P.items()})
