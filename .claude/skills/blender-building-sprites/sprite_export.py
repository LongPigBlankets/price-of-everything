#!/usr/bin/env python3
"""Square-canvas export for one building's level set, plus the heavy OUTER contour.

    python sprite_export.py <renders_dir> <name> [--size 800] [--pad 6] [--levels 1,2,3]

Expects, in `renders_dir`, one 1024 render per level plus its shading mask:
    <name>_L<n>.png  and  <name>_L<n>_mask.png       (both written by render_sprite.py)
Writes, alongside them:
    <name>_lvl<n>.png  and  <name>_lvl<n>_mask.png   (cropped, scaled, contoured)

Then run the print pass at FINAL size:
    python stylize_shade.py <name>_lvl<n>.png <name>_lvl<n>_mask.png <name>_lvl<n>.png

------------------------------------------------------------------------------------------
THE SHARED SCALE. Every level is cropped to its own alpha bbox and then scaled by ONE factor,
set by the reference level's longest side. The empire view draws every sprite in a fixed box,
so relative building size can only come from the PNG content: without a shared scale an L1
shack fills its canvas exactly as an L3 works does. Only the reference level reaches the
`pad` margin — the smaller levels are deliberately inset, and that inset IS the size signal.
Do not "fix" it by re-cropping them tight.

Pick the reference by MEASURING (largest max-dimension), never by eye: on the factory, L1 was
taller than L3 while L3 was widest, and using a non-maximal ref scales another level past the
canvas and clips it. This module does it automatically.

THE MASK RIDES ALONG. It is cropped by the same box and scaled by the same factor, or the
stipple lands on the wrong faces.
"""
import argparse
import os

import numpy as np
from PIL import Image, ImageFilter

# Sampled from the shipped furnace sprite's own contour, so re-baked and legacy sprites match.
CONTOUR_RGB = (47, 59, 89)


def outer_contour(im, r_out=4, rc=13, colour=CONTOUR_RGB):
    """The set's heavy outer line, on the OUTERMOST boundary of each component only.

    Freestyle's `contour` lineset cannot do this and is switched off upstream. It is view-map
    based, so it draws the heavy line around every region of background — including the slot
    between two of a component's own pipes and every hole inside a pylon's lattice. There is
    no lineset selector for "outermost boundary of a connected component".

    In 2D it is easy. A morphological CLOSING at radius `rc` fills any background pocket
    narrower than about 2*rc, which classifies pipe slots, lattice holes and the notches
    between tie-rods as INTERIOR. The contour band is a dilation of the true alpha by `r_out`,
    suppressed wherever it falls in such a pocket. Because the band is always a dilation of
    real geometry, nothing is ever drawn floating across a gap.

    `rc` is the one number to tune: raise it and wider gaps count as interior; lower it and
    genuine background between separate components starts losing its line.
    """
    a = np.asarray(im)[..., 3] > 128
    A = Image.fromarray((a * 255).astype(np.uint8))
    k_close = 2 * rc + 1
    interior = np.asarray(A.filter(ImageFilter.MaxFilter(k_close))
                           .filter(ImageFilter.MinFilter(k_close))) > 128
    band = (np.asarray(A.filter(ImageFilter.MaxFilter(2 * r_out + 1))) > 128) & ~a
    band &= ~(interior & ~a)
    mask = Image.fromarray((band * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
    under = Image.new("RGBA", im.size, tuple(colour) + (0,))
    under.putalpha(mask)
    return Image.alpha_composite(under, im)


def export(src_dir, name, size=800, pad=6, levels=(1, 2, 3), contour=True):
    def path(suffix):
        return os.path.join(src_dir, suffix)

    src, msk = {}, {}
    for L in levels:
        im = Image.open(path("%s_L%d.png" % (name, L))).convert("RGBA")
        src[L] = outer_contour(im) if contour else im
        mp = path("%s_L%d_mask.png" % (name, L))
        msk[L] = Image.open(mp).convert("RGBA") if os.path.exists(mp) else None

    box = {L: src[L].split()[3].getbbox() for L in levels}
    crop = {L: src[L].crop(box[L]) for L in levels}
    ref = max(levels, key=lambda L: max(crop[L].size))
    factor = (size - 2 * pad) / float(max(crop[ref].size))
    print("%s: ref = L%d at %dx%d, scale %.4f"
          % (name, ref, crop[ref].size[0], crop[ref].size[1], factor))

    for L in levels:
        w, h = crop[L].size
        nw, nh = max(1, round(w * factor)), max(1, round(h * factor))
        pos = ((size - nw) // 2, (size - nh) // 2)

        out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        out.alpha_composite(crop[L].resize((nw, nh), Image.LANCZOS), pos)
        out.save(path("%s_lvl%d.png" % (name, L)))

        if msk[L] is not None:
            mo = Image.new("RGBA", (size, size), (0, 0, 0, 0))
            mo.alpha_composite(msk[L].crop(box[L]).resize((nw, nh), Image.LANCZOS), pos)
            mo.save(path("%s_lvl%d_mask.png" % (name, L)))

        m = out.split()[3].getbbox()
        print("  L%d: %dx%d -> %dx%d   margins L%d R%d T%d B%d"
              % (L, w, h, nw, nh, m[0], size - m[2], m[1], size - m[3]))
    return ref


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("src_dir")
    ap.add_argument("name")
    ap.add_argument("--size", type=int, default=800)
    ap.add_argument("--pad", type=int, default=6)
    ap.add_argument("--levels", default="1,2,3")
    ap.add_argument("--no-contour", action="store_true",
                    help="skip the synthesized outer line (renders that still carry "
                         "Freestyle's own contour lineset)")
    k = ap.parse_args()
    export(k.src_dir, k.name, size=k.size, pad=k.pad,
           levels=tuple(int(v) for v in k.levels.split(",")), contour=not k.no_contour)
