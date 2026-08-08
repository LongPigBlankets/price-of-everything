#!/usr/bin/env python3
"""Cross-fade a level set in place: the building upgrades without moving.

Takes the per-level stills rendered from ONE fixed camera (level_lineup.build_stack) and
blends between them, so L1 becomes L2 becomes L3 on the same ground. A free camera cannot
show this, and fading inside Blender cannot either — Freestyle draws its ink at full
opacity regardless of material alpha, so a half-faded building keeps solid black outlines
over a ghost. Blending finished FRAMES is the only way the ink fades with the building.

Blending is done PREMULTIPLIED. These are straight-alpha PNGs, and interpolating straight
RGB across a transparent edge pulls in whatever colour sits in the fully-transparent
pixels — a dark halo around every silhouette.

    python3 xfade_sequence.py renders/xfade --out renders/xfade/seq --fps 30
"""
import argparse
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

GAME_FONT = ("/Users/crisu/Price of Everything/price-of-everything/"
             "price-of-everything-0.1/assets/fonts/BebasNeue-Regular.ttf")
LABEL_RGB = (0xFF, 0xF2, 0xC9)      # the UI button foreground, so captions match the game


def _label_layer(text, size, font_path=GAME_FONT, frac=0.062, pad_frac=0.055):
    """One caption as its own premultiplied RGBA layer, so it can fade with the building."""
    w, h = size
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    if not text:
        a = np.zeros((h, w, 1)); return np.zeros((h, w, 3)), a
    try:
        font = ImageFont.truetype(font_path, int(round(h * frac)))
    except OSError:
        font = ImageFont.load_default()
    d = ImageDraw.Draw(layer)
    box = d.textbbox((0, 0), text, font=font)
    tw, th = box[2] - box[0], box[3] - box[1]
    x = (w - tw) / 2 - box[0]
    y = h - h * pad_frac - th - box[1]
    d.text((x, y), text, font=font, fill=LABEL_RGB + (255,))
    a = np.asarray(layer, dtype=np.float64)[..., 3:4] / 255.0
    rgb = np.asarray(layer, dtype=np.float64)[..., :3] / 255.0
    return rgb * a, a                # premultiplied, same convention as the frames


def _load(path):
    a = np.asarray(Image.open(path).convert("RGBA"), dtype=np.float64) / 255.0
    rgb, alpha = a[..., :3], a[..., 3:4]
    return rgb * alpha, alpha          # premultiplied


def _save(prem, alpha, path, bg=None):
    if bg is not None:
        b = np.asarray(bg, dtype=np.float64).reshape(1, 1, 3) / 255.0
        out = prem + b * (1.0 - alpha)
        img = np.concatenate([out, np.ones_like(alpha)], axis=-1)
    else:
        rgb = np.divide(prem, alpha, out=np.zeros_like(prem), where=alpha > 1e-6)
        img = np.concatenate([rgb, alpha], axis=-1)
    Image.fromarray((np.clip(img, 0, 1) * 255).round().astype(np.uint8), "RGBA").save(path)


def build(folder, out, levels=(1, 2, 3), hold=24, fade=18, tail=36, loop=True, bg=None,
          labels=None):
    frames = [_load(os.path.join(folder, "L%d.png" % lv)) for lv in levels]
    size = Image.open(os.path.join(folder, "L%d.png" % levels[0])).size
    caps = [_label_layer(labels[i] if labels and i < len(labels) else "", size)
            for i in range(len(levels))]
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        if f.endswith(".png"):
            os.remove(os.path.join(out, f))

    plan = []                      # (from_idx, to_idx, t) — t=0 is pure `from`
    for i in range(len(frames)):
        last = i == len(frames) - 1
        for _ in range(tail if last else hold):
            plan.append((i, i, 0.0))
        if not last:
            for s in range(fade):
                plan.append((i, i + 1, (s + 1) / (fade + 1)))
    if loop:
        for s in range(fade):
            plan.append((len(frames) - 1, 0, (s + 1) / (fade + 1)))

    for n, (a, b, t) in enumerate(plan):
        if a == b:
            prem, alpha = frames[a]
            cp, ca = caps[a]
        else:
            pa, aa = frames[a]
            pb, ab = frames[b]
            prem = pa * (1 - t) + pb * t
            alpha = aa * (1 - t) + ab * t
            # The caption crosses on the SAME curve as the building, so the label always
            # names what you are looking at rather than lagging or leading it.
            ka, kb = caps[a], caps[b]
            cp = ka[0] * (1 - t) + kb[0] * t
            ca = ka[1] * (1 - t) + kb[1] * t
        # Caption composited OVER the building, premultiplied: dst = src + dst*(1-a_src).
        prem = cp + prem * (1.0 - ca)
        alpha = ca + alpha * (1.0 - ca)
        _save(prem, alpha, os.path.join(out, "f%04d.png" % n), bg=bg)
    return {"frames": len(plan), "out": out}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("folder")
    ap.add_argument("--out", required=True)
    ap.add_argument("--hold", type=int, default=24)
    ap.add_argument("--fade", type=int, default=18)
    ap.add_argument("--tail", type=int, default=36)
    ap.add_argument("--no-loop", action="store_true")
    ap.add_argument("--bg", default=None, help="e.g. 14,22,38 to flatten onto a colour")
    ap.add_argument("--labels", default=None, help="comma-separated captions, one per level")
    args = ap.parse_args()
    bg = [int(v) for v in args.bg.split(",")] if args.bg else None
    labels = args.labels.split(",") if args.labels else None
    print(build(args.folder, args.out, hold=args.hold, fade=args.fade,
                tail=args.tail, loop=not args.no_loop, bg=bg, labels=labels))
