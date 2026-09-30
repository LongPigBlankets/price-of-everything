"""v13: the duck's back and tail against the shipped duck's top edge in the render's 800 px frame, on the true
silhouette (no ink widening, which had filled the v11/v12 notch in), with no dip (review v12: the dip dented the
shading), scored for one smooth peak falling to the neck."""
import json, math, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import label
sys.path.insert(0, '../source')
from duck_geom import *
from best_powell import best_powell
C = json.load(open('cam800_v10.json')); K8, OX, OY = C['k'], C['ox'], C['oy']
R = np.array([1, 1, 0]) / math.sqrt(2); V = np.array([1, -1, 1]) / math.sqrt(3); U = np.cross(V, R); U /= np.linalg.norm(U)
def s800(W): return np.stack([W @ R * K8 + OX, -(W @ U) * K8 + OY], -1)
ref = np.load('../../adv_rubber_v10/ref_duckfill.npy'); lab, n = label(ref); sz = np.bincount(lab.ravel()); sz[0] = 0; ref = lab == np.argmax(sz)
XS = np.arange(342, 410, 2)
REF_T = np.array([np.where(ref[:, x])[0].min() if ref[:, x].any() else np.nan for x in XS], float)
GX, GY, GZ = dg_grid(160, 80)
def top_edge(D):
    place = dg_place(D); img = Image.new('L', (800, 800), 0); d = ImageDraw.Draw(img)
    for fn in (dg_body_local, dg_head_local):
        s = s800(place(*fn(D, GX, GY, GZ)))
        for i in range(s.shape[0] - 1):
            for j in range(s.shape[1]):
                j2 = (j + 1) % s.shape[1]; d.polygon([tuple(s[i, j]), tuple(s[i, j2]), tuple(s[i + 1, j2]), tuple(s[i + 1, j])], fill=255)
    M = np.array(img) > 0
    return np.array([np.where(M[:, x])[0].min() if M[:, x].any() else np.nan for x in XS], float) + 6.0   # fill = silhouette + half the outline
def score(D, detail=False):
    t = top_edge(D); e = np.nanmean(np.abs(t - REF_T))
    dt = np.diff(t); rough = np.nanmean(np.abs(np.diff(dt)))
    tops = int(np.sum((dt[:-1] < -0.6) & (dt[1:] > 0.6)))            # local tops (y down)
    bottoms = int(np.sum((dt[:-1] > 0.6) & (dt[1:] < -0.6)))         # notches
    s = -e - 1.5 * rough - 4.0 * bottoms - 2.0 * max(0, tops - 1)
    return (s, dict(err=round(float(e), 2), rough=round(float(rough), 2), tops=tops, notches=bottoms)) if detail else s
D = json.load(open(sys.argv[1])); D.update(dip=0.0, chest=0.03, chest_w=0.08, chest_x=0.2, tx0=0.0)
print('start', score(D, True))
keys = ['tail', 'tp', 'rxb', 'tw', 'tx0']
lo = np.array([0.10, 0.8, 0.22, 0.0, -0.10]); hi = np.array([0.45, 3.5, 0.34, 0.6, 0.12])
def unpack(x):
    Q = dict(D); Q.update({k: float(v) for k, v in zip(keys, np.clip(x, lo, hi))}); return Q
best = None
for tp in (1.0, 1.4, 1.9):
    for tail in (0.2, 0.28, 0.36):
        for tx0 in (-0.05, 0.03):
            Q = dict(D, tp=tp, tail=tail, tx0=tx0); v = score(Q)
            if best is None or v > best[0]: best = (v, Q)
D = best[1]; print('grid', score(D, True), {k: D[k] for k in keys})
x0, _ = best_powell(lambda x: -score(unpack(x)), np.clip([D[k] for k in keys], lo, hi), lo, hi, 2, log=print)
Q = unpack(x0); print('final', score(Q, True), {k: round(Q[k], 4) for k in keys})
print('ref ', REF_T.astype(int).tolist()); print('fit ', np.round(top_edge(Q)).astype(int).tolist())
json.dump(Q, open('duck_v13.json', 'w'), indent=1)
