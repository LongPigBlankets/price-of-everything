"""Silhouette fit of the PET bottle: a lathe about a vertical axis standing on the ground at (bx, by),
projected with the chair fit's camera (S, TX, TY), inked like the exporter, IoU against the shipped
bottle's inked silhouette (half-res frame of the chair fit)."""
import json, math, sys, time
import numpy as np
from PIL import Image, ImageDraw
from scipy import optimize
from scipy.ndimage import distance_transform_edt
from chair_fit2 import project, R_OUT, SHAPE, VIEW

full = np.zeros((1770, 1420), bool)
crop = np.array(Image.open('ref_bottle_mask_full.png')) > 0
full[1080:1080 + crop.shape[0], 150:150 + crop.shape[1]] = crop
REFB = full.reshape(885, 2, 710, 2).any(axis=(1, 3))
ys, xs = np.where(REFB); WIN = (slice(ys.min() - 40, ys.max() + 40), slice(max(0, xs.min() - 40), xs.max() + 40))

def profile(B):
    """(r, z) samples of the bottle's outline, bottom to top: a rounded foot, the body, a shoulder dome
    (a superellipse quarter, exponent p) up to the cap, and the cap (rc, hc)."""
    R, H, hc, rc, zs0, p, rb = B['R'], B['H'], B['hc'], B['rc'], B['zs0'], B['p'], B['rb']
    zc0 = H - hc; pts = []
    for k in range(9):
        a = math.pi / 2 * (1 - k / 8)
        pts.append((R - rb + rb * math.cos(a), rb - rb * math.sin(a)))
    for k in range(1, 12):
        pts.append((R, rb + (zs0 - rb) * k / 11))
    for k in range(1, 21):
        u = k / 20
        pts.append((rc + (R - rc) * max(0.0, 1 - u ** p) ** (1 / p), zs0 + (zc0 - zs0) * u))
    pts += [(rc, zc0), (rc, H)]
    return pts

def raster(B, S):
    img = Image.new('L', (SHAPE[1], SHAPE[0]), 0); d = ImageDraw.Draw(img)
    th = np.linspace(0, 2 * np.pi, 60, endpoint=False)
    lobe = 0.5 - 0.5 * np.cos(5 * (th + math.pi / 4))          # five petals, one facing the viewer
    rings = []
    for r, z in profile(B):
        s = max(0.0, 1 - z / B['zf']); k = 1 - B['pinch'] * s * lobe
        pts = np.column_stack([B['bx'] + r * k * np.cos(th), B['by'] + r * k * np.sin(th), np.full(len(th), z)])
        rings.append(project(pts, S))
    for i, r2 in enumerate(rings):
        d.polygon([tuple(p) for p in r2], fill=255)
        if i:
            a, b = rings[i - 1], r2
            la, ra = a[np.argmin(a[:, 0])], a[np.argmax(a[:, 0])]; lb, rb_ = b[np.argmin(b[:, 0])], b[np.argmax(b[:, 0])]
            d.polygon([tuple(la), tuple(ra), tuple(rb_), tuple(lb)], fill=255)
    M = np.array(img) > 0
    return distance_transform_edt(~M) <= R_OUT

def iou(B, S):
    M = raster(B, S)[WIN]; R = REFB[WIN]
    return (M & R).sum() / max((M | R).sum(), 1)

def overlay(B, S, path):
    M = raster(B, S); vis = np.zeros(SHAPE + (3,), 'uint8')
    vis[REFB] = (120, 200, 120); vis[M & ~REFB] = (230, 80, 80); vis[M & REFB] = (60, 110, 60)
    Image.fromarray(vis[WIN]).resize(((WIN[1].stop - WIN[1].start) * 2, (WIN[0].stop - WIN[0].start) * 2), Image.NEAREST).save(path)

if __name__ == '__main__':
    S = json.load(open(sys.argv[1]))                  # the chair fit (camera)
    B = dict(bx=0.28, by=-0.75, R=0.12, H=0.81, hc=0.055, rc=0.052, zs0=0.58, p=2.0, rb=0.01, pinch=0.15, zf=0.10)
    if len(sys.argv) > 3:
        B.update(json.load(open(sys.argv[3])))
    # place the bottle's foot under the shipped bottom centre: search bx, by on a grid first
    best = None
    for bx in np.linspace(B['bx'] - 0.15, B['bx'] + 0.15, 21):
        for by in np.linspace(B['by'] - 0.15, B['by'] + 0.15, 21):
            v = iou(dict(B, bx=bx, by=by), S)
            if best is None or v > best[0]:
                best = (v, bx, by)
    B['bx'], B['by'] = best[1], best[2]; print('grid IoU %.4f at (%.3f, %.3f)' % best, flush=True)
    keys = ['bx', 'by', 'R', 'H', 'hc', 'rc', 'zs0', 'p', 'rb', 'pinch', 'zf']
    lo = np.array([-0.6, -1.8, 0.05, 0.5, 0.02, 0.03, 0.3, 1.2, 0.003, 0.0, 0.02])
    hi = np.array([1.0, 0.0, 0.18, 1.2, 0.12, 0.09, 0.75, 4.0, 0.06, 0.4, 0.25])
    if 'hc_fixed' in B:
        lo[4] = hi[4] = B['hc'] = B['hc_fixed']
    if 'p_min' in B:
        lo[7] = B['p_min']; B['p'] = max(B['p'], B['p_min'])
    if 'rc_min' in B:
        lo[5] = B['rc_min']; B['rc'] = max(B['rc'], B['rc_min'])
    if 'pinch_max' in B:
        hi[9] = B['pinch_max']; B['pinch'] = min(B['pinch'], B['pinch_max'])
    if 'zs0_min' in B:
        lo[6] = B['zs0_min']; B['zs0'] = max(B['zs0'], B['zs0_min'])
    if 'zf_min' in B:
        lo[10] = B['zf_min']; B['zf'] = max(B['zf'], B['zf_min'])
    def unpack(x):
        Q = dict(B); Q.update({k: float(v) for k, v in zip(keys, np.clip(x, lo, hi))})
        Q['zs0'] = min(Q['zs0'], Q['H'] - Q['hc'] - 0.05)
        return Q
    x0 = np.clip([B[k] for k in keys], lo, hi); t = time.time()
    for rnd in range(3):
        res = optimize.minimize(lambda x: -iou(unpack(x), S), x0, method='Powell', bounds=list(zip(lo, hi)), options={'xtol': 1e-4, 'ftol': 1e-6, 'maxiter': 5000})
        x0 = res.x; print('round', rnd, 'IoU %.4f' % -res.fun, '%.0fs' % (time.time() - t), flush=True)
    B = unpack(x0); json.dump(B, open(sys.argv[2], 'w'), indent=1); overlay(B, S, sys.argv[2].replace('.json', '.png'))
    print({k: round(v, 4) for k, v in B.items()})
