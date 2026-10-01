#!/usr/bin/env python3
"""Turn a raw capsule render into its prints: a review print and a main-capsule-size print.

    python3 tools/steam_capsule/finish_render.py tools/steam_capsule/renders/plate.png [--shadows]

The print pass is the game's own since August (`stylize_shade.py`, with the parameters
`bake_sprite.py` uses): stipple stands for SHADE, read from the render's .shade.png mask (how
far each face turns from the sun), not from colour. It runs at each output's final size,
after the resize: printed at full size and shrunk, the 10 px dots turn to grain at the Steam
main capsule's scale and to a flat tint below it. With --shadows, ground in a cast shadow
(.shadow.png) prints as a dense band of dots too, as the loading film printed its shadows.
A warm look (render_earth_plate.py --look) leaves a .glow.png of its light sources, and they
get a soft bloom here. Its sides are renders of the same frame under the light it leans
toward at the plate's north-west end (.nw.png) and at its sea end (.se.png), blended in
before the print; or, for a look without them, a darkening ramp.

Then water goes back to flat map colour (.water.png), and the heavy outer line goes round
the plate only (.plate.png), scaled to the output. The sprites draw that line round their
whole silhouette, but on a diorama it would climb every chimney that rises past the plate's
edge; here it stops wherever anything stands in front.

Writes: _print.png, _print_on_navy.png and _labels.png at full size, and _main.png at 0.45
(the plate at about the height of Steam's 1232x706 main capsule).
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.normpath(os.path.join(HERE, "..", "..", ".claude", "skills", "blender-building-sprites"))
sys.path.insert(0, SKILL)
from stylize_shade import stylize  # noqa: E402

NAVY = (20, 28, 38, 255)
PLATE_LINE = (47, 59, 89)        # the sprites' synthesized outer line (sprite_export.py)
PLATE_LINE_PX = 5.0              # outside the plate's own ink, per 1536 px of width
PRINT = dict(spacing=10.0, dot_r=1.6, strength=0.22, lit=0.86, dark=0.56)   # the game's bake
SHADOW_SHADE = 0.40              # mask value for ground in a cast shadow: a dense band
TOP_SHADE = 0.85                 # shade value above which a face points up (a flat top reads 0.88)
SIZES = (("review", 1.0), ("main", 0.45))


def premult_resize(img, size):
    """Lanczos on premultiplied colour, so transparent edges do not bleed dark."""
    a = np.asarray(img.convert("RGBA")).astype(np.float32) / 255.0
    pm = np.concatenate([a[..., :3] * a[..., 3:4], a[..., 3:4]], -1)
    chans = [np.asarray(Image.fromarray(pm[..., i]).resize(size, Image.LANCZOS)) for i in range(4)]
    pm = np.clip(np.stack(chans, -1), 0, 1)
    al = pm[..., 3:4]
    rgb = np.where(al > 1e-4, pm[..., :3] / np.maximum(al, 1e-4), 0)
    return Image.fromarray((np.clip(np.concatenate([rgb, al], -1), 0, 1) * 255 + 0.5).astype(np.uint8))


def plate_line(img, plate_alpha, width_px):
    """Composite the heavy line under `img`: a band `width_px` wide round the plate's
    silhouette, kept only where nothing else is opaque."""
    a = np.asarray(img)[..., 3] > 128
    outside = ndimage.distance_transform_edt(~(plate_alpha > 128))
    band = (outside > 0) & (outside <= width_px) & ~a
    mask = Image.fromarray((band * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
    under = Image.new("RGBA", img.size, PLATE_LINE + (0,))
    under.putalpha(mask)
    return Image.alpha_composite(under, img)


def shade_mask(stem, shadows):
    """The shading mask as RGBA; with shadows, sun-facing ground the sun cannot reach is
    pulled down to SHADOW_SHADE."""
    m = np.asarray(Image.open(stem + ".shade.png").convert("RGBA")).astype(np.float32) / 255.0
    if shadows and os.path.exists(stem + ".shadow.png"):
        lum = m[..., 0] * 0.2126 + m[..., 1] * 0.7152 + m[..., 2] * 0.0722
        lit = np.asarray(Image.open(stem + ".shadow.png").convert("L")).astype(np.float32) / 255.0
        # Upward faces only (the ground, roofs, decks): that is where a shadow anchors a
        # building. On walls and trees it only adds speckle, since canopy clumps and busy
        # facades shade parts of themselves.
        cast = (lit < 0.06) & (lum > TOP_SHADE) & (m[..., 3] > 0.5)
        m[cast, :3] = SHADOW_SHADE
    return Image.fromarray((m * 255 + 0.5).astype(np.uint8))


FALL_DIR = (0.951, 0.309)        # on screen, from the plate's north-west toward the sea
FALL_COOL, FALL_WARM = (0.90, 0.94, 1.06), (1.04, 1.00, 0.95)


def ramp_t(alpha):
    """Each pixel's place along FALL_DIR, 0 at the plate's north-west end and 1 at its sea
    end, from the plate's own extent (alpha, 0..1)."""
    h, w = alpha.shape
    proj = np.arange(w)[None, :] * FALL_DIR[0] + np.arange(h)[:, None] * FALL_DIR[1]
    on = alpha > 0.5
    p0, p1 = proj[on].min(), proj[on].max()
    return np.clip((proj - p0) / max(p1 - p0, 1.0), 0.0, 1.0)


