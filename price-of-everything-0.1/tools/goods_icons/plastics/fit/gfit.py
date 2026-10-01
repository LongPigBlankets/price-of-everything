"""Place the downloaded monobloc (monobloc_gltf/chair_welded.npz, Blender Z-up, faces -Y) on the shipped chair:
yaw, uniform scale (optionally per-axis), ground position, scored as IoU of the inked silhouette against the
shipped chair (fit/chair_fit2's frame, camera and ink model).
    python3 gfit.py <out.json> [aniso]"""
import json, math, sys, time
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'fit'))
import chair_fit2 as cf
from best_powell import best_powell
Z = np.load(HERE.parent / 'monobloc_gltf' / 'chair_welded.npz'); CO, TRI = Z['co'], Z['faces']
CAM = json.load(open(HERE.parent / 'fit' / 'P27c.json')); CAM = {k: CAM[k] for k in ('S', 'TX', 'TY')}


def place(G, co=CO):
    """chair-local (x width, y depth with the front at -y, z up) -> world, facing +X"""
    p = co * np.array([G.get('kx', 1.0), G.get('ky', 1.0), G.get('kz', 1.0)]) * G['s']
    a = math.radians(G['yaw']); c, s_ = math.cos(a), math.sin(a)
    return np.column_stack([c * p[:, 0] - s_ * p[:, 1] + G['tx'], s_ * p[:, 0] + c * p[:, 1] + G['ty'], p[:, 2]])


def mask(G, shape=cf.SHAPE):
    W = place(G); S2 = cf.project(W, CAM); img = Image.new('L', (shape[1], shape[0]), 0); d = ImageDraw.Draw(img)
    for t in TRI:
        d.polygon([tuple(S2[i]) for i in t], fill=255)
    return np.array(img) > 0


def iou(G):
    M = cf.inked(mask(G)); care = cf.CARE
    return (M & cf.REF & care).sum() / max(((M | cf.REF) & care).sum(), 1)


def overlay(G, path):
    M = cf.inked(mask(G)); care = cf.CARE; vis = np.zeros(cf.SHAPE + (3,), 'uint8')
    vis[cf.REF & care] = (120, 200, 120); vis[M & ~cf.REF & care] = (230, 80, 80); vis[M & cf.REF & care] = (60, 110, 60); vis[~care] = (70, 70, 90)
    Image.fromarray(vis).save(path)


if __name__ == '__main__':
    out = sys.argv[1]; aniso = len(sys.argv) > 2 and sys.argv[2] == 'aniso'
    G = dict(s=0.87, yaw=90.0, tx=0.0, ty=0.0)
    if Path(out).exists():
        G.update(json.load(open(out)))
    B = dict(s=(0.6, 1.2), yaw=(70.0, 110.0), tx=(-0.5, 0.5), ty=(-0.5, 0.5))
    if aniso:
        B.update(kx=(0.8, 1.2), ky=(0.8, 1.2), kz=(0.8, 1.2))
    keys = list(B); lo = np.array([B[k][0] for k in keys]); hi = np.array([B[k][1] for k in keys])
    def unpack(x):
        Q = dict(G); Q.update({k: float(v) for k, v in zip(keys, np.clip(x, lo, hi))}); return Q
    t = time.time(); print('start IoU %.4f' % iou(G), flush=True)
    x, f = best_powell(lambda x: -iou(unpack(x)), np.array([G.get(k, 1.0) for k in keys]), lo, hi, 3,
                       log=lambda m: print(m, '%.0fs' % (time.time() - t), flush=True), xtol=1e-3, ftol=1e-5)
    G = unpack(x); G['iou'] = iou(G); json.dump(G, open(out, 'w'), indent=1); overlay(G, out.replace('.json', '.png'))
    print({k: round(v, 4) for k, v in G.items()})
