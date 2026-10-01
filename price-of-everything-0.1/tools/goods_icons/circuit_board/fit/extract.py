"""Read the shipped board's copper off board_uv.png: trace centrelines (Zhang-Suen thinning, traced into polylines,
Douglas-Peucker simplified), vias (dark holes inside gold rings), pads (thick gold, outlined), the connector fingers.
Writes copper.json in board coordinates (u, v in [0, 1] over the top face).    python3 extract.py"""
import json
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
LO, HI, N = -0.25, 1.05, 1300; PX = (HI - LO) / (N - 1)
im = np.asarray(Image.open('board_uv.png').convert('RGB')).astype(int); R, G, Bc = im[..., 0], im[..., 1], im[..., 2]
def uv(c, r): return (LO + c * PX, HI - r * PX)
gold = (R > 160) & (Bc < 150) & (R > G)
navy = (R < 70) & (G < 70) & (Bc < 110)
cc, rr = np.meshgrid(np.arange(N), np.arange(N)); U, V = uv(cc, rr)
board = (U > 0.012) & (U < 0.985) & (V > 0.03) & (V < 0.985)
gold = ndi.binary_opening(gold, iterations=1)
faint = (R > 130) & (Bc < 150) & (R > G + 5)                 # the art's faded runs of copper
gold = (gold | (ndi.binary_closing(gold | faint, iterations=4) & ndi.binary_dilation(gold, iterations=8))) & board
gold = ndi.binary_opening(gold, iterations=2) & board
# vias: small navy blobs ringed by gold
lab, n = ndi.label(navy & board); vias = []
for k in range(1, n + 1):
    ys, xs = np.where(lab == k)
    if not (30 < len(xs) < 900): continue
    cy, cx = ys.mean(), xs.mean(); r_hole = np.sqrt(len(xs) / np.pi)
    ring = gold[max(0, int(cy) - 30):int(cy) + 31, max(0, int(cx) - 30):int(cx) + 31]
    if ring.sum() < 200: continue
    vias.append(dict(c=uv(cx, cy), r_hole=float(r_hole * PX)))
# measure the ring's outer radius on the gold around each hole
for v_ in vias:
    cx, cy = (v_['c'][0] - LO) / PX, (HI - v_['c'][1]) / PX; best = 0
    for rpx in range(8, 30):
        ang = np.linspace(0, 2 * np.pi, 48, endpoint=False); px = (cx + rpx * np.cos(ang)).astype(int); py = (cy + rpx * np.sin(ang)).astype(int)
        if gold[py, px].mean() > 0.5: best = rpx
    v_['r_out'] = float(best * PX)
# pads: gold components whose thickness (distance transform) exceeds a trace's
dt = ndi.distance_transform_edt(gold); lab, n = ndi.label(gold); pads = []; thin = gold.copy()
for k in range(1, n + 1):
    m = lab == k
    if dt[m].max() > 10:                                   # traces are ~6 px half width
        thick = m & ndi.binary_dilation(dt > 9, iterations=10)
        thin &= ~thick
        sub, ns = ndi.label(thick)
        for j in range(1, ns + 1):
            ys, xs = np.where(sub == j)
            if len(xs) < 300: continue
            pads.append(dict(box=[*uv(xs.min(), ys.max()), *uv(xs.max(), ys.min())], area=int(len(xs))))
# the rings of the vias are not traces: remove gold within r_out + 2 px of each via
for v_ in vias:
    cx, cy = (v_['c'][0] - LO) / PX, (HI - v_['c'][1]) / PX
    thin &= (cc - cx) ** 2 + (rr - cy) ** 2 > ((v_['r_out'] / PX) + 1) ** 2
