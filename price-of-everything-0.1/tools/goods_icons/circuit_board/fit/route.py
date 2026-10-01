"""copper.json (the shipped copper as read) -> copper2.json, made electrically plausible (owner: "fix the traces and
fingers ... maybe a slot marking where the CPU and its slot will come in"):
  1. fragments of one trace rejoined (dead ends within GAP of each other);
  2. a printed socket outline (SOCKET, u/v box) in the empty middle; traces ending near it run to its edge and end on
     small land pads there; the top comb of stubs becomes its top row of breakout traces;
  3. loose dashes (short pieces with both ends free) dropped;
  4. every other free end finishes in a small via;
  5. each connector finger gets a trace onto the board, to an existing via above it or to its own via (two staggered rows).
    python3 route.py"""
import json, math
import numpy as np
from PIL import Image, ImageDraw
def segdist(p, P):
    best = 1e9
    for a, b in zip(P, P[1:]):
        d = b - a; L2 = d @ d; t = 0 if L2 < 1e-12 else max(0, min(1, (p - a) @ d / L2)); best = min(best, np.hypot(*(p - (a + t * d))))
    return best
C = json.load(open('copper.json')); T = [np.array(t, float) for t in C['traces']]
# the gap-closed reading (copper.json) lost the short stubs; the first reading (copper_v1.json) kept them, broken: add
# each first-reading piece that the second does not already cover
def _cov(P, Q, tol=0.012):
    pts = [P[0] + (P[-1] - P[0]) * 0 ]
    S = [a + (b - a) * t for a, b in zip(P, P[1:]) for t in np.linspace(0, 1, 6)]
    return np.mean([min(segdist(p, R) for R in Q) < tol for p in S])
C1 = json.load(open('copper_v1.json'))
_extra = [np.array(t, float) for t in C1['traces']]
_extra = [P for P in _extra if _cov(P, T) < 0.3]
T += _extra
print('added %d short pieces from the first reading' % len(_extra))
W = C['width']; GAP = 0.034; SOCK = dict(u0=0.465, u1=0.790, v0=0.425, v1=0.750)
VIAS = [dict(c=list(v['c']), r_out=v['r_out'], r_hole=v['r_hole']) for v in C['vias']]
C['pad_polys'] = C1['pad_polys'] if 'C1' in dir() else C['pad_polys']
SMALL = dict(r_out=0.0125, r_hole=0.0055)
def inpoly(p, poly):
    x, y = p; c = False; n = len(poly)
    for i in range(n):
        (x1, y1), (x2, y2) = poly[i], poly[(i + 1) % n]
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1): c = not c
    return c
def length(P): return float(sum(np.hypot(*(b - a)) for a, b in zip(P, P[1:])))
def on_socket(p):
    u, v = p; S = SOCK
    return (min(abs(u - S['u0']), abs(u - S['u1'])) < 0.004 and S['v0'] - 0.004 <= v <= S['v1'] + 0.004) or \
           (min(abs(v - S['v0']), abs(v - S['v1'])) < 0.004 and S['u0'] - 0.004 <= u <= S['u1'] + 0.004)
def connected(p, i, T):
    if on_socket(p): return 'socket'
    if any(np.hypot(*(p - np.array(v['c']))) < v['r_out'] + 0.008 for v in VIAS): return 'via'
    if any(inpoly(p, pp) or min(np.hypot(*(p - np.array(q))) for q in pp) < 0.02 for pp in C['pad_polys']): return 'pad'
    if any(j != i and T[j] is not None and segdist(p, T[j]) < 0.012 for j in range(len(T))): return 'trace'
    return None
def free_ends(T):
    out = []
    for i, P in enumerate(T):
        if P is None: continue
        for k in (0, 1):
            p = P[0] if k == 0 else P[-1]
            if connected(p, i, T) is None: out.append((i, k))
    return out
def end_dir(P, k):                                    # outward direction at an end
    a, b = (P[0], P[1]) if k == 0 else (P[-1], P[-2]); d = a - b; return d / max(np.hypot(*d), 1e-9)
# 1. rejoin fragments: two ends of different traces, close, and roughly facing each other
for _ in range(200):
    fe = [(i, k) for i, P in enumerate(T) if P is not None for k in (0, 1) if connected(P[0] if k == 0 else P[-1], i, T) in (None, 'trace')]; best = None
    for x in range(len(fe)):
        for y in range(x + 1, len(fe)):
            (i, ki), (j, kj) = fe[x], fe[y]
            if i == j: continue
            pi = T[i][0] if ki == 0 else T[i][-1]; pj = T[j][0] if kj == 0 else T[j][-1]; d = np.hypot(*(pj - pi))
            if d > GAP: continue
            gap = (pj - pi) / max(d, 1e-9)
            if d > 0.008 and (end_dir(T[i], ki) @ gap < 0.7 or end_dir(T[j], kj) @ -gap < 0.7): continue
            if best is None or d < best[0]: best = (d, i, ki, j, kj)
    if best is None: break
    _, i, ki, j, kj = best
    A = T[i] if ki == 1 else T[i][::-1]; B = T[j] if kj == 0 else T[j][::-1]
    T[i] = np.vstack([A, B]); T[j] = None
