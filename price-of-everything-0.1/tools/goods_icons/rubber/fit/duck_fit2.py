"""Region fit of the rubber duck (source/duck_geom.py) to the shipped duck: its inked silhouette, its bill
(the orange region, less half a line), and its neck line (the shipped ink curve where the head's back
meets the body, scored by its distance to the model's head/body boundary). Painted back to front with
back faces culled; the stack's camera."""
import json, math, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt
sys.path.insert(0, '../source')
from duck_geom import *
from rfit_common import project, PX800, DUCK, inked, R_OUT as R_OUTK

CAM = json.load(open('stack_fit.json'))['C']
H, W = DUCK.shape
ys, xs = np.where(DUCK); WY = slice(ys.min() - 40, ys.max() + 30); WX = slice(xs.min() - 40, xs.max() + 60)
OX, OY = WX.start, WY.start
def half_mask(m):
    h, w = m.shape; return m[:h // 2 * 2, :w // 2 * 2].reshape(h // 2, 2, w // 2, 2).mean(axis=(1, 3)) >= 0.5
REG = np.load('duck_regions_lab.npy'); BEAK = half_mask(REG == 78)[WY, WX]
INK = np.load('duck_inner_ink_lab.npy')
def pts_half(k):
    yy, xx = np.where(INK == k); return np.column_stack([xx / 2.0 - OX, yy / 2.0 - OY])
NECK = pts_half(21); EYE_N = pts_half(17).mean(0); EYE_F = pts_half(14).mean(0)
SIL = DUCK[WY, WX]
VIEWV = np.array([1.0, -1.0, 1.0]) / math.sqrt(3)
LAB = dict(body=1, head=2, bill=3, lower=3)
R_INT = 2.5 / PX800; R_OUT = 4.5 / PX800


def paint(D, nu=48, nv=24):
    img = Image.new('L', (WX.stop - WX.start, WY.stop - WY.start), 0); d = ImageDraw.Draw(img)
    Qs, Ls, Ds = [], [], []
    for name, g, c in dg_parts(D, nu, nv):
        a, b = g[:-1], g[1:]
        q = np.stack([a, np.roll(a, -1, 1), np.roll(b, -1, 1), b], 2).reshape(-1, 4, 3)
        n = np.cross(q[:, 2] - q[:, 0], q[:, 3] - q[:, 1]); m = q.mean(1)
        n *= np.sign(((m - c) * n).sum(1) + 1e-12)[:, None]
        vis = n @ VIEWV > 0
        Qs.append(q[vis]); Ls.append(np.full(vis.sum(), LAB[name])); Ds.append((m @ VIEWV)[vis])
    Q = np.concatenate(Qs); L = np.concatenate(Ls); Dp = np.concatenate(Ds); o = np.argsort(Dp)
    P2 = project(Q[o], CAM) - (OX, OY)
    for q, v in zip(P2, L[o]):
        d.polygon([(float(x), float(y)) for x, y in q], fill=int(v))
    return np.array(img)


HEAD_PIN = (512.25, 684.0, 0.1298)            # the shipped head's circle (half-res centre, world radius)


def pin_head(D):
    """hx, hz, hr so that the head's sphere projects onto the shipped head's circle, for this placement."""
    c, s_ = math.cos(math.radians(D['yaw'])), math.sin(math.radians(D['yaw'])); S, TX, TY = CAM['S'], CAM['TX'], CAM['TY']
    a = (HEAD_PIN[0] - TX) * math.sqrt(2) / S                 # X + Y
    b = (TY - HEAD_PIN[1]) * math.sqrt(6) / S                 # -X + Y + 2Z
    # X = x + s hx c, Y = y + s hx s_, Z = s hz
    hx = (a - D['x'] - D['y']) / (D['s'] * (c + s_))
    X, Y = D['x'] + D['s'] * hx * c, D['y'] + D['s'] * hx * s_
    hz = (b + X - Y) / 2 / D['s']
    return dict(D, hx=hx, hz=hz, hr=HEAD_PIN[2] / D['s'])


def score(D, detail=False):
    if D.get('pin'):
        D = pin_head(D)
    Lm = paint(D)
    M = inked(Lm > 0)
    sil = (M & SIL).sum() / max((M | SIL).sum(), 1)
    b = Lm == 3
    keep = (distance_transform_edt(b) > R_INT) & (distance_transform_edt(Lm > 0) > R_OUT)
    bm = b & keep; beak = (bm & BEAK).sum() / max((bm | BEAK).sum(), 1)
    hb = (Lm == 2) & ((np.roll(Lm, 1, 0) == 1) | (np.roll(Lm, -1, 0) == 1) | (np.roll(Lm, 1, 1) == 1) | (np.roll(Lm, -1, 1) == 1))
    if hb.any():
        dt = distance_transform_edt(~hb); ix = np.clip(NECK.astype(int), 0, np.array(dt.shape[::-1]) - 1)
        neck = float(dt[ix[:, 1], ix[:, 0]].mean())
    else:
        neck = 60.0
    s = sil + 0.5 * beak - 0.01 * neck
    return (s, dict(sil=round(sil, 4), beak=round(beak, 4), neck=round(neck, 2))) if detail else s


def view(D, path):
    if D.get('pin'):
        D = pin_head(D)
    Lm = paint(D); M = inked(Lm > 0)
    vis = np.zeros(Lm.shape + (3,), np.uint8)
    vis[SIL] = (120, 200, 120); vis[M & ~SIL] = (230, 80, 80); vis[M & SIL] = (60, 110, 60)
    vis[Lm == 2] = vis[Lm == 2] // 2 + np.array([60, 60, 0], np.uint8)
    vis[Lm == 3] = (240, 150, 60); vis[BEAK & (Lm != 3)] = (160, 60, 20)
    for p in NECK.astype(int):
        if 0 <= p[1] < vis.shape[0] and 0 <= p[0] < vis.shape[1]:
            vis[p[1], p[0]] = (255, 255, 255)
    for e in (EYE_N, EYE_F):
        vis[int(e[1]) - 1:int(e[1]) + 2, int(e[0]) - 1:int(e[0]) + 2] = (255, 0, 255)
    Image.fromarray(vis).resize((vis.shape[1] * 2, vis.shape[0] * 2), Image.NEAREST).save(path)


KEYS = ['x', 'y', 'yaw', 's', 'rxf', 'rxb', 'ry', 'rz', 'tail', 'tp', 'tw', 'fb', 'hx', 'hz', 'hr', 'hsz', 'hsx', 'kd', 'kzr', 'krx', 'kry', 'krz', 'kup', 'kw', 'kp']
LO = dict(x=1.0, y=-0.4, yaw=0, s=0.6, rxf=0.12, rxb=0.12, ry=0.1, rz=0.1, tail=0.0, tp=1.0, tw=0.0, fb=0.3, hx=-0.05, hz=0.25, hr=0.08, hsz=0.8, hsx=0.8,
          kd=0.5, kzr=-0.9, krx=0.05, kry=0.03, krz=0.012, kup=0.0, kw=0.0, kp=-10.0)
HI = dict(x=1.6, y=0.3, yaw=80, s=1.3, rxf=0.4, rxb=0.4, ry=0.35, rz=0.3, tail=0.45, tp=4.0, tw=0.7, fb=1.0, hx=0.25, hz=0.6, hr=0.2, hsz=1.2, hsx=1.5,
          kd=2.2, kzr=0.4, krx=0.2, kry=0.14, krz=0.07, kup=0.06, kw=0.8, kp=45.0)

if __name__ == '__main__':
    D = dict(DUCK_G)
    if len(sys.argv) > 1 and sys.argv[1].endswith('.json'):
        D.update(json.load(open(sys.argv[1])))
    s, det = score(D, True); print('start %.4f' % s, det, flush=True); view(D, 'duck_fit2_start.png')
    lo = np.array([LO[k] for k in KEYS]); hi = np.array([HI[k] for k in KEYS])
    def unpack(x):
        Q = dict(D); Q.update({k: float(v) for k, v in zip(KEYS, np.clip(x, lo, hi))}); return Q
    from best_powell import best_powell
    rounds = int(sys.argv[2]) if len(sys.argv) > 2 else 3
    x0, _ = best_powell(lambda x: -score(unpack(x)), np.clip([D[k] for k in KEYS], lo, hi), lo, hi, rounds, log=lambda m: print(m, flush=True))
    D = unpack(x0); s, det = score(D, True)
    out = sys.argv[3] if len(sys.argv) > 3 else 'duck_fit2'
    json.dump(D, open(out + '.json', 'w'), indent=1); view(D, out + '.png')
    print('final %.4f' % s, det); print({k: round(v, 4) for k, v in D.items()})
