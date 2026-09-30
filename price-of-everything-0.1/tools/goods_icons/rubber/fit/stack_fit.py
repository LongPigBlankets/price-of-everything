"""Fit the rubber stack (folded and flat sheets, as rb_stack builds them) to the shipped stack's inked
silhouette, the boots and the duck as don't-care; also fixes the camera (S, TX, TY) for rubber."""
import json, math, sys, time
import numpy as np
from PIL import Image, ImageDraw
from scipy import optimize
from scipy.ndimage import binary_dilation
from rfit_common import *

KINDS = ['thin', 'thin', 'thin', 'fold', 'thin', 'thin', 'fold', 'thin', 'thin', 'fold', 'thin', 'top']
INS = [(0.02, 0.00, 0.01, 0.00), (0.00, 0.02, 0.00, 0.02), (0.01, 0.01, 0.02, 0.00), (-0.02, -0.02, 0.00, 0.01), (0.01, 0.00, 0.01, 0.01),
       (0.00, 0.01, 0.00, 0.00), (-0.025, -0.01, 0.01, 0.00), (0.00, 0.00, 0.00, 0.01), (0.01, 0.01, 0.01, 0.00), (-0.015, -0.02, 0.00, 0.01),
       (0.00, 0.01, 0.01, 0.00), (0.00, 0.00, 0.00, 0.00)]

def layers(P):
    out = []; z = 0.0
    for kind, (xi0, xi1, yi0, yi1) in zip(KINDS, INS):
        t = P['thin'] if kind == 'thin' else P['fold'] if kind == 'fold' else P['top']
        fo = P['fold_out'] / 0.02 if kind == 'fold' else 1.0
        x0, x1, y0, y1 = xi0 * fo, P['SX'] - xi1 * fo, yi0, P['SY'] - yi1
        if kind == 'fold':
            r = t / 2; ol = []
            for k in range(13):
                a = math.radians(90 + 180 * k / 12); ol.append((x0 + r + r * math.cos(a), z + r + r * math.sin(a)))
            for k in range(13):
                a = math.radians(-90 + 180 * k / 12); ol.append((x1 - r + r * math.cos(a), z + r + r * math.sin(a)))
        else:
            ol = [(x0, z), (x1, z), (x1, z + t), (x0, z + t)]
        out.append((np.array(ol), y0, y1)); z += t + 0.004
    return out

def raster(P, C):
    img = Image.new('L', (SHAPE[1], SHAPE[0]), 0); d = ImageDraw.Draw(img)
    for ol, y0, y1 in layers(P):
        A = np.column_stack([ol[:, 0], np.full(len(ol), y0), ol[:, 1]]); B = np.column_stack([ol[:, 0], np.full(len(ol), y1), ol[:, 1]])
        a2, b2 = project(A, C), project(B, C)
        poly(d, a2); poly(d, b2)
        for k in range(len(ol)):
            k2 = (k + 1) % len(ol); poly(d, (a2[k], a2[k2], b2[k2], b2[k]))
    return inked(np.array(img) > 0)

DC = binary_dilation(BOOTS | DUCK, iterations=4); CARE = ~DC
if __name__ == '__main__':
    P = dict(SX=1.00, SY=1.41, thin=0.040, fold=0.125, top=0.050, fold_out=0.02)
    C = dict(S=300.0, TX=300.0, TY=600.0)
    # initial camera from the bounding boxes
    M = raster(P, dict(S=100.0, TX=400.0, TY=500.0))
    ys, xs = np.where(M); ry, rx = np.where(STACK)
    k = (rx.max() - rx.min()) / (xs.max() - xs.min()); C['S'] = 100.0 * k
    C['TX'] = rx.min() - (xs.min() - 400.0) * k; C['TY'] = ry.min() - (ys.min() - 500.0) * k
    keys = ['SY', 'thin', 'fold', 'top', 'fold_out', 'S', 'TX', 'TY']
    lo = np.array([1.0, 0.02, 0.06, 0.02, 0.0, C['S'] * 0.8, C['TX'] - 60, C['TY'] - 60]); hi = np.array([2.0, 0.08, 0.2, 0.1, 0.06, C['S'] * 1.25, C['TX'] + 60, C['TY'] + 60])
    def unpack(x):
        x = np.clip(x, lo, hi); Q = dict(P); Q.update({k: float(v) for k, v in zip(keys[:5], x[:5])}); return Q, dict(S=x[5], TX=x[6], TY=x[7])
    f = lambda x: -iou(raster(*unpack(x)), STACK, CARE)
    x0 = np.clip(np.array([P[k] for k in keys[:5]] + [C['S'], C['TX'], C['TY']]), lo, hi)
    t = time.time(); print('start %.4f' % -f(x0), flush=True)
    for rnd in range(3):
        res = optimize.minimize(f, x0, method='Powell', bounds=list(zip(lo, hi)), options={'xtol': 1e-4, 'ftol': 1e-6})
        x0 = res.x; print('round', rnd, 'IoU %.4f' % -res.fun, '%.0fs' % (time.time() - t), flush=True)
    P, C = unpack(x0)
    json.dump(dict(P=P, C={k: float(v) for k, v in C.items()}), open('stack_fit.json', 'w'), indent=1)
    M = raster(P, C); vis = np.zeros(SHAPE + (3,), 'uint8')
    vis[STACK & CARE] = (120, 200, 120); vis[M & ~STACK & CARE] = (230, 80, 80); vis[M & STACK & CARE] = (60, 110, 60); vis[DC] = (70, 70, 90)
    Image.fromarray(vis).save('stack_fit.png'); print(P, C)