T = [P for P in T if P is not None]
# spurs left by the via rings and pad outlines: short pieces near a via or a pad go
def near_feature(p):
    return any(np.hypot(*(p - np.array(v['c']))) < v['r_out'] + 0.02 for v in VIAS) or \
           any(inpoly(p, pp) or min(np.hypot(*(p - np.array(q))) for q in pp) < 0.025 for pp in C['pad_polys'])
T = [P for P in T if not (length(P) < 0.035 and (near_feature(P[0]) or near_feature(P[-1])))]
# ends that stop short of a via ring run into its centre (the ring covers it)
for i, P in enumerate(T):
    for k in (0, 1):
        p = P[0] if k == 0 else P[-1]
        for v in VIAS:
            c = np.array(v['c']); d = np.hypot(*(p - c))
            if v['r_out'] * 0.6 < d < v['r_out'] + 0.035 and end_dir(P, k) @ ((c - p) / d) > 0.5:
                q = c + (p - c) / d * v['r_out'] * 0.5
                T[i] = np.vstack([q, P]) if k == 0 else np.vstack([P, q]); P = T[i]; break
def pad_entry(p, dirn):
    for pp in C['pad_polys']:
        Q = np.array(pp); c = Q.mean(0)
        dmin = min(np.hypot(*(p - q)) for q in Q)
        if dmin < 0.04 and dirn @ ((c - p) / max(np.hypot(*(c - p)), 1e-9)) > 0.3:
            return Q[np.argmin(np.hypot(*(Q - p).T))] + (c - Q[np.argmin(np.hypot(*(Q - p).T))]) * 0.15
    return None
# short pieces in the gap between the socket's right edge and the connector pads go (the pads get their own traces)
T = [P for P in T if not (length(P) < 0.07 and P[:, 0].min() > SOCK['u1'] - 0.015 and P[:, 0].max() < SOCK['u1'] + 0.07)]
for i, P in enumerate(T):
    for k in (0, 1):
        p = P[0] if k == 0 else P[-1]
        if connected(p, i, T) is None:
            q = pad_entry(p, end_dir(P, k))
            if q is not None:
                T[i] = np.vstack([q, P]) if k == 0 else np.vstack([P, q]); P = T[i]
# 2. the socket: ends near or inside its box run to its edge, square to it, and end on a land pad
u0, u1, v0, v1 = SOCK['u0'], SOCK['u1'], SOCK['v0'], SOCK['v1']; lands = []
def to_edge(p, d):
    """the nearest edge point of the box from p (outside or inside), on the side p faces"""
    u, v = p; cands = []
    if v0 <= v <= v1: cands += [(abs(u - u0), np.array([u0, v])), (abs(u - u1), np.array([u1, v]))]
    if u0 <= u <= u1: cands += [(abs(v - v0), np.array([u, v0])), (abs(v - v1), np.array([u, v1]))]
    return min(cands, key=lambda c: c[0]) if cands else (1e9, None)
for i, k in free_ends(T):
    P = T[i]; p = P[0] if k == 0 else P[-1]; dist, q = to_edge(p, end_dir(P, k))
    inside = u0 < p[0] < u1 and v0 < p[1] < v1
    toward = q is not None and dist > 1e-6 and end_dir(P, k) @ ((q - p) / dist) > 0.6
    if q is not None and ((dist < 0.06 and toward) or inside):
        if k == 0: T[i] = np.vstack([q, P]) if not inside else np.vstack([q, P[1:]])
        else: T[i] = np.vstack([P, q]) if not inside else np.vstack([P[:-1], q])
        lands.append(q.tolist())
# traces that cross into the box are cut at its edge
def clip(P):
    out = [P[0]]
    for a, b in zip(P, P[1:]):
        ina = u0 < a[0] < u1 and v0 < a[1] < v1; inb = u0 < b[0] < u1 and v0 < b[1] < v1
        if inb and not ina:
            for t in np.linspace(0, 1, 200):
                q = a + (b - a) * t
                if u0 < q[0] < u1 and v0 < q[1] < v1: out.append(q); lands.append(q.tolist()); return np.array(out), True
        out.append(b)
    return np.array(out), False