def side_blend(raw, other, ramp, rising):
    """Blend a render made under one side's light into the look's own along the plate: the
    north-west side's fully up to ramp[0] and easing out to nothing at ramp[1]; the sea
    side's (rising) from nothing at ramp[0] to fully at ramp[1]."""
    a = np.asarray(raw).astype(np.float32)
    b = np.asarray(other.convert("RGBA")).astype(np.float32)
    u = np.clip((ramp_t(a[..., 3] / 255.0) - ramp[0]) / (ramp[1] - ramp[0]), 0.0, 1.0)
    w = u * u * (3.0 - 2.0 * u)
    w = (w if rising else 1.0 - w)[..., None]
    out = a.copy()
    out[..., :3] = a[..., :3] * (1.0 - w) + b[..., :3] * w
    return Image.fromarray((out + 0.5).astype(np.uint8))


def falloff(img, dark, light):
    """Darken the plate toward the north-west and lift it toward the sea, as the AI concept
    does (owner): a smooth ramp along FALL_DIR over the plate, cooler where it is dark and
    warmer where it is light. Lamps are painted after it, so they stay bright in the dark."""
    a = np.asarray(img).astype(np.float32) / 255.0
    t = ramp_t(a[..., 3])
    t = t * t * (3.0 - 2.0 * t)
    f = dark + (light - dark) * t
    tint = np.stack([FALL_COOL[c] + (FALL_WARM[c] - FALL_COOL[c]) * t for c in range(3)], -1)
    rgb = np.clip(a[..., :3] * f[..., None] * tint, 0.0, 1.0)
    return Image.fromarray((np.concatenate([rgb, a[..., 3:4]], -1) * 255 + 0.5).astype(np.uint8))


HAZE_RGB = (0.25, 0.22, 0.20)    # smoke: a dark warm grey, as the concept's hangs over its pit


