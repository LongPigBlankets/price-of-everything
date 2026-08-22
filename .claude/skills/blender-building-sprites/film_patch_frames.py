#!/usr/bin/env python3
"""Composite region-rendered repair frames over the shipped film's own frames.

    python film_patch_frames.py --patch <dir> --orig <decoded_frames_dir> --out <dir> \
                               --frames 0 18 [--border 0.09 0.47 0.0 0.72] [--feather 48]

tools_render_patch.py re-renders only the strip a fault occupies, at full frame dimensions
with everything outside the border empty. This shades those frames the way film_stitch shades
the film, crops to the shipped 1920x1080, and lays the valid strip over the corresponding
decoded film frame.

WHY OVER THE FILM'S OWN FRAMES. Everything outside the repair is already correct in the
shipped film, and taking it from there makes it correct BY CONSTRUCTION — no dependence on
this machine reproducing another machine's render. The repair is the only thing that has to
be re-rendered, so it is the only thing that is.

THE REPAIR ALSO FADES OUT IN TIME (--fade). A fresh render is sharper than the same picture
after a trip through Theora, so the strip does not just differ where the fault was — it is
crisper everywhere inside itself. Ending it abruptly on the frame the fault leaves shot would
pop that crispness away in one frame, which is a new artefact in place of the old one. Fading
it over the frames AFTER the fault has gone costs nothing (there is nothing left to repair
there) and lands the change where no edge in the picture announces it.

THE SEAM IS FEATHERED because the two sides are not bit-identical: one is a fresh render, the
other has been through Theora once. In flat fills they agree to about 1/255 and the seam would
be invisible anyway; along ink lines the codec rings and a hard edge could show. Feathering
over `feather` px cross-dissolves between two pictures of the same thing, which cannot band.
Only the INTERIOR edges are feathered — where the border runs off the side of the frame there
is nothing to blend into.
"""
import argparse
import os

import numpy as np
from PIL import Image

import film_stitch as fs

HERE = os.path.dirname(os.path.abspath(__file__))
CROP_W, CROP_H = 1920, 1080
RENDER_W, RENDER_H = 2400, 1080


def _centre_crop(a):
    x = (a.shape[1] - CROP_W) // 2
    y = (a.shape[0] - CROP_H) // 2
    return a[y:y + CROP_H, x:x + CROP_W]


def _ramp(n, feather, at_start):
    """A 0->1 ramp `feather` wide at one end of an axis of length n."""
    w = np.ones(n, np.float32)
    f = min(feather, n)
    if f <= 0:
        return w
    r = np.linspace(0.0, 1.0, f, dtype=np.float32)
    if at_start:
        w[:f] = r
    else:
        w[n - f:] = r[::-1]
    return w


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--patch", required=True)
    ap.add_argument("--orig", required=True, help="decoded film frames, f%03d.png, 1-based")
    ap.add_argument("--out", required=True)
    ap.add_argument("--frames", nargs=2, type=int, required=True)
    ap.add_argument("--border", nargs=4, type=float, default=[0.09, 0.47, 0.0, 0.72])
    ap.add_argument("--feather", type=int, default=48)
    ap.add_argument("--fade", nargs=2, type=int, default=None, metavar=("FROM", "TO"),
                    help="cross-fade the repair out across frames [FROM, TO); full strength "
                         "before FROM, absent from TO on")
    ap.add_argument("--sky", default="renders/loading/layers/L0_sky_wide.png")
    ap.add_argument("--report-only", action="store_true",
                    help="measure the render against the film, write nothing")
    a = ap.parse_args()
    patch = a.patch if os.path.isabs(a.patch) else os.path.join(HERE, a.patch)
    sky = a.sky if os.path.isabs(a.sky) else os.path.join(HERE, a.sky)
    os.makedirs(a.out, exist_ok=True)
    fs.set_size(RENDER_W, RENDER_H, sky=sky, shift_y=0.10)

    x0f, x1f, y0f, y1f = a.border
    # Border fractions are of the 2400-wide render, Y from the BOTTOM. Convert to rows and
    # columns of the shipped 1920x1080 crop, which starts 240 px in from the render's left.
    off = (RENDER_W - CROP_W) // 2
    cx0 = max(0, int(round(x0f * RENDER_W)) - off)
    cx1 = min(CROP_W, int(round(x1f * RENDER_W)) - off)
    cy0 = max(0, RENDER_H - int(round(y1f * RENDER_H)))
    cy1 = min(CROP_H, RENDER_H - int(round(y0f * RENDER_H)))
    print("valid strip in film coords: x %d..%d  y %d..%d" % (cx0, cx1, cy0, cy1))

    # Feather only where the strip has film on the other side of it.
    wx = np.ones(cx1 - cx0, np.float32)
    if cx0 > 0:
        wx *= _ramp(cx1 - cx0, a.feather, at_start=True)
    if cx1 < CROP_W:
        wx *= _ramp(cx1 - cx0, a.feather, at_start=False)
    wy = np.ones(cy1 - cy0, np.float32)
    if cy0 > 0:
        wy *= _ramp(cy1 - cy0, a.feather, at_start=True)
    if cy1 < CROP_H:
        wy *= _ramp(cy1 - cy0, a.feather, at_start=False)
    w = (wy[:, None] * wx[None, :])[..., None]

    for idx in range(a.frames[0], a.frames[1]):
        new = _centre_crop(fs.frame(patch, idx, 0.0)).astype(np.float32)
        old = np.asarray(Image.open(os.path.join(a.orig, "f%03d.png" % (idx + 1)))
                         .convert("RGB")).astype(np.float32)
        ns = new[cy0:cy1, cx0:cx1]
        os_ = old[cy0:cy1, cx0:cx1]
        d = np.abs(ns - os_).mean(axis=2)
        print("frame %3d  strip diff: mean %5.2f  median %5.2f  p95 %6.2f  frac>16 %.4f"
              % (idx, d.mean(), np.median(d), np.percentile(d, 95), (d > 16).mean()))
        if a.report_only:
            continue
        t = 1.0
        if a.fade is not None and idx >= a.fade[0]:
            span = max(1, a.fade[1] - a.fade[0])
            t = max(0.0, 1.0 - float(idx - a.fade[0] + 1) / span)
        out = old.copy()
        out[cy0:cy1, cx0:cx1] = ns * (w * t) + os_ * (1.0 - w * t)
        Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).save(
            os.path.join(a.out, "p%04d.png" % idx))
    print("done")


if __name__ == "__main__":
    main()
