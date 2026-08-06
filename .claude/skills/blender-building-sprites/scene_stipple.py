#!/usr/bin/env python3
"""Light-driven stipple for the loading SCENE (the sprites keep stylize.py).

stylize.py bands dot density by ALBEDO luma, which is right for sprites (flat tones,
no cast light) and wrong for a lit scene: lit brick (0.266) and shadowed road (0.277)
overlap, so no luma threshold can keep lit facades clean while stippling shade.

Here LIT vs SHADE comes from a LIGHT MASK — the same camera rendered with a white
material override and no ink, so the mask is pure illumination. With one sun and a
flat ambient the mask is close to binary (measured: shade ~0.604, lit ~0.765), so
the lit/shade split is a single cut between the modes (default 0.70) and the density
BANDS inside shade come from the albedo after all — in shadow the albedo IS the local
depth cue (dark brick in shade sits deeper than pale kerb in the same shadow):
  light >= lit_cut          -> no dots   (owner: fully lit areas carry no stipple)
  in shade                  -> sparse grid
  ... and albedo < mid_alb  -> + offset grid (2x)
  ... and albedo < deep_alb -> + half-spacing grid (4x)
Pixels with no mask coverage (backdrop, sky) get no dots. Glass keeps stylize.py's
blue-dominant test. Dot colour multiplies toward ink navy.

    python3 scene_stipple.py colour.png mask.png out.png --spacing 20 --dot-r 3.4
"""
import argparse
import numpy as np
from PIL import Image

INK = np.array([0.055, 0.065, 0.13], dtype=np.float32)


def _grid(xx, yy, spacing, off_u=0.0, off_v=0.0):
    u = (xx / spacing + off_u) % 1.0
    v = (yy / spacing + off_v) % 1.0
    return np.sqrt((u - 0.5) ** 2 + (v - 0.5) ** 2) * spacing


def scene_stipple(src, mask_path, dst, spacing=20.0, dot_r=3.4, strength=0.26,
                  lit_cut=0.70, mid_alb=0.45, deep_alb=0.25):
    im = Image.open(src).convert("RGBA")
    a = np.asarray(im).astype(np.float32) / 255.0
    rgb, alpha = a[..., :3], a[..., 3]
    m = Image.open(mask_path).convert("RGBA")
    if m.size != im.size:
        m = m.resize(im.size)
    ma = np.asarray(m).astype(np.float32) / 255.0
    mask_rgb, mask_a = ma[..., :3], ma[..., 3]
    light = mask_rgb[..., 0] * 0.2126 + mask_rgb[..., 1] * 0.7152 + mask_rgb[..., 2] * 0.0722
    albedo = rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722

    is_glass = (rgb[..., 2] > rgb[..., 0] * 1.45) & (albedo < 0.38)
    shaded = (alpha > 0.01) & (mask_a > 0.5) & ~is_glass & (light < lit_cut)

    h, w = light.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    g_a = _grid(xx, yy, spacing) < dot_r
    g_b = _grid(xx, yy, spacing, 0.5, 0.5) < dot_r
    g_c = (_grid(xx, yy, spacing / 2) < dot_r * 0.85)

    dot = np.zeros_like(light, dtype=bool)
    dot |= g_a
    dot |= g_b & (albedo < mid_alb)
    dot |= g_c & (albedo < deep_alb)
    dot &= shaded

    out = rgb.copy()
    k = strength
    out[dot] = out[dot] * (1 - k) + INK[None, :] * k
    res = np.concatenate([out, alpha[..., None]], axis=-1)
    Image.fromarray((np.clip(res, 0, 1) * 255).round().astype(np.uint8)).save(dst)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("src"); ap.add_argument("mask"); ap.add_argument("dst")
    ap.add_argument("--spacing", type=float, default=20.0)
    ap.add_argument("--dot-r", type=float, default=3.4)
    ap.add_argument("--strength", type=float, default=0.26)
    ap.add_argument("--lit-cut", type=float, default=0.70)
    ap.add_argument("--mid-alb", type=float, default=0.45)
    ap.add_argument("--deep-alb", type=float, default=0.25)
    args = ap.parse_args()
    scene_stipple(args.src, args.mask, args.dst, args.spacing, args.dot_r,
                  args.strength, args.lit_cut, args.mid_alb, args.deep_alb)
    print("scene-stippled", args.src, "->", args.dst)
