"""v11 duck strokes (review v10): the wing as the shipped closed teardrop (the traced lobe kept, its back edge
closed at least 8 px inside the body's outline, the tip where the shipped tip is), two feather strokes inside
it, the eyes scaled to the shipped sizes, the mouth line re-traced to ~9 px from the bill's tip; all designed in
the 800 px frame of the render (fit/cam800_v10.json) and carried onto the new duck's surfaces.
    python3 duck_strokes2.py <duck params json>  ->  duck_strokes2.json"""
import ast, json, math, re, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import binary_fill_holes, distance_transform_edt
sys.path.insert(0, '../source')
from duck_geom import *

D = json.load(open(sys.argv[1]))
src = open('../source/rubber_kit_v10_backup.py').read()      # the strokes traced off the shipped ink (v9), in their own geometry
OLD = ast.literal_eval(src[src.index('DUCK_STROKES = ') + len('DUCK_STROKES = '):].split('\n')[0])
G0 = ast.literal_eval(re.search(r"DUCK_GEOM = (\{.*?\})\n", src, re.S).group(1))
C = json.load(open('cam800_v10.json')); K8, OX, OY = C['k'], C['ox'], C['oy']
R = np.array([1, 1, 0]) / math.sqrt(2); V = np.array([1, -1, 1]) / math.sqrt(3); U = np.cross(V, R); U /= np.linalg.norm(U)


def s800(W):
    W = np.asarray(W); return np.stack([W @ R * K8 + OX, -(W @ U) * K8 + OY], -1)


def surf(D, part, nu=480, nv=240):
    GX, GY, GZ = dg_grid(nu, nv); place = dg_place(D)
    L = {'body': dg_body_local, 'head': dg_head_local, 'bill': dg_bill_local}[part](D, GX, GY, GZ)
    Pw = place(*L); Ll = np.stack(L, -1)
    du = np.roll(Pw, -1, 1) - np.roll(Pw, 1, 1); dv = np.gradient(Pw, axis=0); n = np.cross(du, dv)
    c = Pw.reshape(-1, 3).mean(0); n *= np.sign(((Pw - c) * n).sum(-1, keepdims=True) + 1e-12)
    vis = (n @ V) > 0
    return s800(Pw[vis]), Ll[vis], (Pw[vis] @ V)


def backproject(pts, S):
    s2, Ll, dep = S; out = []
    for p in pts:
        d = np.hypot(*(s2 - p).T)
        for r in (0.5, 0.9, 1.5, 2.5):
            k = np.where(d < r)[0]
            if len(k):
                break
        out.append(Ll[k[np.argmax(dep[k])]] if len(k) else None)
    return [q for q in out if q is not None]


def model_mask(D):
    """The duck's filled silhouette in the 800 frame (body, head, bill)."""
    img = Image.new('L', (800, 800), 0); d = ImageDraw.Draw(img)
    for name, g, c in dg_parts(D, 96, 48):
        s = s800(g)
        for i in range(s.shape[0] - 1):
            for j in range(s.shape[1]):
                j2 = (j + 1) % s.shape[1]
                d.polygon([tuple(s[i, j]), tuple(s[i, j2]), tuple(s[i + 1, j2]), tuple(s[i + 1, j])], fill=255)
    return binary_fill_holes(np.array(img) > 0)


def old_800(nm):
    L = np.array(OLD[nm]['pts']); return s800(dg_place(G0)(L[:, 0], L[:, 1], L[:, 2]))


def resample(P, step=2.0, closed=False):
    P = np.asarray(P, float)
    if closed:
        P = np.vstack([P, P[:1]])
    d = np.r_[0, np.cumsum(np.hypot(*np.diff(P, axis=0).T))]; n = max(2, int(d[-1] / step))
    t = np.linspace(0, d[-1], n, endpoint=not closed)
    return np.column_stack([np.interp(t, d, P[:, 0]), np.interp(t, d, P[:, 1])])


def smooth(P, k=3, closed=False):
    P = np.asarray(P, float); out = P.copy()
    for i in range(len(P)):
        idx = [(i + j) % len(P) if closed else min(max(i + j, 0), len(P) - 1) for j in range(-k, k + 1)]
        out[i] = P[idx].mean(0)
    return out


M = model_mask(D); inside = distance_transform_edt(M)          # px from the duck's outline (the silhouette)

# --- the wing: the traced lobe from its top-most point on, cut where it comes within INSET px of the outline;
#     the back edge follows the body's outline INSET px inside it (>= 8 px of yellow after the 12 px outline)
INSET = 18.0
W = old_800('wing')
itop = int(np.argmin(W[:, 1] + 0.3 * W[:, 0]))                 # the tip: the upper-left extreme
lobe = np.array([p for p in W[itop:] if inside[int(round(p[1])), int(round(p[0]))] >= INSET])
tip = np.array([348.0, 662.0])                                   # the shipped tip (review v10)
end = lobe[-1]
def left_in(y):
    xs = np.where(M[int(round(y))])[0]; x = xs.min()
    while inside[int(round(y)), x] < INSET:
        x += 1
    return x
ys = np.linspace(end[1], tip[1], 36)[1:-1]
back = [np.array([left_in(y), y]) for y in ys]
# blend the back edge into the lobe's end and the tip
loop = np.vstack([tip[None], lobe, np.array(back)])
loop = smooth(resample(loop, 2.0, closed=True), 4, closed=True)
# v12 (review v11: the tip was blunt): pull the points round the tip back onto straight lines into it
it = int(np.argmin(np.hypot(*(loop - tip).T))); n_ = len(loop)
for j in range(1, 6):
    for sgn in (-1, 1):
        q = (it + sgn * j) % n_; w = (6 - j) / 6.0
        loop[q] = loop[q] * (1 - w * 0.8) + (tip + (loop[(it + sgn * 6) % n_] - tip) * j / 6.0) * (w * 0.8)
