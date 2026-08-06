#!/usr/bin/env python3
"""Regrade the L0 sky layer: smooth vertical gradient + radial sun-glow (post).

Owner 2026-08-06: "blend the colours of the sky more gradient-like and make the
top colour even more vibrant, like #20a7db. Add a further gradient radially from
the top right to the left because the sun is somewhere off camera to the top
right."

Done in POST, not in the Blender sky material, for the same reason the stipple
is: AgX crushes emission colours (the .blend's vivid (0.175,0.445,0.850) top
band renders as #84a6c2 steel), so an exact display hex can only be authored in
display space. The .blend keeps the banded plane as a stand-in; this script is
part of the layer pipeline: L0_sky.png -> L0_sky_graded.png, and the composite /
Godot import use the graded file.

Vertical stops run from the owner's vibrant zenith through the approved steel
mids into the warm horizon cream sampled from the banded render, interpolated
smoothly (no band edges). The glow lerps toward warm sun-cream, centred just
off-canvas beyond the top-right corner, smoothstep falloff.

    python3 sky_gradient.py L0_sky.png L0_sky_graded.png
"""
import argparse
import numpy as np
from PIL import Image

# (row_frac, display hex) — piecewise-linear between stops.
STOPS = [
    (0.000, "#20a7db"),    # zenith (owner)
    (0.370, "#4fa7d2"),    # hold vibrancy through the upper sky
    (0.533, "#7fabc7"),    # into the approved steel mid
    (0.630, "#9fb1c0"),
    (0.704, "#b3b9bc"),    # horizon cream (sampled from the banded render)
    (1.000, "#b3b9bc"),
]
GLOW = "#ffedc4"           # warm sun-cream, matches the sun tint (1.0,0.955,0.87)
GLOW_CX, GLOW_CY = 1.08, -0.13    # centre, fractions of W/H — beyond the TR corner
GLOW_R = 0.80              # falloff radius as a fraction of W
GLOW_MIX = 0.40            # lerp weight at the glow centre


def _hex(c):
    c = c.lstrip("#")
    return np.array([int(c[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32) / 255.0


def sky_gradient(src, dst, top=None, glow=None, glow_mix=GLOW_MIX):
    im = Image.open(src).convert("RGBA")
    a = np.asarray(im).astype(np.float32) / 255.0
    h, w = a.shape[:2]
    alpha = a[..., 3]

    stops = list(STOPS)
    if top:
        stops[0] = (0.0, top)
    ys = np.array([s[0] for s in stops], dtype=np.float32)
    cs = np.stack([_hex(s[1]) for s in stops])
    rows = np.linspace(0.0, 1.0, h, dtype=np.float32)
    grad = np.empty((h, 3), dtype=np.float32)
    for ch in range(3):
        grad[:, ch] = np.interp(rows, ys, cs[:, ch])
    out = np.repeat(grad[:, None, :], w, axis=1)

    gc = _hex(glow or GLOW)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt((xx - GLOW_CX * w) ** 2 + (yy - GLOW_CY * h) ** 2) / (GLOW_R * w)
    t = np.clip(1.0 - d, 0.0, 1.0)
    t = t * t * (3.0 - 2.0 * t) * glow_mix          # smoothstep falloff
    out = out * (1.0 - t[..., None]) + gc[None, None, :] * t[..., None]

    res = np.concatenate([out, alpha[..., None]], axis=-1)
    Image.fromarray((np.clip(res, 0, 1) * 255).round().astype(np.uint8)).save(dst)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("src"); ap.add_argument("dst")
    ap.add_argument("--top")
    ap.add_argument("--glow")
    ap.add_argument("--glow-mix", type=float, default=GLOW_MIX)
    args = ap.parse_args()
    sky_gradient(args.src, args.dst, args.top, args.glow, args.glow_mix)
    print("sky-graded", args.src, "->", args.dst)
