"""Fit the fertiliser bag's shape parameters to the shipped bag's silhouette (shape only: both masks are
normalised to equal area and aligned centroids, then compared by IoU)."""
import math, json, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi, optimize

im = np.array(Image.open('reference/g_064_fertilisers.png').convert('RGB')).astype(int)
r, g, b = im[..., 0], im[..., 1], im[..., 2]
green = (g > r + 18) & (g > b + 8)
lab, n = ndi.label(green)
keep = np.zeros_like(green)
for k in range(1, n + 1):
    ys, xs = np.where(lab == k)
    if len(xs) > 1500 and xs.mean() < 800 and ys.mean() > 950 and xs.min() > 120:
        keep |= lab == k
bag = ndi.binary_fill_holes(ndi.binary_closing(keep, structure=np.ones((41, 41))))
ys, xs = np.where(bag)
print('ref bag bbox', xs.min(), ys.min(), xs.max(), ys.max(), 'area', int(bag.sum()))
Image.fromarray((bag * 255).astype('uint8')).save('ref_bag_mask.png')

RIGHT = np.array([1, 1, 0]) / math.sqrt(2); VIEW = np.array([1, -1, 1]) / math.sqrt(3); UP = np.cross(VIEW, RIGHT); UP /= np.linalg.norm(UP)

def model(P, rows=40, cols=64):
    lean, yaw, T, Hh, pinch, sag, belly, p = P
    W = 1.0; sm = 0.05
    t = np.linspace(0, 1, rows + 1)
    u = (t - sm) / (1 - 2 * sm)
    f = np.where((u > 0) & (u < 1), np.sin(np.pi * np.clip(u, 1e-6, 1) ** sag) ** belly, 0.0)
    a = W / 2 * (1 - pinch * f); bt = np.maximum(0.004, T / 2 * f)
    th = np.linspace(0, 2 * np.pi, cols, endpoint=False)
    c, s = np.cos(th), np.sin(th)
    X = a[:, None] * np.sign(c) * np.abs(c) ** (2 / p)
    Y = bt[:, None] * np.sign(s) * np.abs(s) ** (2 / p)
    Z = (t * Hh)[:, None] * np.ones_like(th)
    l, yw = math.radians(lean), math.radians(yaw)
    Y2 = Y * math.cos(l) + Z * math.sin(l); Z2 = -Y * math.sin(l) + Z * math.cos(l)
    X3 = X * math.cos(yw) - Y2 * math.sin(yw); Y3 = X * math.sin(yw) + Y2 * math.cos(yw)
    V = np.stack([X3, Y3, Z2], -1)
    sx = V @ RIGHT; sy = -(V @ UP)
    return sx, sy

def raster(sx, sy, res=400):
    x0, x1, y0, y1 = sx.min(), sx.max(), sy.min(), sy.max()
    k = (res - 20) / max(x1 - x0, y1 - y0)
    img = Image.new('L', (res, res)); d = ImageDraw.Draw(img)
    R, C = sx.shape
    for i in range(R - 1):
        for j in range(C):
            j2 = (j + 1) % C
            pts = [((sx[i, j] - x0) * k + 10, (sy[i, j] - y0) * k + 10), ((sx[i, j2] - x0) * k + 10, (sy[i, j2] - y0) * k + 10),
                   ((sx[i + 1, j2] - x0) * k + 10, (sy[i + 1, j2] - y0) * k + 10), ((sx[i + 1, j] - x0) * k + 10, (sy[i + 1, j] - y0) * k + 10)]
            d.polygon(pts, fill=255)
    return np.array(img) > 0

def norm(mask, res=300):
    """Scale to a fixed area, centre the centroid."""
    ys, xs = np.where(mask); area = len(xs); cy, cx = ys.mean(), xs.mean()
    k = math.sqrt(0.30 * res * res / area)
    out = np.zeros((res, res), bool)
    yy, xx = np.mgrid[0:res, 0:res]
    sy = (yy - res / 2) / k + cy; sx = (xx - res / 2) / k + cx
    inside = (sy >= 0) & (sy < mask.shape[0]) & (sx >= 0) & (sx < mask.shape[1])
    out[inside] = mask[sy[inside].astype(int), sx[inside].astype(int)]
    return out

REF = norm(bag)

def score(P):
    sx, sy = model(P)
    m = norm(raster(sx, sy))
    return (m & REF).sum() / (m | REF).sum()

names = ['lean', 'yaw', 'T', 'H', 'pinch', 'sag', 'belly', 'p']
v7 = [15.0, 3.0, 0.48 / 0.74, 0.86 / 0.74, 0.13, 0.85, 0.55, 2.15]
print('v7 IoU', round(score(v7), 4))
lo = np.array([0, -25, 0.10, 0.9, -0.15, 0.5, 0.2, 1.6]); hi = np.array([45, 25, 0.9, 1.9, 0.3, 1.6, 1.2, 4.0])
rng = np.random.default_rng(3); best = (score(v7), list(v7))
for i in range(260):
    P = lo + (hi - lo) * rng.random(8)
    sc = score(P)
    if sc > best[0]:
        best = (sc, list(P))
print('random best', round(best[0], 4), dict(zip(names, np.round(best[1], 3))))
res = optimize.minimize(lambda P: -score(np.clip(P, lo, hi)), best[1], method='Nelder-Mead', options={'maxiter': 500, 'xatol': 1e-3, 'fatol': 1e-4})
P = np.clip(res.x, lo, hi)
print('refined', round(score(P), 4), dict(zip(names, np.round(P, 3))))
json.dump({'iou': score(P), 'params': dict(zip(names, [float(x) for x in P])), 'v7_iou': score(v7)}, open('bag_fit.json', 'w'), indent=2)
sx, sy = model(P); m = norm(raster(sx, sy))
vis = np.zeros(REF.shape + (3,), 'uint8'); vis[REF] = (120, 200, 120); vis[m & ~REF] = (230, 80, 80); vis[m & REF] = (60, 110, 60)
Image.fromarray(vis).resize((450, 450), Image.Resampling.NEAREST).save('bag_fit_overlay.png')
sx, sy = model(v7); m7 = norm(raster(sx, sy))
vis = np.zeros(REF.shape + (3,), 'uint8'); vis[REF] = (120, 200, 120); vis[m7 & ~REF] = (230, 80, 80); vis[m7 & REF] = (60, 110, 60)
Image.fromarray(vis).resize((450, 450), Image.Resampling.NEAREST).save('bag_fit_overlay_v7.png')
