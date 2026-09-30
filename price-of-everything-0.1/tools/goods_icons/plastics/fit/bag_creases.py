"""Back-project the shipped bag's crease lines (full-res screen polylines) onto the fitted bag's
front surface: each point -> the visible (t, theta) of the body under it."""
import json, math, sys
import numpy as np
from chair_fit2 import project, VIEW
import bag_fit as bf
cam = json.load(open(sys.argv[1])); G = dict(bf.G0); G.update(json.load(open(sys.argv[2]))); G['s2'] = float(sys.argv[3])
C = {k: cam[k] for k in ('S', 'TX', 'TY')}
a, b, rim = bf.body_fns(G); p = G['pe']; Rz = bf.rot(G); O = np.array([G['bx'], G['by'], 0.0])
T, TH = np.meshgrid(np.linspace(0, 1, 400), np.linspace(-math.pi, math.pi, 720), indexing='ij')
c, s = np.cos(TH), np.sin(TH)
X = a(T) * np.sign(c) * np.abs(c) ** (2 / p); Y = b(T) * np.sign(s) * np.abs(s) ** (2 / p); Z = T * rim(TH)
W = np.stack([X, Y, Z], -1) @ Rz.T + O
S2 = project(W, C) * 2; D = W @ VIEW
CREASES = {
    'smile': [(990, 1287), (1040, 1305), (1100, 1321), (1160, 1330), (1210, 1318), (1240, 1290), (1258, 1262)],
    'right': [(1308, 1318), (1290, 1365), (1270, 1415), (1252, 1462)],
    'left': [(872, 1185), (878, 1250), (878, 1320), (872, 1400), (870, 1470), (878, 1512)],
    'foot': [(842, 1546), (890, 1560), (940, 1573), (1000, 1586)],
    'foot2': [(835, 1480), (858, 1508), (878, 1530)],
}
out = {}
for name, pts in CREASES.items():
    res = []
    for (sx, sy) in pts:
        d = np.hypot(S2[..., 0] - sx, S2[..., 1] - sy)
        near = d < max(2.5, d.min() + 1.0)
        i, j = np.unravel_index(np.argmax(np.where(near, D, -1e9)), d.shape)
        res.append((float(T[i, j]), float(TH[i, j]))); 
    out[name] = res
    print(name, [(round(t, 3), round(math.degrees(th), 1)) for t, th in res])
json.dump(out, open('bag_creases.json', 'w'), indent=1)
