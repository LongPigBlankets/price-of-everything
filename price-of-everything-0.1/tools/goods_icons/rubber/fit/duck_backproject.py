"""Trace the shipped duck's interior ink (eyes, neck line, mouth line, wing, feathers) and carry it onto the
fitted duck (duck_fit2g.json + the pinned head) through the camera: each stroke's centre line (the geodesic
diameter of its pixels, smoothed), or an eye's outline, back-projected onto the front-most surface of the
part it belongs to. Writes duck_strokes.json: polylines in the duck's own frame (before its scale), for
rubber_kit.rb_duck."""
import json, math, sys
from collections import deque
import numpy as np
from scipy.ndimage import binary_erosion
sys.path.insert(0, '../source')
from duck_geom import *
import duck_fit2 as F

D = F.pin_head(json.load(open(sys.argv[1] if len(sys.argv) > 1 else 'duck_fit2g.json')))
C = F.CAM; S, TX, TY = C['S'], C['TX'], C['TY']
LAB = np.load('duck_ink_lab2.npy')          # full-res labels of the interior ink (duck_ink_lab2.png)
VIEWV = np.array([1.0, -1.0, 1.0]) / math.sqrt(3)
RIGHT = np.array([1.0, 1.0, 0.0]) / math.sqrt(2); UP = np.cross(VIEWV, RIGHT); UP /= np.linalg.norm(UP)


def scr(p):
    p = np.asarray(p); return np.stack([p @ RIGHT * S + TX, -(p @ UP) * S + TY], -1)


def geodesic_path(mask):
    ys, xs = np.where(mask); pts = set(zip(ys.tolist(), xs.tolist()))
    def bfs(src):
        par = {src: None}; q = deque([src]); last = src
        while q:
            u = q.popleft(); last = u
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    v = (u[0] + dy, u[1] + dx)
                    if v in pts and v not in par:
                        par[v] = u; q.append(v)
        return last, par
    a, _ = bfs(next(iter(pts))); b, par = bfs(a)
    path = [b]
    while par[path[-1]] is not None:
        path.append(par[path[-1]])
    P = np.array([(x, y) for y, x in path], float)
    k = 9; Ps = np.array([P[max(0, i - k):i + k + 1].mean(0) for i in range(len(P))])   # smooth
    return Ps[::6] if len(Ps) > 12 else Ps


def blob_loop(mask, n=24):
    ys, xs = np.where(mask & ~binary_erosion(mask)); c = np.array([xs.mean(), ys.mean()])
    ang = np.arctan2(ys - c[1], xs - c[0]); out = []
    for a in np.linspace(-np.pi, np.pi, n, endpoint=False):
        d = np.abs(np.angle(np.exp(1j * (ang - a)))); k = np.argsort(d)[:3]
        out.append(np.array([xs[k].mean(), ys[k].mean()]))
    return np.array(out)


def samples(part, nu=360, nv=180):
    GX, GY, GZ = dg_grid(nu, nv); place = dg_place(D)
    if part == 'body':
        L = dg_body_local(D, GX, GY, GZ)
    elif part == 'head':
        L = dg_head_local(D, GX, GY, GZ)
    else:
        L = dg_bill_local(D, GX, GY, GZ)
    Pw = place(*L); Ll = np.stack(L, -1)
    # normals from the grid
    du = np.roll(Pw, -1, 1) - np.roll(Pw, 1, 1); dv = np.gradient(Pw, axis=0)
    n = np.cross(du, dv); c = Pw.reshape(-1, 3).mean(0); n *= np.sign(((Pw - c) * n).sum(-1, keepdims=True) + 1e-12)
    return Pw.reshape(-1, 3), Ll.reshape(-1, 3), n.reshape(-1, 3)


CACHE = {}
def backproject(pts_half, part):
    if part not in CACHE:
        Pw, Ll, n = samples(part); vis = n @ VIEWV > 0
        CACHE[part] = (scr(Pw[vis]), Ll[vis], Pw[vis] @ VIEWV)
    s2, Ll, dep = CACHE[part]; out = []
    for p in pts_half:
        d = np.hypot(*(s2 - p).T)
        for r in (1.0, 1.6, 2.5, 4.0):
            k = np.where(d < r)[0]
            if len(k):
                break
        if not len(k):
            continue
        out.append(Ll[k[np.argmax(dep[k])]])
    return np.array(out)


STROKES = {'eye_near': ([2], 'head', 'loop'), 'eye_far': ([1], 'head', 'loop'), 'neck': ([4], 'head', 'path'),
           'mouth': ([5, 6], 'bill', 'path'), 'wing': ([7, 9, 10], 'body', 'path'), 'feather': ([8], 'body', 'path')}
out = {}
for name, (ks, part, kind) in STROKES.items():
    m = np.isin(LAB, ks)
    if kind == 'path' and len(ks) > 1:              # bridge the small gaps between a stroke's pieces
        from scipy.ndimage import binary_dilation
        m = binary_dilation(m, iterations=5)
    P = blob_loop(m) if kind == 'loop' else geodesic_path(m)
    ph = P / 2.0                                      # half-res, the camera's frame
    L = backproject(ph, part)
    out[name] = dict(part=part, closed=kind == 'loop', pts=[[round(float(v), 5) for v in p] for p in L])
    print(name, part, len(P), '->', len(L))
json.dump(out, open('duck_strokes.json', 'w'), indent=1)
