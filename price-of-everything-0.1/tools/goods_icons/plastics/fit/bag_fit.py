"""Silhouette fit of the carrier bag: a soft body (superellipse sections, belly and neck, a sagging
mouth), two handle loops (elliptical bands above the mouth's sides, each tilted about the vertical),
and the pellet heap; placed with the chair fit's camera, inked, IoU against the shipped bag."""
import json, math, sys, time
import numpy as np
from PIL import Image, ImageDraw
from scipy import optimize
from scipy.ndimage import distance_transform_edt, binary_fill_holes
from chair_fit2 import project, R_OUT, R_HOLE, SHAPE

full = np.array(Image.open('ref_bag_mask_full.png')) > 0
REFG = full.reshape(885, 2, 710, 2).mean(axis=(1, 3)) >= 0.5
ys, xs = np.where(REFG); WIN = (slice(max(0, ys.min() - 50), ys.max() + 30), slice(max(0, xs.min() - 50), min(710, xs.max() + 40)))

G0 = dict(bx=1.10, by=0.10, yaw=78.0, H=0.80, W=0.80, bulge=0.10, neck=0.14, D=0.42, bb=0.30, bn=0.45, pe=2.4, s1=0.05, s2=0.15,
          hL_c=0.62, hL_z=0.12, hL_rx=0.16, hL_rz=0.26, hL_w=0.07, hL_psi=0.0, hL_y=0.0,
          hR_c=0.62, hR_z=0.12, hR_rx=0.16, hR_rz=0.30, hR_w=0.07, hR_psi=0.0, hR_y=0.0, heap=0.08)

def rot(G):
    y = math.radians(G['yaw']); c, s = math.cos(y), math.sin(y)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1.0]])

def body_fns(G):
    W, D, H = G['W'], G['D'], G['H']
    a = lambda t: W / 2 * (1 + G['bulge'] * np.sin(np.pi * np.minimum(1, t / 0.8)) - G['neck'] * np.maximum(0, t - 0.6) / 0.4)
    b = lambda t: D / 2 * (0.75 + G['bb'] * np.sin(np.pi * np.minimum(1, t / 0.75)) - G['bn'] * np.maximum(0, t - 0.55) / 0.45)
    rim = lambda th: H * (1 - G['s1'] * np.abs(np.sin(th)) ** G.get('sq', 1.0) - G['s2'] * np.maximum(0.0, -np.sin(th)) ** 1.5)
    return a, b, rim

def parts(G, rows=28, cols=48):
    """World-space polygons: body quads, handle band quads, heap polygon."""
    Rz = rot(G); O = np.array([G['bx'], G['by'], 0.0]); a, b, rim = body_fns(G); p = G['pe']
    th = np.linspace(0, 2 * np.pi, cols, endpoint=False); c, s = np.cos(th), np.sin(th)
    t = np.linspace(0, 1, rows + 1)
    X = a(t)[:, None] * np.sign(c) * np.abs(c) ** (2 / p); Y = b(t)[:, None] * np.sign(s) * np.abs(s) ** (2 / p)
    Z = t[:, None] * rim(th)[None, :]
    body = (np.stack([X, Y, Z], -1) @ Rz.T) + O
    handles = []
    for side, k in ((-1, 'hL'), (1, 'hR')):
        cxl = side * a(1.0) * G[k + '_c']; zr = (G['H'] - 0.02) if G.get('shoulders', 0) else (G['H'] * (1 - G['s1']) - 0.02)
        psi = math.radians(G[k + '_psi']); u = np.linspace(-0.15 * np.pi, 1.15 * np.pi, 40)
        outer, inner = [], []
        for rx, rz, lst in ((G[k + '_rx'], G[k + '_rz'], outer), (G[k + '_rx'] - G[k + '_w'], G[k + '_rz'] - G[k + '_w'], inner)):
            for uu in u:
                dx = rx * math.cos(uu); dz = rz * math.sin(uu)
                # the loop's plane: the bag's width-z plane turned by psi about the vertical through its foot
                lx = cxl + dx * math.cos(psi); ly = G[k + '_y'] + dx * math.sin(psi)
                lst.append((lx, ly, zr + G[k + '_z'] + dz))
        loop = (np.array(outer) @ Rz.T + O, np.array(inner) @ Rz.T + O)
        handles.append(loop)
    # the heap: a dome over the mouth's ellipse
    ea, eb = a(1.0) * 0.86, b(1.0) * 0.80; q = np.linspace(0, 2 * np.pi, 40, endpoint=False)
    heap = []
    for f in (0.0, 0.5, 0.8, 0.95):
        r = math.sqrt(max(0.0, 1 - f * f))
        zm = G['H'] * (1 - G['s1']) if G.get('shoulders', 0) else G['H'] * 0.80 + 0.05
        heap.append(np.column_stack([ea * r * np.cos(q), eb * r * np.sin(q), np.full(len(q), zm + G['heap'] * f)]) @ Rz.T + O)
    return body, handles, heap

