#!/usr/bin/env python3
"""Print-texture pass driven by a SHADING MASK rather than by pixel luma.

Why this exists. `stylize.py` decides where to stipple from the colour render's own luma, so
it is a luma key: a dark MATERIAL on a fully lit face gets stippled, and a pale material on a
face in shade does not. That is backwards. Stippling in this style is a shading substitute —
denser dots mean the face is turned away from the sun — so the thing that should drive it is
the face's orientation, not what colour it happens to be painted.

The mask is a second render of the same frame with a plain white diffuse `material_override`
and Freestyle off, so every pixel's brightness IS its shading and nothing else. Everything in
the sprite is then stippled on the same footing.

    python stylize_shade.py colour.png mask.png out.png [--strength 0.22] [--spacing 10]

Two things still come from the COLOUR image, not the mask:
  * ink lines, which the mask does not contain at all (no Freestyle in the mask pass) and
    which must never be dotted;
  * glass, which is deliberately left clean (owner rule) and is a material fact, not a
    shading one.
"""
import argparse
import numpy as np
from PIL import Image


def _grid_dist(xx, yy, spacing, off_u=0.0, off_v=0.0):
    """Distance to the nearest dot centre on a 45-degree rotated grid."""
    u = (xx + yy) / np.sqrt(2.0) + off_u
    v = (yy - xx) / np.sqrt(2.0) + off_v
    du = u - (np.round(u / spacing) * spacing)
    dv = v - (np.round(v / spacing) * spacing)
    return np.sqrt(du * du + dv * dv)


def stylize(colour, mask, dst, spacing=10.0, dot_r=1.6, strength=0.22, contrast=1.06,
            lit=0.72, dark=0.30, t_ink=0.10):
    im = Image.open(colour).convert("RGBA")
    a = np.asarray(im).astype(np.float32) / 255.0
    rgb, alpha = a[..., :3], a[..., 3]

    mk = Image.open(mask).convert("RGBA")
    if mk.size != im.size:
        mk = mk.resize(im.size, Image.LANCZOS)
    m = np.asarray(mk).astype(np.float32) / 255.0
    shade = m[..., 0] * 0.2126 + m[..., 1] * 0.7152 + m[..., 2] * 0.0722

    rgb = np.clip((rgb - 0.5) * contrast + 0.5, 0.0, 1.0)
    luma = rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722

    # HOW SHADED is this face — from the mask alone. `lit` is the brightness at which a face
    # counts as fully lit and takes no dots at all; `dark` is where density saturates.
    darkness = np.clip((lit - shade) / max(1e-6, (lit - dark)), 0.0, 1.0)

    # Exclusions, both material facts rather than shading ones.
    is_ink = luma < t_ink
    is_glass = (rgb[..., 2] > rgb[..., 0] * 1.45) & (luma < 0.38)
    keep = (alpha > 0.5) & (~is_ink) & (~is_glass) & (m[..., 3] > 0.5)

    h, w = luma.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    # Three density bands, as before: the dot SIZE never changes, only how many there are.
    d1 = _grid_dist(xx, yy, spacing)
    d2 = _grid_dist(xx, yy, spacing, off_u=spacing / 2.0)
    d3 = _grid_dist(xx, yy, spacing / 2.0, off_v=spacing / 4.0)
    dots = (d1 < dot_r).astype(np.float32)
    dots = np.maximum(dots, (darkness > 0.45) * (d2 < dot_r))
    dots = np.maximum(dots, (darkness > 0.78) * (d3 < dot_r))

    amt = (dots * darkness * strength)[..., None] * keep[..., None]
    out = np.clip(rgb * (1.0 - amt), 0.0, 1.0)
    res = np.concatenate([out, alpha[..., None]], axis=-1)
    Image.fromarray((res * 255.0 + 0.5).astype(np.uint8), "RGBA").save(dst)
    cov = float((dots * keep).mean())
    print("stylize_shade %s + %s -> %s   dotted %.1f%% of frame" % (colour, mask, dst,
                                                                   100.0 * cov))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("colour"); ap.add_argument("mask"); ap.add_argument("dst")
    ap.add_argument("--spacing", type=float, default=10.0)
    ap.add_argument("--dot-r", type=float, default=1.6)
    ap.add_argument("--strength", type=float, default=0.22)
    ap.add_argument("--lit", type=float, default=0.72)
    ap.add_argument("--dark", type=float, default=0.30)
    k = ap.parse_args()
    stylize(k.colour, k.mask, k.dst, spacing=k.spacing, dot_r=k.dot_r,
            strength=k.strength, lit=k.lit, dark=k.dark)
