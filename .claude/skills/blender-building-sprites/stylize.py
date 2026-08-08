#!/usr/bin/env python3
"""Print-texture pass for building sprites (WPA / midcentury catalogue look).

Stippling is a SHADING SUBSTITUTE: denser stippling = darker shading.
Lit faces stay clean; mid faces get a sparse dot grid; darker faces double the
density; the darkest shaded faces quadruple it. Dot size stays constant —
only density ramps. Ink linework and glass (near-black pixels) are excluded,
and alpha is preserved.

Usage:
    python3 stylize.py in.png out.png [--spacing 10] [--dot-r 1.8] [--strength 0.30]
"""
import argparse
import numpy as np
from PIL import Image


def _grid_dist(xx, yy, spacing, off_u=0.0, off_v=0.0):
    """Distance to nearest dot centre on a 45-degree rotated grid."""
    u = (xx + yy) / np.sqrt(2.0) + off_u
    v = (yy - xx) / np.sqrt(2.0) + off_v
    du = u - (np.round(u / spacing) * spacing)
    dv = v - (np.round(v / spacing) * spacing)
    return np.sqrt(du * du + dv * dv)


def stylize(src: str, dst: str, spacing: float = 10.0, dot_r: float = 1.8,
            strength: float = 0.30, contrast: float = 1.10,
            t_ink: float = 0.09, t_hi: float = 0.50,
            skip_hex: str = "", skip_tol: float = 0.055) -> None:
    im = Image.open(src).convert("RGBA")
    a = np.asarray(im).astype(np.float32) / 255.0
    rgb, alpha = a[..., :3], a[..., 3]

    # --- contrast punch (around mid-grey) ---
    rgb = np.clip((rgb - 0.5) * contrast + 0.5, 0.0, 1.0)

    luma = rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722
    # 0 = highlight (no dots), 1 = darkest shaded face
    darkness = np.clip((t_hi - luma) / (t_hi - t_ink), 0.0, 1.0)
    # windows stay unstippled: rendered glass is blue-dominant AND dark
    # (b/r >= 1.5, luma < 0.35 measured), unlike slate (b/r <= 1.25). The same
    # test catches the navy doors/darkmetal — fine, those are detail features.
    is_glass = (rgb[..., 2] > rgb[..., 0] * 1.45) & (luma < 0.38)
    # Explicit tone exclusions (comma-separated hexes). The docks' open water is
    # #497486: blue-dominant like glass, but at luma 0.424 it clears the 0.38 cut,
    # so the glass test lets it through and the bay comes out halftoned. Water is a
    # flat plane of one tone, and a screen over it reads as texture on the sea.
    skip = np.zeros_like(luma, dtype=bool)
    for hx in [h for h in skip_hex.split(",") if h.strip()]:
        c = hx.strip().lstrip("#")
        tgt = np.array([int(c[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32) / 255.0
        skip |= np.all(np.abs(rgb - tgt[None, None, :]) < skip_tol, axis=-1)
    eligible = (luma > t_ink) & (luma < t_hi) & (alpha > 0.01) & ~is_glass & ~skip

    h, w = alpha.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)

    def dots(d):
        return np.clip((dot_r - d) + 0.5, 0.0, 1.0)   # soft-edged, constant size

    # density bands: sparse grid -> +dual grid (2x) -> +half-spacing grid (4x)
    g_a = dots(_grid_dist(xx, yy, spacing))
    g_b = dots(_grid_dist(xx, yy, spacing, spacing / 2, spacing / 2))
    g_c = dots(_grid_dist(xx, yy, spacing / 2, spacing / 4, 0.0))

    dot = np.zeros_like(luma)
    dot = np.maximum(dot, g_a * (darkness > 0.10))
    dot = np.maximum(dot, g_b * (darkness > 0.45))
    dot = np.maximum(dot, g_c * (darkness > 0.75))

    mask = dot * strength * eligible
    rgb = rgb * (1.0 - mask[..., None])

    out = np.concatenate([rgb, alpha[..., None]], axis=-1)
    Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).save(dst)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--spacing", type=float, default=10.0)
    ap.add_argument("--dot-r", type=float, default=1.8)
    ap.add_argument("--strength", type=float, default=0.30)
    ap.add_argument("--contrast", type=float, default=1.10)
    ap.add_argument("--skip-hex", default="", help="comma-separated tones to leave unstippled")
    ap.add_argument("--skip-tol", type=float, default=0.055)
    args = ap.parse_args()
    stylize(args.src, args.dst, args.spacing, args.dot_r, args.strength, args.contrast,
            skip_hex=args.skip_hex, skip_tol=args.skip_tol)
    print(f"stylized {args.src} -> {args.dst}")