def raster(G):
    img = Image.new('L', (SHAPE[1], SHAPE[0]), 0); d = ImageDraw.Draw(img)
    body, handles, heap = parts(G)
    B2 = project(body, G['cam'])
    R, C = B2.shape[:2]
    for i in range(R - 1):
        for j in range(C):
            j2 = (j + 1) % C
            d.polygon([tuple(B2[i, j]), tuple(B2[i, j2]), tuple(B2[i + 1, j2]), tuple(B2[i + 1, j])], fill=255)
    d.polygon([tuple(p) for p in B2[-1]], fill=255)
    for outer, inner in handles:
        o2 = project(outer, G['cam']); i2 = project(inner, G['cam'])
        for k in range(len(o2) - 1):
            d.polygon([tuple(o2[k]), tuple(o2[k + 1]), tuple(i2[k + 1]), tuple(i2[k])], fill=255)
    for h in heap:
        d.polygon([tuple(p) for p in project(h, G['cam'])], fill=255)
    M = np.array(img) > 0
    filled = binary_fill_holes(M); vis = distance_transform_edt(~filled) <= R_OUT
    holes = filled & ~M
    if holes.any():
        vis &= ~(distance_transform_edt(holes) > R_HOLE)
    return vis

def iou(G):
    M = raster(G)[WIN]; R = REFG[WIN]
    return (M & R).sum() / max((M | R).sum(), 1)

def overlay(G, path):
    M = raster(G); vis = np.zeros(SHAPE + (3,), 'uint8')
    vis[REFG] = (120, 200, 120); vis[M & ~REFG] = (230, 80, 80); vis[M & REFG] = (60, 110, 60)
    Image.fromarray(vis[WIN]).resize(((WIN[1].stop - WIN[1].start) * 2, (WIN[0].stop - WIN[0].start) * 2), Image.NEAREST).save(path)

KEYS = ['bx', 'by', 'yaw', 'H', 'W', 'bulge', 'D', 'bb', 's1', 'sq', 's2',
        'hL_c', 'hL_z', 'hL_rx', 'hL_rz', 'hL_w', 'hL_psi', 'hL_y', 'hR_c', 'hR_z', 'hR_rx', 'hR_rz', 'hR_w', 'hR_psi', 'hR_y', 'heap']
LO = dict(bx=0.5, by=-0.6, yaw=50, H=0.5, W=0.5, bulge=-0.1, neck=0.0, D=0.2, bb=0.0, bn=0.0, s1=0.0, sq=0.2, s2=0.0,
          hL_c=0.2, hL_z=-0.25, hL_rx=0.06, hL_rz=0.1, hL_w=0.03, hL_psi=-60, hL_y=-0.2, hR_c=0.2, hR_z=-0.25, hR_rx=0.06, hR_rz=0.1, hR_w=0.03, hR_psi=-60, hR_y=-0.2, heap=0.0)
HI = dict(bx=1.8, by=0.8, yaw=100, H=1.4, W=1.2, bulge=0.4, neck=0.4, D=0.8, bb=0.6, bn=0.10, s1=0.5, sq=1.5, s2=0.5,
          hL_c=1.0, hL_z=0.3, hL_rx=0.35, hL_rz=0.5, hL_w=0.15, hL_psi=60, hL_y=0.2, hR_c=1.0, hR_z=0.3, hR_rx=0.35, hR_rz=0.55, hR_w=0.15, hR_psi=60, hR_y=0.2, heap=0.15)

if __name__ == '__main__':
    cam = json.load(open(sys.argv[1])); G = dict(G0); G['cam'] = {k: cam[k] for k in ('S', 'TX', 'TY')}
    if len(sys.argv) > 3:
        G.update(json.load(open(sys.argv[3])))
    lo = np.array([LO[k] for k in KEYS]); hi = np.array([HI[k] for k in KEYS])
    if 'yaw_fixed' in G:                             # on the isometric grid (owner ruling 3)
        i = KEYS.index('yaw'); lo[i] = hi[i] = G['yaw'] = G['yaw_fixed']
    if G.get('flush', 0):                            # v11: straps flush with the sides, square-ish, slim
        for kk, (a_, b_) in (('hL_psi', (-15, 15)), ('hR_psi', (-15, 15)), ('hL_w', (0.04, 0.065)), ('hR_w', (0.04, 0.065))):
            i = KEYS.index(kk); lo[i], hi[i] = a_, b_; G[kk] = float(np.clip(G[kk], a_, b_))
    def unpack(x):
        Q = dict(G); Q.update({k: float(v) for k, v in zip(KEYS, np.clip(x, lo, hi))})
        if Q.get('flush', 0):
            a1 = body_fns(Q)[0](1.0)
            for h in ('hL', 'hR'):
                Q[h + '_c'] = max(0.2, (a1 - Q[h + '_rx'] - 0.005) / a1)
        return Q
    # place the body first on a coarse grid
    best = None
    for bx in np.linspace(G['bx'] - 0.1, G['bx'] + 0.1, 5):
        for by in np.linspace(G['by'] - 0.1, G['by'] + 0.1, 5):
            v = iou(dict(G, bx=bx, by=by))
            if best is None or v > best[0]:
                best = (v, bx, by)
    G['bx'], G['by'] = best[1], best[2]; print('grid IoU %.4f at (%.3f, %.3f)' % best, flush=True)
    from best_powell import best_powell
    x0 = np.clip([G[k] for k in KEYS], lo, hi)
    x0, _ = best_powell(lambda x: -iou(unpack(x)), x0, lo, hi, int(sys.argv[4]) if len(sys.argv) > 4 else 3, log=lambda m: print(m, flush=True), xtol=1e-3, ftol=1e-5)
    G = unpack(x0); json.dump({k: G[k] for k in KEYS + ['shoulders', 'bn', 'neck']}, open(sys.argv[2], 'w'), indent=1)
    overlay(G, sys.argv[2].replace('.json', '.png'))
    print({k: round(G[k], 3) for k in KEYS})
