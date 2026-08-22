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
# Stacking order, back to front — which is the order these are WRITTEN and therefore the
# order the loading screen stacks them. It is not the order they arrive in; that is
# sequence.json, written at the end, and it runs the other way (road first, sky last).
LAYERS = [
    ("03_city", "02_city"),
    ("04_bldg_far", "07_bldg_far"),
    ("05_bldg_near", "06_bldg_near"),
    ("06_street", "03_street"),
    ("07_props", "05_props"),
]
# Front to back: the road, then what stands on it, then the near buildings, the far ones,
# the city, and the sky last of all.
REVEAL = ["06_street.png", "07_props.png", "05_bldg_near.png", "04_bldg_far.png",
          "03_city.png", "02_sky.png"]
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


def _dominant(arr, want_green):
    """A representative colour out of an RGBA array — the median of the pixels that count.

    Median, not mean: the art is flat fills with ink outlines through it, and averaging drags
    every colour toward that ink. `want_green` picks out the grass (green channel ahead of the
    other two) rather than the road or the kerbs.
    """
    a = arr.reshape(-1, arr.shape[-1]).astype(np.int32)
    keep = a[:, 3] > 200 if a.shape[1] == 4 else np.ones(len(a), bool)
    if want_green:
        keep = keep & (a[:, 1] > a[:, 0] + 12) & (a[:, 1] > a[:, 2] + 12)
    sel = a[keep]
    if len(sel) == 0:
        sel = a
    med = np.median(sel[:, :3], axis=0).astype(int)
    return (int(med[0]), int(med[1]), int(med[2]), 255)


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
    args = ap.parse_args()
    d = args.dir if os.path.isabs(args.dir) else os.path.join(HERE, args.dir)
    out = args.out or os.path.join(d, "plates")
    sky = args.sky if os.path.isabs(args.sky) else os.path.join(HERE, args.sky)
    os.makedirs(out, exist_ok=True)

    # The film's widescreen geometry, so the stipple grid and the sky pan match it exactly.
    fs.set_size(2400, 1080, sky=sky, shift_y=0.10)

    # 02: the sky, at frame 0 — step_i 0, so no advance. It stacks second from the bottom
    # and arrives LAST, which is what finally hides the flat base underneath.
    sky_img = _centre_crop(fs.sky_for(0, 0.0).convert("RGBA"))
    sky_img.save(os.path.join(out, "02_sky.png"))
    print("wrote 02_sky.png %dx%d" % sky_img.size)

    plates = {}
    for name, tag in LAYERS:
        img = _centre_crop(Image.fromarray(layer_rgba(d, tag), "RGBA"))
        img.save(os.path.join(out, name + ".png"))
        plates[name] = img
        print("wrote %s.png %dx%d" % (name, img.size[0], img.size[1]))

    # 01: the empty world the sequence opens on — sky blue over grass green, split at the
    # half. Both colours are TAKEN FROM THE ART rather than picked: the blue is the graded
    # sky's own zenith, the green is the median of the street layer's grass. Nothing new is
    # invented, so the card cannot drift away from the film it introduces.
    base = Image.new("RGBA", sky_img.size)
    blue = _dominant(np.asarray(sky_img)[: sky_img.height // 6], want_green=False)
    green = _dominant(np.asarray(plates["06_street"]), want_green=True)
    base.paste(blue, (0, 0, base.width, base.height // 2))
    base.paste(green, (0, base.height // 2, base.width, base.height))
    base.save(os.path.join(out, "01_base.png"))
    print("wrote 01_base.png %dx%d  sky=%s grass=%s" % (base.width, base.height, blue, green))

    import json
    with open(os.path.join(out, "sequence.json"), "w") as f:
        json.dump({"reveal": REVEAL}, f, indent=2)
    print("wrote sequence.json: %s" % " -> ".join(r.split("_", 1)[1][:-4] for r in REVEAL))
    print("plates in %s" % out)


if __name__ == "__main__":
    main()
