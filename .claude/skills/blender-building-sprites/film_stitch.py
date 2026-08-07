#!/usr/bin/env python3
"""Stitch rendered keyframes into the loading film, and test the interpolation.

Each keyframe is a TRUE render from its own camera position, so perspective,
occlusion and setbacks are exact by construction — none of the plane-warp errors.
Per keyframe the renderer emits three passes:
    fNNN.png      flat colour, sky plane hidden (AgX crushes the emission bands, so
                  the vivid sky only exists in post — composited here)
    fNNN_geo.png  geometric light mask -> orientation bands on walls
    fNNN_gnd.png  diffuse mask of the GROUND ONLY -> real cast shadows on road/lawn
Dots are laid on a grid fixed in OUTPUT space, so the stipple sits on the page like
a print screen while the world moves under it.

Keyframes are rendered every STEP world units and the in-between frames are
synthesized, because rendering all 1350 frames costs ~13h and ~1.4GB for no visible
gain. Two interpolators are written so they can be compared:
    _mci   ffmpeg minterpolate (motion-compensated) — true in-betweens
    _fade  plain cross-dissolve — the cheap baseline

    python3 film_stitch.py [--dir renders/loading/film_probe] [--pace 1.3]
"""
import argparse
import os
import subprocess
import numpy as np
from PIL import Image
from scipy.ndimage import binary_erosion, gaussian_filter

HERE = os.path.dirname(os.path.abspath(__file__))
W, H = 1920, 1080
SKY = os.path.join(HERE, "renders/loading/layers/L0_sky_graded.png")
SKY_X, CAM_X, LENS, SENSOR = 210.0, -13.0, 32.0, 36.0
SHIFT_Y = 0.125
INK = np.array([0.055, 0.065, 0.13], dtype=np.float32)
DOT_SPACING, DOT_R, DOT_STRENGTH = 11.2, 1.36, 0.38
# Edge softening (owner): the outer band left and right goes progressively soft.
# It does two jobs — the fastest optical flow in a forward dolly is at the frame
# edges, which is exactly where motion interpolation deforms, and blurring BEFORE
# interpolation leaves it much less high-frequency detail to misalign there. It
# also reads as speed, which is free.
EDGE_FRAC, EDGE_SIGMA = 0.10, 7.0
GND_CUTS = (0.70, 0.63, True)        # diffuse mask scale, deepest band = cast shadow
WALL_CUTS = (0.775, 0.60, False)     # geometric mask scale


def _grid(xx, yy, sp, ou=0.0, ov=0.0):
    u = (xx / sp + ou) % 1.0
    v = (yy / sp + ov) % 1.0
    return np.sqrt((u - 0.5) ** 2 + (v - 0.5) ** 2) * sp


yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
_c = lambda d, r: np.clip(r + 0.5 - d, 0.0, 1.0)
G_A = _c(_grid(xx, yy, DOT_SPACING), DOT_R)
G_B = _c(_grid(xx, yy, DOT_SPACING, 0.5, 0.5), DOT_R)
G_C = _c(_grid(xx, yy, DOT_SPACING / 2), DOT_R * 0.9)
del xx, yy


def _bands(light, cuts):
    lit_cut, part_cut, deep = cuts
    a = binary_erosion(light < lit_cut, np.ones((5, 5), bool))
    b = binary_erosion(light < part_cut, np.ones((5, 5), bool))
    cov = np.maximum(G_A * a, G_B * b)
    if deep:
        cov = np.maximum(cov, G_C * b)
    return cov


def _edge_weight():
    """0 across the middle, smoothstepping to 1 at the extreme left/right edges."""
    x = np.arange(W, dtype=np.float32)
    band = EDGE_FRAC * W
    t = np.maximum((band - x) / band, (x - (W - 1 - band)) / band)
    t = np.clip(t, 0.0, 1.0)
    t = t * t * (3.0 - 2.0 * t)
    return np.repeat(t[None, :], H, axis=0)[..., None]


EDGE_W = _edge_weight()


def _luma(a):
    return a[..., 0] * 0.2126 + a[..., 1] * 0.7152 + a[..., 2] * 0.0722