# Zhang-Suen thinning
def zs(img):
    img = img.copy().astype(np.uint8)
    while True:
        changed = False
        for step in (0, 1):
            P = np.pad(img, 1); p2, p3, p4, p5, p6, p7, p8, p9 = (P[:-2, 1:-1], P[:-2, 2:], P[1:-1, 2:], P[2:, 2:], P[2:, 1:-1], P[2:, :-2], P[1:-1, :-2], P[:-2, :-2])
            nb = p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9
            seq = [p2, p3, p4, p5, p6, p7, p8, p9, p2]; A = sum(((seq[i] == 0) & (seq[i + 1] == 1)).astype(int) for i in range(8))
            c1 = (p2 * p4 * p6 == 0) if step == 0 else (p2 * p4 * p8 == 0)
            c2 = (p4 * p6 * p8 == 0) if step == 0 else (p2 * p6 * p8 == 0)
            rem = (img == 1) & (nb >= 2) & (nb <= 6) & (A == 1) & c1 & c2
            if rem.any(): img[rem] = 0; changed = True
        if not changed: return img.astype(bool)
sk = zs(thin)
# trace the skeleton into polylines between endpoints and junctions
nbrs = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
pts = set(zip(*np.where(sk)))
def neigh(p): return [(p[0] + a, p[1] + b) for a, b in nbrs if (p[0] + a, p[1] + b) in pts]
deg = {p: len(neigh(p)) for p in pts}; nodes = {p for p, d in deg.items() if d != 2}
used = set(); lines = []
def walk(a, b):
    path = [a, b]; used.add(frozenset((a, b)))
    while path[-1] not in nodes:
        nx = [q for q in neigh(path[-1]) if frozenset((path[-1], q)) not in used and q != path[-2]]
        if not nx: break
        used.add(frozenset((path[-1], nx[0]))); path.append(nx[0])
    return path
for a in nodes:
    for b in neigh(a):
        if frozenset((a, b)) not in used: lines.append(walk(a, b))
for p in pts:                                              # closed loops without nodes
    if deg[p] == 2 and not any(frozenset((p, q)) in used for q in neigh(p)):
        lines.append(walk(p, neigh(p)[0]))
def rdp(P, eps):
    P = np.asarray(P, float)
    if len(P) < 3: return P
    a, b = P[0], P[-1]; d = b - a; L = np.hypot(*d)
    dist = np.abs(np.cross(d, P - a)) / L if L > 1e-9 else np.hypot(*(P - a).T)
    i = int(np.argmax(dist))
    if dist[i] > eps: return np.vstack([rdp(P[:i + 1], eps)[:-1], rdp(P[i:], eps)])
    return np.array([a, b])
traces = []
for L_ in lines:
    if len(L_) < 14: continue                              # skeleton spurs
    P = rdp([(c, r) for r, c in L_], 2.0)
    traces.append([list(uv(c, r)) for c, r in P])
width = float(2 * np.median(dt[sk & (dt > 0)]) * PX)
# fingers: the tab's gold columns
tab = (V < -0.01) & (V > -0.13) & (U > 0.29) & (U < 0.96)
colgold = ((R > 150) & (Bc < 160) & tab).sum(0); fing = []
on = colgold > 25; runs = np.diff(np.r_[0, on.astype(int), 0]); s_ = np.where(runs == 1)[0]; e_ = np.where(runs == -1)[0]
for a, b in zip(s_, e_):
    if b - a >= 4: fing.append([uv(a, 0)[0], uv(b, 0)[0]])
json.dump(dict(pad_polys=json.load(open('copper_v1.json'))['pad_polys'], width=width, traces=traces, vias=vias, pads=pads, fingers=fing), open('copper.json', 'w'), indent=1)
print('width %.4f, %d traces, %d vias, %d pads, %d fingers' % (width, len(traces), len(vias), len(pads), len(fing)))
# check image
chk = Image.open('board_uv.png').convert('RGB'); d = ImageDraw.Draw(chk)
def px(p): return ((p[0] - LO) / PX, (HI - p[1]) / PX)
for t in traces: d.line([px(p) for p in t], fill=(255, 0, 0), width=3)
for v_ in vias:
    x, y = px(v_['c']); r = v_['r_out'] / PX; d.ellipse((x - r, y - r, x + r, y + r), outline=(0, 0, 255), width=3)
for p_ in pads:
    a = px(p_['box'][:2]); b = px(p_['box'][2:]); d.rectangle((a[0], b[1], b[0], a[1]), outline=(255, 0, 255), width=3)
for f in fing:
    d.rectangle(((f[0] - LO) / PX, 1095, (f[1] - LO) / PX, 1230), outline=(0, 160, 255), width=2)
chk.save('copper_check.png')
