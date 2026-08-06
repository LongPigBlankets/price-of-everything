#!/usr/bin/env python3
"""Light-driven stipple for the loading SCENE (the sprites keep stylize.py).

Owner 2026-08-06: shading is carried by STIPPLE DENSITY ALONE — the colour layers
render FLAT (render_layers turns the sun off and boosts ambient for the colour
pass), and this pass prints the light back on as dots: the denser the dots, the
deeper the shade. Dots are half the size of the first pass (r 1.7 at 2400px) so
density, not dot weight, is the signal.

LIT vs SHADE comes from a LIGHT MASK — the same camera rendered with a white
material override and no ink (sun ON for masks). With one sun and a flat ambient
the mask is nearly bimodal (shade ~0.604, lit ~0.765); tilted facets land between.
Bands (mask luma):
  light >= lit_cut   -> no dots        (fully lit carries no stipple)
  part_cut..lit_cut  -> sparse grid    (grazing light: canopy facets, tilted faces)
  < part_cut         -> 2x density     (faces turned from the sun)
  < part_cut, --deep-shade -> 4x       (street layer: its full-shade pixels are
                                        CAST SHADOWS — the deepest band)
Pixels with no mask coverage (backdrop, sky) get no dots. Glass keeps stylize.py's
blue-dominant test. Dot colour multiplies toward ink navy.

    python3 scene_stipple.py colour.png mask.png out.png [--deep-shade]
"""
import argparse
import numpy as np
from PIL import Image

INK = np.array([0.055, 0.065, 0.13], dtype=np.float32)


def _grid(xx, yy, spacing, off_u=0.0, off_v=0.0):
    u = (xx / spacing + off_u) % 1.0
    v = (yy / spacing + off_v) % 1.0
    return np.sqrt((u - 0.5) ** 2 + (v - 0.5) ** 2) * spacing


def scene_stipple(src, mask_path, dst, spacing=14.0, dot_r=1.7, strength=0.38,
                  lit_cut=0.70, part_cut=0.63, deep_shade=False, px_scale=1.0):
    # Every knob below is in PIXELS, so a layer rendered at a different canvas
    # size needs them scaled or the dots come out finer/coarser on screen than
    # the approved frame (px_scale = canvas_width / 2400, the reference).
    spacing *= px_scale
    dot_r *= px_scale
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
    covered = (alpha > 0.01) & (mask_a > 0.5) & ~is_glass
    # Dots need AREA: erode coverage so slivers thinner than ~5px never collect
    # dots. Sub-pixel strips of geometry peeking over a holdout horizon (e.g. a
    # yard slab edge above the lawn) otherwise render as dashed speck trails.
    _cr = max(1, int(round(2 * px_scale)))
    er = covered.copy()
    for dy in range(-_cr, _cr + 1):
        for dx in range(-_cr, _cr + 1):
            er &= np.roll(np.roll(covered, dy, 0), dx, 1)
    covered = er

    h, w = light.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    # Anti-aliased coverage per grid (1px soft edge): at half-size dots a hard
    # threshold rasterises square-ish; coverage keeps them round.
    def cov(dist, r):
        return np.clip(r + 0.5 - dist, 0.0, 1.0)
    c_a = cov(_grid(xx, yy, spacing), dot_r)
    c_b = cov(_grid(xx, yy, spacing, 0.5, 0.5), dot_r)
    c_c = cov(_grid(xx, yy, spacing / 2), dot_r * 0.9)

    # Shade features need AREA too: a scaffold pole or crane-jib shadow a few px
    # wide dots as a dashed dirt trail across the lawn, not as shade. Erode the
    # band masks so features thinner than ~2r+1 px carry no dots; broad shadow
    # blobs and canopy shade merely shrink by the same margin.
    def _er(m, r=max(1, int(round(3 * px_scale)))):
        out = m.copy()
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                out &= np.roll(np.roll(m, dy, 0), dx, 1)
        return out
    band_a = _er(light < lit_cut)
    band_b = _er(light < part_cut)

    coverage = np.zeros_like(light, dtype=np.float32)
    coverage = np.maximum(coverage, c_a * band_a)
    coverage = np.maximum(coverage, c_b * band_b)
    if deep_shade:
        coverage = np.maximum(coverage, c_c * band_b)
    coverage *= covered

    out = rgb.copy()
    k = strength * coverage[..., None]
    out = out * (1 - k) + INK[None, None, :] * k
    res = np.concatenate([out, alpha[..., None]], axis=-1)
    Image.fromarray((np.clip(res, 0, 1) * 255).round().astype(np.uint8)).save(dst)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("src"); ap.add_argument("mask"); ap.add_argument("dst")
    ap.add_argument("--spacing", type=float, default=14.0)
    ap.add_argument("--dot-r", type=float, default=1.7)
    ap.add_argument("--strength", type=float, default=0.38)
    ap.add_argument("--lit-cut", type=float, default=0.70)
    ap.add_argument("--part-cut", type=float, default=0.63)
    ap.add_argument("--deep-shade", action="store_true")
    ap.add_argument("--px-scale", type=float, default=1.0)
    args = ap.parse_args()
    scene_stipple(args.src, args.mask, args.dst, args.spacing, args.dot_r,
                  args.strength, args.lit_cut, args.part_cut, args.deep_shade,
                  args.px_scale)
    print("scene-stippled", args.src, "->", args.dst)