def haze(img, opacity, t_end, seed=3):
    """A smoke haze over the plate's north-west, the mine's side (owner): the smoke's warm grey
    laid over the plate at `opacity` at its north-west end, thinning to nothing at `t_end`
    along it, in billows (smooth noise at two scales) so it reads as smoke, not a tint. Lamps
    are painted after it, so they shine through."""
    a = np.asarray(img).astype(np.float32) / 255.0
    h, w = a.shape[:2]
    u = np.clip(ramp_t(a[..., 3]) / t_end, 0.0, 1.0)
    ramp = 1.0 - u * u * (3.0 - 2.0 * u)
    rng = np.random.default_rng(seed)
    small = (max(1, h // 8), max(1, w // 8))              # noise on a coarse grid, then up
    billows = np.zeros(small, np.float32)
    for sigma, amp in ((small[1] * 0.035, 0.65), (small[1] * 0.012, 0.35)):
        f = ndimage.gaussian_filter(rng.standard_normal(small).astype(np.float32), sigma)
        billows += amp * f / (f.std() + 1e-6)
    billows = np.asarray(Image.fromarray(billows).resize((w, h), Image.BICUBIC))
    billows = np.clip(0.5 + billows * 0.22, 0.0, 1.0)
    alpha = (opacity * ramp * (0.55 + 0.45 * billows) * (a[..., 3] > 0.5))[..., None]
    rgb = a[..., :3] * (1.0 - alpha) + np.array(HAZE_RGB, np.float32) * alpha
    return Image.fromarray((np.clip(np.concatenate([rgb, a[..., 3:4]], -1), 0, 1) * 255 + 0.5).astype(np.uint8))


INK = np.array((65, 74, 101), np.float32) / 255.0    # the Freestyle ink as it prints


def paint_lamps(img, glow):
    """Lay the light sources over the print in their own colour: the render's view (AgX)
    takes a bright amber most of the way to white, the glow pass (Standard) keeps it. A lamp
    only ever brightens (its soft edge would otherwise darken what is round it), and never
    covers the ink: the glow pass has no lines, so a line drawn in front of a lamp (a blade's
    outline over a lit window) would be painted out."""
    a = np.asarray(img).astype(np.float32) / 255.0
    g = np.asarray(glow.convert("RGB")).astype(np.float32) / 255.0
    lum = np.array((0.2126, 0.7152, 0.0722), np.float32)
    cover = np.clip(g.max(-1, keepdims=True) / 0.30, 0.0, 1.0)
    brighter = np.clip(((g @ lum) - (a[..., :3] @ lum))[..., None] / 0.10, 0.0, 1.0)
    ink = (np.abs(a[..., :3] - INK).max(-1, keepdims=True) < 0.10).astype(np.float32)
    w = cover * brighter * (1.0 - ink)
    rgb = a[..., :3] * (1.0 - w) + g * w
    return Image.fromarray((np.concatenate([rgb, a[..., 3:4]], -1) * 255 + 0.5).astype(np.uint8))


def pit_rise(img, pit, scale, strength=0.34):
    """Light rising out of the mine's pit (owner): a warm glow over the pit, tall and soft,
    screened over the print (after the smoke haze, so it lights the smoke)."""
    a = np.asarray(img).astype(np.float32) / 255.0
    h, w = a.shape[:2]
    cx, cy, r = (v * scale for v in pit)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    g = np.exp(-(((xx - cx) / (r * 0.95)) ** 2) - (((yy - (cy - r * 0.55)) / (r * 1.5)) ** 2))
    glow = (np.array((1.0, 0.70, 0.36), np.float32) * (strength * g)[..., None])
    rgb = 1.0 - (1.0 - a[..., :3]) * (1.0 - glow)
    return Image.fromarray((np.concatenate([rgb, a[..., 3:4]], -1) * 255 + 0.5).astype(np.uint8))


def bloom(img, glow, strength):
    """Screen a soft halo of the light sources (.glow.png) over the print: a tight one and a
    wide one, sized to the output, as a lens blooms round a lamp."""
    a = np.asarray(img).astype(np.float32) / 255.0
    g = np.asarray(glow.convert("RGB")).astype(np.float32) / 255.0
    w = img.size[0]
    halo = np.zeros_like(g)
    for radius, gain in ((0.0020 * w, 0.9), (0.0085 * w, 0.7)):
        halo += gain * np.stack([ndimage.gaussian_filter(g[..., c], radius) for c in range(3)], -1)
    halo = np.clip(halo * strength, 0.0, 1.0)
    rgb = 1.0 - (1.0 - a[..., :3]) * (1.0 - halo)
    return Image.fromarray((np.concatenate([rgb, a[..., 3:4]], -1) * 255 + 0.5).astype(np.uint8))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("render")
    ap.add_argument("--shadows", action="store_true", help="print cast shadows as dots too")
    args = ap.parse_args()
    stem = os.path.splitext(args.render)[0]
    raw = Image.open(args.render).convert("RGBA")
    mask = shade_mask(stem, args.shadows)
    water = Image.open(stem + ".water.png").convert("L")
    plate = Image.open(stem + ".plate.png").convert("RGBA").split()[3]
    glow, glow_gain, fall, smoke, pit = None, 0.0, None, None, None
    if os.path.exists(stem + ".look.json"):
        look = json.load(open(stem + ".look.json"))
        fall = look.get("falloff")
        smoke = look.get("haze")
        pit = look.get("pit_glow")
        for side, ramp in (look.get("sides") or {}).items():
            if os.path.exists(stem + ".%s.png" % side):
                raw = side_blend(raw, Image.open(stem + ".%s.png" % side), ramp, side == "se")
        glow_gain = look.get("glow", 0.0)
        if glow_gain > 0 and os.path.exists(stem + ".glow.png"):
            glow = Image.open(stem + ".glow.png")
    tmp = tempfile.mkdtemp(prefix="print_")
    for name, scale in SIZES:
        size = (int(round(raw.width * scale)), int(round(raw.height * scale)))
        r = raw if scale == 1.0 else premult_resize(raw, size)
        m = mask if scale == 1.0 else mask.resize(size, Image.LANCZOS)
        rp, mp, pp = (os.path.join(tmp, "%s_%s.png" % (name, k)) for k in ("raw", "mask", "print"))
        r.save(rp)
        m.save(mp)
        stylize(rp, mp, pp, **PRINT)
        out = np.asarray(Image.open(pp).convert("RGBA")).copy()
        wm = np.asarray(water.resize(size, Image.LANCZOS)) > 127
        out[wm] = np.asarray(r)[wm]
        img = plate_line(Image.fromarray(out), np.asarray(plate.resize(size, Image.LANCZOS)),
                         max(1.2, PLATE_LINE_PX * size[0] / 1536.0))
        if fall:
            img = falloff(img, *fall)
        if smoke:
            img = haze(img, *smoke)
        if pit:
            img = pit_rise(img, pit, scale)
        bg = Image.new("RGBA", img.size, NAVY)
        bg.alpha_composite(img)
        if glow is not None:
            g = glow if scale == 1.0 else glow.resize(size, Image.LANCZOS)
            img = bloom(paint_lamps(img, g), g, glow_gain)
            bg = bloom(paint_lamps(bg, g), g, glow_gain)
        if name == "review":
            img.save(stem + "_print.png")
            bg.convert("RGB").save(stem + "_print_on_navy.png")
        else:
            bg.convert("RGB").save(stem + "_%s.png" % name)
    for f in os.listdir(tmp):
        os.remove(os.path.join(tmp, f))
    os.rmdir(tmp)
    if os.path.exists(stem + ".probe.json"):
        subprocess.run([sys.executable, os.path.join(HERE, "label_render.py"), args.render,
                        stem + "_print.png", stem + "_labels.png"], check=True)


if __name__ == "__main__":
    main()