T = [clip(P)[0] for P in T]
for pp in C['pad_polys']:
    Q = np.array(pp)
    if Q[:, 0].min() > SOCK['u1'] and SOCK['v0'] < Q[:, 1].mean() < SOCK['v1']:
        left = Q[Q[:, 0] < Q[:, 0].min() + 0.01]; p = np.array([Q[:, 0].min() + 0.006, min(left[:, 1].mean(), SOCK['v1'] - 0.02)])
        if not any(np.hypot(*(np.array(l) - np.array([SOCK['u1'], p[1]]))) < 0.02 for l in lands):
            T.append(np.array([p, [SOCK['u1'], p[1]]])); lands.append([SOCK['u1'], float(p[1])])
# 3. loose dashes go
T = [P for i, P in enumerate(T) if not (length(P) < 0.10 and sum(1 for j, k in free_ends(T) if j == i) == 2)]
# 4. other free ends finish in a small via (the trace drops to another layer)
for i, k in free_ends(T):
    P = T[i]; p = (P[0] if k == 0 else P[-1]).copy()
    VIAS.append(dict(c=(p + end_dir(P, k) * SMALL['r_out'] * 0.6).tolist(), **SMALL))
# 5. the fingers
f_traces = []; f_vias = []; row = 0
BOARD = dict(tab=(0.295, 0.955), notch=(0.475, 0.540), finger_pitch=0.0285)
FING = []
for a0, a1 in ((BOARD['tab'][0], BOARD['notch'][0]), (BOARD['notch'][1], BOARD['tab'][1])):
    n = int((a1 - a0 - 0.01) / BOARD['finger_pitch'])
    FING += [a0 + 0.005 + BOARD['finger_pitch'] * (k + 0.5) + ((a1 - a0 - 0.01) - n * BOARD['finger_pitch']) / 2 for k in range(n)]
for uc in FING:
    top = np.array([uc, -0.04])
    near = [v for v in VIAS if abs(v['c'][0] - uc) < 0.016 and -0.01 < v['c'][1] < 0.12]
    if near:
        v = min(near, key=lambda v: v['c'][1]); f_traces.append([top.tolist(), [uc, v['c'][1] - v['r_out'] * 0.5]])
    else:
        vy = 0.035 + 0.045 * (row % 2); row += 1
        c = [uc, vy]
        if any(np.hypot(c[0] - v['c'][0], c[1] - v['c'][1]) < v['r_out'] + SMALL['r_out'] + 0.008 for v in VIAS + f_vias):
            c = [uc, 0.025]
        f_traces.append([top.tolist(), [uc, c[1] - SMALL['r_out'] * 0.5]]); f_vias.append(dict(c=c, **SMALL))
out = dict(width=W, traces=[P.tolist() for P in T] + f_traces, vias=VIAS + f_vias, pad_polys=C['pad_polys'], fingers=C['fingers'],
           socket=SOCK, lands=lands)
json.dump(out, open('copper2.json', 'w'), indent=1)
print('traces %d -> %d (+%d finger traces), vias %d -> %d, lands %d, free ends now %d' % (len(C['traces']), len(T), len(f_traces), len(C['vias']), len(out['vias']), len(lands), len(free_ends(T))))
# check image
LO, HI, N = -0.25, 1.05, 1300; PX = (HI - LO) / (N - 1)
def px(p): return ((p[0] - LO) / PX, (HI - p[1]) / PX)
im = Image.new('RGB', (N, N), (98, 128, 98)); d = ImageDraw.Draw(im)
d.rectangle((px((u0, v1))[0], px((u0, v1))[1], px((u1, v0))[0], px((u1, v0))[1]), outline=(235, 230, 210), width=3)
for P in out['traces']: d.line([px(p) for p in P], fill=(214, 182, 116), width=int(W / PX))
for v in out['vias']:
    x, y = px(v['c']); r = v['r_out'] / PX; h = v['r_hole'] / PX; d.ellipse((x - r, y - r, x + r, y + r), fill=(214, 182, 116)); d.ellipse((x - h, y - h, x + h, y + h), fill=(30, 36, 60))
for pp in out['pad_polys']: d.polygon([px(p) for p in pp], fill=(214, 182, 116), outline=(30, 36, 60))
for q in lands:
    x, y = px(q); d.rectangle((x - 7, y - 7, x + 7, y + 7), fill=(214, 182, 116))
for uc in FING: d.rectangle((px((uc - 0.0095, -0.045))[0], px((uc, -0.045))[1], px((uc + 0.0095, -0.178))[0], px((uc, -0.178))[1]), fill=(214, 182, 116))
im.save('route_check.png')
