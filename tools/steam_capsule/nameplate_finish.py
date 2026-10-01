#!/usr/bin/env python3
"""Lay a nameplate render (transparent) on the capsule's navy with the shadow it casts (soft,
falling away from the light: left and a little down when it comes from the right, down and
right when it comes from the top left) and a soft glow round its fire.

    python3 tools/steam_capsule/nameplate_finish.py tools/steam_capsule/renders/nameplate_v1.png

Writes <render>_on_navy.png beside it.
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

NAVY = (20, 28, 38)
# The shadow's offset x and y (image y down) and blur, as shares of the width, and its opacity,
# by where the light comes from (nameplate.py writes <render>.light.json).
SHADOWS = {"right": (-0.022, 0.012, 0.010, 0.55), "topleft": (0.018, 0.020, 0.010, 0.55),
           "topleft-high": (0.010, 0.012, 0.009, 0.55)}   # the high sun casts short shadows


GLOW = ((0.006, 0.55), (0.022, 0.40))    # bloom: blur radius (share of the width), strength


def bloom(img, glow=None):
    """A soft glow round the plate's fire (the forge, embers, sparks, the white-hot feet of the
    coal letters), blurred at two radii and screened back over, onto the plate and past its
    edge. The fire is the render's glow pass (nameplate.py writes <render>.glow.png: the frame
    with every light off, so only what glows shows); without one, the render's bright, warm
    pixels stand in for it, which lit brass can be mistaken for."""
    a = np.asarray(img).astype(np.float32) / 255.0
    rgb, al = a[..., :3] * a[..., 3:4], a[..., 3]
    if glow is not None:
        g = np.asarray(glow.convert("RGBA")).astype(np.float32) / 255.0
        src = g[..., :3] * g[..., 3:4]
    else:
        warm = (rgb[..., 0] > 0.55) & (rgb[..., 0] > rgb[..., 2] + 0.25)
        src = rgb * warm[..., None]
    w = img.size[0]
    halo = np.zeros_like(src)
    for radius, gain in GLOW:
        halo += gain * np.stack([ndimage.gaussian_filter(src[..., c], radius * w) for c in range(3)], -1)
    halo = np.clip(halo, 0.0, 1.0)
    out_rgb = 1.0 - (1.0 - rgb) * (1.0 - halo)
    out_a = np.clip(np.maximum(al, halo.max(-1)), 0.0, 1.0)
    unpremult = np.where(out_a[..., None] > 1e-4, out_rgb / np.maximum(out_a[..., None], 1e-4), 0.0)
    return Image.fromarray((np.clip(np.concatenate([unpremult, out_a[..., None]], -1), 0, 1) * 255 + 0.5)
                           .astype(np.uint8))


def light_of(path):
    """Where the render's light came from, as a SHADOWS key (nameplate.py writes
    <render>.light.json)."""
    side = os.path.splitext(path)[0] + ".light.json"
    if not os.path.exists(side):
        return "right"
    j = json.load(open(side))
    light = j.get("light", "right")
    return light + "-high" if light == "topleft" and j.get("sun") == "high" else light


def glow_of(path):
    g = os.path.splitext(path)[0] + ".glow.png"
    return Image.open(g) if os.path.exists(g) else None


def main(path):
    img = bloom(Image.open(path).convert("RGBA"), glow_of(path))
    w, h = img.size
    dx, dy, blur, opacity = SHADOWS[light_of(path)]
    alpha = img.split()[3]
    shadow = Image.new("L", (w, h), 0)
    shadow.paste(alpha, (int(dx * w), int(dy * w)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur * w))
    base = Image.new("RGBA", (w, h), NAVY + (255,))
    dark = Image.new("RGBA", (w, h), (4, 6, 9, 255))
    dark.putalpha(Image.fromarray((np.asarray(shadow).astype(np.float32) * opacity).astype(np.uint8)))
    base.alpha_composite(dark)
    base.alpha_composite(img)
    out = os.path.splitext(path)[0] + "_on_navy.png"
    base.convert("RGB").save(out)
    print("wrote", out)


if __name__ == "__main__":
    main(sys.argv[1])