def sky_for(step_i, step):
    """The graded sky for this advance. It is a perpendicular backdrop 223 units
    away, so a plain uniform scale about the vanishing point covers it — over a
    whole run it barely moves, which is the point."""
    im = Image.open(SKY).convert("RGB").resize((W, H), Image.LANCZOS)
    d = step_i * step
    f = SKY_X - CAM_X
    m = f / (f - d)
    if abs(m - 1.0) < 1e-6:
        return im
    fx = W / 2.0
    fy = H / 2.0 + SHIFT_Y * max(W, H)
    a = 1.0 / m
    return im.transform((W, H), Image.AFFINE,
                        (a, 0.0, fx * (1.0 - a), 0.0, a, fy * (1.0 - a)),
                        resample=Image.BICUBIC)


def frame(dirpath, i, step):
    col = Image.open(os.path.join(dirpath, "f%03d.png" % i)).convert("RGBA").resize((W, H), Image.LANCZOS)
    geo = Image.open(os.path.join(dirpath, "f%03d_geo.png" % i)).convert("RGBA").resize((W, H), Image.LANCZOS)
    gnd = Image.open(os.path.join(dirpath, "f%03d_gnd.png" % i)).convert("RGBA").resize((W, H), Image.LANCZOS)
    c = np.asarray(col).astype(np.float32) / 255.0
    g = np.asarray(geo).astype(np.float32) / 255.0
    n = np.asarray(gnd).astype(np.float32) / 255.0
    rgb, alpha = c[..., :3].copy(), c[..., 3]
    lum = _luma(rgb)
    glass = (rgb[..., 2] > rgb[..., 0] * 1.45) & (lum < 0.38)
    is_gnd = n[..., 3] > 0.5
    # Dots only where a mask actually covers the pixel. The city and the clouds are
    # hidden from BOTH mask passes (they are emission backdrop), so without this
    # they read as luma 0 = deepest shade and the skyline comes out stippled.
    has_mask = (g[..., 3] > 0.5) | is_gnd
    body = binary_erosion((alpha > 0.01) & ~glass & has_mask, np.ones((5, 5), bool))
    cov = np.where(is_gnd, _bands(_luma(n), GND_CUTS), _bands(_luma(g), WALL_CUTS))
    k = (DOT_STRENGTH * cov * body)[..., None]
    rgb = rgb * (1 - k) + INK[None, None, :] * k
    sky = np.asarray(sky_for(i, step)).astype(np.float32) / 255.0
    a = alpha[..., None]
    out = rgb * a + sky * (1 - a)
    if EDGE_SIGMA > 0:
        soft = gaussian_filter(out, sigma=(EDGE_SIGMA, EDGE_SIGMA, 0))
        out = out * (1.0 - EDGE_W) + soft * EDGE_W
    return (np.clip(out, 0, 1) * 255).astype(np.uint8)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="renders/loading/film_probe")
    ap.add_argument("--step", type=float, default=0.5)
    ap.add_argument("--pace", type=float, default=1.3, help="world units per second")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()
    d = os.path.join(HERE, args.dir) if not os.path.isabs(args.dir) else args.dir
    n = len([f for f in os.listdir(d) if f.startswith("f") and f.endswith(".png")
             and "_" not in f])
    stage = os.path.join(d, "_stage")
    os.makedirs(stage, exist_ok=True)
    for i in range(n):
        Image.fromarray(frame(d, i, args.step)).save(os.path.join(stage, "k%03d.png" % i))
        print("keyframe %d/%d" % (i + 1, n), flush=True)

    kfps = args.pace / args.step                     # keyframes per second
    base = args.out or os.path.join(HERE, "renders/loading/film_probe")
    for tag, vf in (("mci", "minterpolate=fps=30:mi_mode=mci:mc_mode=aobmc:vsbmc=1"),
                    ("fade", "framerate=fps=30")):
        out = "%s_%s.mp4" % (base, tag)
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-r", "%.5f" % kfps,
                        "-i", os.path.join(stage, "k%03d.png"),
                        "-vf", vf, "-c:v", "libx264", "-crf", "17",
                        "-pix_fmt", "yuv420p", "-movflags", "+faststart", out], check=True)
        print("wrote", out)
    print("%d keyframes @ %.2f/s -> %.1fs of film" % (n, kfps, n / kfps))


if __name__ == "__main__":
    main()
