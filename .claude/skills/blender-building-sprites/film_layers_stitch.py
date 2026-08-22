#!/usr/bin/env python3
"""Turn the frame-0 layer renders into stackable RGBA plates for the loading screen.

    python3 film_layers_stitch.py [--dir renders/loading/layers_frame0] [--out <dir>]

tools_render_layers.py renders each layer's three passes (colour / geometric wall mask /
ground mask) with only that collection visible. This applies the FILM'S OWN post — the same
stipple grid, the same wall and ground shading bands, from film_stitch — and writes each layer
as RGBA instead of compositing it over the sky.

That difference is the entire point. film_stitch.frame() ends with

    out = rgb * a + sky * (1 - a)

which flattens the frame onto the sky and throws the alpha away. A layer needs the alpha kept:
it has to be a cutout, so the layer under it shows through everywhere its own objects are not.
Stack the plates back to front and you have the film's first frame; stop part way and you have
it partly built, which is what the loading screen shows while the game loads.

The sky plate is not rendered — the film's colour pass hides the sky plane because AgX crushes
the emission bands, and the vivid sky only exists in post. So plate 01 is that same post sky,
taken through the same sky_for() the film uses.

Output is cropped 2400 -> 1920 about the centre, because the shipped film is the 16:9 master
and FILM_RUNBOOK says the centre 1920x1080 of the wide render is the approved composition at
1:1. Plates and film therefore land on the same pixels.
"""
import argparse
import os

import numpy as np
from PIL import Image

import film_stitch as fs

HERE = os.path.dirname(os.path.abspath(__file__))
LAYERS = ["02_city", "03_street", "04_buildings"]
CROP_W, CROP_H = 1920, 1080


def layer_rgba(dirpath, tag):
    """One layer, shaded the way the film shades it, with its alpha intact."""
    def _read(suffix):
        p = os.path.join(dirpath, tag + suffix + ".png")
        return np.asarray(Image.open(p).convert("RGBA").resize((fs.W, fs.H), Image.LANCZOS)
                          ).astype(np.float32) / 255.0

    c, g, n = _read(""), _read("_geo"), _read("_gnd")
    rgb, alpha = c[..., :3].copy(), c[..., 3]
    lum = fs._luma(rgb)
    glass = (rgb[..., 2] > rgb[..., 0] * 1.45) & (lum < 0.38)
    is_gnd = n[..., 3] > 0.5
    has_mask = (g[..., 3] > 0.5) | is_gnd
    from scipy.ndimage import binary_erosion
    body = binary_erosion((alpha > 0.01) & ~glass & has_mask, np.ones((5, 5), bool))
    cov = np.where(is_gnd, fs._bands(fs._luma(n), fs.GND_CUTS),
                   fs._bands(fs._luma(g), fs.WALL_CUTS))
    k = (fs.DOT_STRENGTH * cov * body)[..., None]
    rgb = rgb * (1 - k) + fs.INK[None, None, :] * k
    out = np.concatenate([rgb, alpha[..., None]], axis=2)
    return (np.clip(out, 0, 1) * 255).astype(np.uint8)


def _centre_crop(img):
    if img.width == CROP_W and img.height == CROP_H:
        return img
    x = (img.width - CROP_W) // 2
    y = (img.height - CROP_H) // 2
    return img.crop((x, y, x + CROP_W, y + CROP_H))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="renders/loading/layers_frame0")
    ap.add_argument("--out", default=None, help="where the plates go (default: --dir/plates)")
    ap.add_argument("--sky", default="renders/loading/layers/L0_sky_wide.png")
    ap.add_argument("--film", default=None, help="film to take the final frame-0 plate from")
    args = ap.parse_args()
    d = args.dir if os.path.isabs(args.dir) else os.path.join(HERE, args.dir)
    out = args.out or os.path.join(d, "plates")
    sky = args.sky if os.path.isabs(args.sky) else os.path.join(HERE, args.sky)
    os.makedirs(out, exist_ok=True)

    # The film's widescreen geometry, so the stipple grid and the sky pan match it exactly.
    fs.set_size(2400, 1080, sky=sky, shift_y=0.10)

    # 01: the sky, at frame 0 — step_i 0, so no advance.
    sky_img = _centre_crop(fs.sky_for(0, 0.0).convert("RGBA"))
    sky_img.save(os.path.join(out, "01_sky.png"))
    print("wrote 01_sky.png %dx%d" % sky_img.size)

    for tag in LAYERS:
        img = _centre_crop(Image.fromarray(layer_rgba(d, tag), "RGBA"))
        img.save(os.path.join(out, tag + ".png"))
        print("wrote %s.png %dx%d" % (tag, img.size[0], img.size[1]))

    # 05: the film's own first frame, opaque. A per-layer render cannot carry the shadows
    # buildings cast onto a road that lives in another layer, so the sequence ends on the
    # truth rather than on an approximation of it — and the props arrive with the shading,
    # which is what the last step should look like landing.
    if args.film:
        import subprocess
        tmp = os.path.join(out, "_frame0.png")
        subprocess.check_call(["ffmpeg", "-y", "-loglevel", "error", "-i", args.film,
                               "-vf", "select=eq(n\,0)", "-vframes", "1", tmp])
        full = _centre_crop(Image.open(tmp).convert("RGBA"))
        full.save(os.path.join(out, "05_full.png"))
        os.remove(tmp)
        print("wrote 05_full.png %dx%d (from the film)" % full.size)
    print("plates in %s" % out)


if __name__ == "__main__":
    main()
