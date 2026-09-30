"""Silhouette fit of the plastics chair, v2: the shared geometry (source/chair_geom.py), rasterised with
the exporter's ink (12 px outer band centred on the silhouette, 6 px round enclosed openings), holes
seen through the web's thickness (front and back outlines intersected), scored as IoU against the
shipped chair's inked silhouette outside the bag and bottle."""
import json, math, sys, time
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import binary_fill_holes, distance_transform_edt, label as cc_label
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'source'))
from chair_geom import *   # noqa

SQ2, SQ3 = math.sqrt(2), math.sqrt(3)
VIEW = np.array([1, -1, 1]) / SQ3
RIGHT = np.array([1, 1, 0]) / SQ2
UP = np.cross(VIEW, RIGHT); UP /= np.linalg.norm(UP)
PX800 = 736.0 / 1638.0 * 2.0            # px at 800 per half-res reference px
R_OUT, R_HOLE = 6.0 / PX800, 3.0 / PX800

REF = np.load(HERE / 'ref_chair.npy'); DC = np.load(HERE / 'ref_dontcare.npy'); CARE = ~DC
SHAPE = REF.shape


def project(p, P):
    p = np.asarray(p)
    return np.stack([p @ RIGHT * P['S'] + P['TX'], -(p @ UP) * P['S'] + P['TY']], -1)


def _poly(d, pts):
    d.polygon([(float(x), float(y)) for x, y in pts], fill=255)


def layers(P, shape=SHAPE):
    """Boolean masks (no ink): the union of the parts, and the slots' visible holes."""
    Hh, Ww = shape
    rings, i0, i1, U, Q, zb, zt = cg_shell(P)
    R2 = project(rings, P); m = R2.shape[1]
    L = cg_arc(U)
    sl = cg_slots(P, U, Q) if P.get('slots_on', 1) else []
    main = Image.new('L', (Ww, Hh), 0); dm = ImageDraw.Draw(main)
    lay = [Image.new('L', (Ww, Hh), 0) for _ in sl]; dl = [ImageDraw.Draw(x) for x in lay]
    for i in range(len(R2) - 1):
        tgt = dm
        if i0 <= i < i1 - 1:
            s_mid = (L[i - i0] + L[i + 1 - i0]) / 2; best = None
            for k, (_, _, (a, b)) in enumerate(sl):
                if a - 0.07 <= s_mid <= b + 0.07:
                    dd = abs(s_mid - (a + b) / 2)
                    if best is None or dd < best[0]:
                        best = (dd, k)
            if best:
                tgt = dl[best[1]]
        for k in range(m):
            k2 = (k + 1) % m
            _poly(tgt, (R2[i, k], R2[i, k2], R2[i + 1, k2], R2[i + 1, k]))
    for rr in cg_rim(P, U, Q, zb, zt):
        r2 = project(rr, P); mm = r2.shape[1]
        for i in range(len(r2) - 1):
            for k in range(mm):
                k2 = (k + 1) % mm
                _poly(dm, (r2[i, k], r2[i, k2], r2[i + 1, k2], r2[i + 1, k]))
        _poly(dm, r2[0]); _poly(dm, r2[-1])
    ring, ztop, z0, (bp, fp), _ = cg_seat_solid(P, U, Q)
    top = np.column_stack([ring, ztop]); bot = np.column_stack([ring, np.full(len(ring), z0)])
    _poly(dm, project(top[bp], P)); _poly(dm, project(top[fp], P)); _poly(dm, project(bot, P))
    for k in range(len(top)):
        k2 = (k + 1) % len(top)
        _poly(dm, project(np.array([top[k], top[k2], bot[k2], bot[k]]), P))
    for vs, fs in cg_back_legs(P):
        v2 = project(vs, P)
        for f in fs:
            _poly(dm, v2[list(f)])
    for sy, vs, fs in cg_fins(P) + cg_skirts(P):
        v2 = project(vs, P)
        for f in fs:
            _poly(dm, v2[list(f)])
    M = np.array(main) > 0
    holes = []
    for k, (fr, bk, _) in enumerate(sl):
        a = Image.new('L', (Ww, Hh), 0); _poly(ImageDraw.Draw(a), project(fr, P))
        b = Image.new('L', (Ww, Hh), 0); _poly(ImageDraw.Draw(b), project(bk, P))
        h = (np.array(a) > 0) & (np.array(b) > 0)
        M |= (np.array(lay[k]) > 0) & ~h
        holes.append(h)
    return M, holes


def inked(M):
    filled = binary_fill_holes(M)
    vis = distance_transform_edt(~filled) <= R_OUT
    holes = filled & ~M
    if holes.any():
        vis &= ~(distance_transform_edt(holes) > R_HOLE)
    return vis


def raster(P, shape=SHAPE):
    return inked(layers(P, shape)[0])


def iou(P, care=None):
    care = CARE if care is None else care
    M = raster(P)
    inter = (M & REF & care).sum(); union = ((M | REF) & care).sum()
    return inter / max(union, 1)


def overlay(P, path, scale=1, care=None):
    care = CARE if care is None else care
    M = raster(P)
    vis = np.zeros(SHAPE + (3,), 'uint8')
    vis[REF & care] = (120, 200, 120); vis[M & ~REF & care] = (230, 80, 80); vis[M & REF & care] = (60, 110, 60); vis[~care] = (70, 70, 90)
    im = Image.fromarray(vis)
    if scale != 1:
        im = im.resize((SHAPE[1] * scale, SHAPE[0] * scale), Image.NEAREST)
    im.save(path)


def shipped_holes():
    """The shipped chair's enclosed openings: [(area, centroid (x, y), axis unit, half-length, half-width, mask)]."""
    holes = binary_fill_holes(REF) & ~REF & CARE
    lab, n = cc_label(holes); out = []
    for k in range(1, n + 1):
        ys, xs = np.where(lab == k)
        if len(xs) < 30:
            continue
        c = np.array([xs.mean(), ys.mean()]); X = np.column_stack([xs, ys]) - c
        w, v = np.linalg.eigh(X.T @ X / len(xs)); a = v[:, 1]
        if a[1] > 0:
            a = -a                                    # the axis points up the screen
        with np.errstate(all="ignore"):
            pr = X @ a; pp = X @ np.array([-a[1], a[0]])
        out.append(dict(area=len(xs), c=c, axis=a, hl=(pr.max() - pr.min()) / 2, hw=(pp.max() - pp.min()) / 2,
                        mid=(pr.max() + pr.min()) / 2, mask=lab == k))
    return sorted(out, key=lambda d: -d['area'])