loop[it] = tip
loop = np.array([p if inside[int(round(p[1])), int(round(p[0]))] >= INSET - 1 else p for p in loop])
print('wing loop', len(loop), 'bbox x %.0f..%.0f y %.0f..%.0f' % (loop[:, 0].min(), loop[:, 0].max(), loop[:, 1].min(), loop[:, 1].max()),
      'min px inside the outline %.1f' % min(inside[int(round(y)), int(round(x))] for x, y in loop))

# --- two feather strokes from the back edge into the wing, square to it and a little down (as shipped)
bpts = smooth(resample(np.array(back[::-1]), 2.0), 2)            # tip -> end along the back edge
feathers = []
for f, L in ((0.36, 15.0), (0.62, 18.0)):
    i = int(len(bpts) * f); a = bpts[i]; t = bpts[min(i + 2, len(bpts) - 1)] - bpts[max(i - 2, 0)]; t /= np.linalg.norm(t)
    nrm = np.array([t[1], -t[0]])
    if nrm[0] < 0:
        nrm = -nrm
    dirn = nrm * 0.8 + t * 0.45; dirn /= np.linalg.norm(dirn)
    feathers.append(np.array([a + dirn * 2.0, a + dirn * L]))

# --- the eyes: scaled about their centres to the shipped sizes (near 11x18 px, far 8x17 px)
eyes = {}
for nm, k, dy in (('eye_near', 1.33, 0.0), ('eye_far', 1.65, -2.0)):
    # v12: a clean ellipse fitted to the traced eye (the trace notched the near eye's right edge), the far eye 2 px
    # higher (review v11: it ran into the bill's outline)
    E8 = old_800(nm); c = E8.mean(0); X = E8 - c; w, v = np.linalg.eigh(X.T @ X / len(X))
    a, b = np.sqrt(2 * w[1]) * k, np.sqrt(2 * w[0]) * k; ang = np.linspace(0, 2 * np.pi, 28, endpoint=False)
    eyes[nm] = c + np.array([0.0, dy]) + np.outer(a * np.cos(ang), v[:, 1]) + np.outer(b * np.sin(ang), v[:, 0])

# --- the mouth: the shipped stroke re-traced to ~9 px from the bill's tip (the old trace stopped 23 px short)
Mo = old_800('mouth'); bill_s = surf(D, 'bill', 240, 120)[0]
tipx = bill_s[:, 0].max()
d = Mo[-1] - Mo[-3]; d /= np.linalg.norm(d)
ext = [Mo[-1] + d * s for s in np.arange(2.0, max(2.0, (tipx - 9.0) - Mo[-1][0]) / max(d[0], 0.3), 2.0)]
mouth = np.vstack([Mo, np.array(ext)]) if ext else Mo
mouth = mouth[mouth[:, 0] <= tipx - 9.0]
print('mouth ends %.1f px from the tip (x %.1f vs tip %.1f)' % (tipx - mouth[-1][0], mouth[-1][0], tipx))

SB, SH, SK = surf(D, 'body'), surf(D, 'head'), surf(D, 'bill')
out = {}
out['wing'] = dict(part='body', closed=True, pts=[[round(float(v), 5) for v in q] for q in backproject(loop, SB)])
out['feather'] = dict(part='body', closed=False, pts=[[round(float(v), 5) for v in q] for q in backproject(resample(feathers[0], 1.5), SB)])
out['feather2'] = dict(part='body', closed=False, pts=[[round(float(v), 5) for v in q] for q in backproject(resample(feathers[1], 1.5), SB)])
for nm in ('eye_near', 'eye_far'):
    out[nm] = dict(part='head', closed=True, pts=[[round(float(v), 5) for v in q] for q in backproject(eyes[nm], SH)])
out['mouth'] = dict(part='bill', closed=False, pts=[[round(float(v), 5) for v in q] for q in backproject(resample(mouth, 1.5), SK)])
out['neck'] = OLD['neck']                                         # re-carried below onto the new head
Nk = old_800('neck'); out['neck'] = dict(part='head', closed=False, pts=[[round(float(v), 5) for v in q] for q in backproject(Nk, SH)])
for nm, v in out.items():
    print(nm, v['part'], len(v['pts']))
json.dump(out, open('duck_strokes2.json', 'w'), indent=1)
# a check image: the designed strokes over the old render
im = Image.open('../v10/rubber_800.png').convert('RGBA'); bg = Image.new('RGBA', im.size, (255, 255, 255, 255)); bg.alpha_composite(im)
dr = ImageDraw.Draw(bg)
dr.line([tuple(p) for p in np.vstack([loop, loop[:1]])], fill=(255, 0, 0, 255), width=2)
for f in feathers:
    dr.line([tuple(p) for p in f], fill=(255, 0, 0, 255), width=2)
for nm in eyes:
    dr.line([tuple(p) for p in np.vstack([eyes[nm], eyes[nm][:1]])], fill=(0, 200, 0, 255), width=1)
dr.line([tuple(p) for p in mouth], fill=(0, 0, 255, 255), width=2)
bg.crop((300, 560, 540, 780)).resize((720, 660), Image.LANCZOS).convert('RGB').save('duck_strokes2_check.png')
