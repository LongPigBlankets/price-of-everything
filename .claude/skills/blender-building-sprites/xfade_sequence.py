#!/usr/bin/env python3
"""Cross-fade a level set in place: the building upgrades without moving.

Takes the per-level stills rendered from ONE fixed camera (level_lineup.build_stack) and
blends between them, so L1 becomes L2 becomes L3 on the same ground. A free camera cannot
show this, and fading inside Blender cannot either — Freestyle draws its ink at full
opacity regardless of material alpha, so a half-faded building keeps solid black outlines
over a ghost. Blending finished FRAMES is the only way the ink fades with the building.

Blending is done PREMULTIPLIED. These are straight-alpha PNGs, and interpolating straight
RGB across a transparent edge pulls in whatever colour sits in the fully-transparent
pixels — a dark halo around every silhouette.

    python3 xfade_sequence.py renders/xfade --out renders/xfade/seq --fps 30
"""
import argparse
import os
import numpy as np
from PIL import Image


def _load(path):
    a = np.asarray(Image.open(path).convert("RGBA"), dtype=np.float64) / 255.0
    rgb, alpha = a[..., :3], a[..., 3:4]
    return rgb * alpha, alpha          # premultiplied


def _save(prem, alpha, path, bg=None):
    if bg is not None:
        b = np.asarray(bg, dtype=np.float64).reshape(1, 1, 3) / 255.0
        out = prem + b * (1.0 - alpha)
        img = np.concatenate([out, np.ones_like(alpha)], axis=-1)
    else:
        rgb = np.divide(prem, alpha, out=np.zeros_like(prem), where=alpha > 1e-6)
        img = np.concatenate([rgb, alpha], axis=-1)
    Image.fromarray((np.clip(img, 0, 1) * 255).round().astype(np.uint8), "RGBA").save(path)


def build(folder, out, levels=(1, 2, 3), hold=24, fade=18, tail=36, loop=True, bg=None):
    frames = [_load(os.path.join(folder, "L%d.png" % lv)) for lv in levels]
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        if f.endswith(".png"):
            os.remove(os.path.join(out, f))

    plan = []                      # (from_idx, to_idx, t) — t=0 is pure `from`
    for i in range(len(frames)):
        last = i == len(frames) - 1
        for _ in range(tail if last else hold):
            plan.append((i, i, 0.0))
        if not last:
            for s in range(fade):
                plan.append((i, i + 1, (s + 1) / (fade + 1)))
    if loop:
        for s in range(fade):
            plan.append((len(frames) - 1, 0, (s + 1) / (fade + 1)))

    for n, (a, b, t) in enumerate(plan):
        if a == b:
            prem, alpha = frames[a]
        else:
            pa, aa = frames[a]
            pb, ab = frames[b]
            prem = pa * (1 - t) + pb * t
            alpha = aa * (1 - t) + ab * t
        _save(prem, alpha, os.path.join(out, "f%04d.png" % n), bg=bg)
    return {"frames": len(plan), "out": out}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("folder")
    ap.add_argument("--out", required=True)
    ap.add_argument("--hold", type=int, default=24)
    ap.add_argument("--fade", type=int, default=18)
    ap.add_argument("--tail", type=int, default=36)
    ap.add_argument("--no-loop", action="store_true")
    ap.add_argument("--bg", default=None, help="e.g. 14,22,38 to flatten onto a colour")
    args = ap.parse_args()
    bg = [int(v) for v in args.bg.split(",")] if args.bg else None
    print(build(args.folder, args.out, hold=args.hold, fade=args.fade,
                tail=args.tail, loop=not args.no_loop, bg=bg))
