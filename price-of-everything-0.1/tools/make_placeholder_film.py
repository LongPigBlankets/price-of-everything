"""Placeholder loading film, until the Blender dolly render lands.

    python tools/make_placeholder_film.py

Writes assets/loading/film.ogv — 2400x1080, 30 fps, 45 s of Ogg Theora, which is the
format Godot decodes natively and the size FILM_RUNBOOK.md specifies for the real thing.
It exists so the loading screen's film path can be built and MEASURED before the render
is finished: the decode cost that matters is driven by resolution and frame rate, and
those are the real ones here.

It is deliberately not trying to be the film. Two silhouette strips panning at different
rates over the game's navy — enough parallax to see a stutter instantly, in the right
palette, and obviously a stand-in. Drop the real film at the same path and delete this.
"""

import os
import subprocess
import sys
from PIL import Image, ImageDraw

W, H = 2400, 1080
SECONDS = 45
FPS = 30

SKY_TOP = (4, 15, 27)
SKY_BOT = (10, 42, 66)
FAR_INK = (16, 52, 76)
NEAR_INK = (5, 20, 34)
ACCENT = (230, 179, 74)
OUT_DIR = os.path.join("assets", "loading")
OUT = os.path.join(OUT_DIR, "film.ogv")


def _sky(width, height):
    img = Image.new("RGB", (width, height))
    d = ImageDraw.Draw(img)
    for y in range(height):
        t = y / float(height - 1)
        d.line([(0, y), (width, y)],
               fill=tuple(int(a + (b - a) * t) for a, b in zip(SKY_TOP, SKY_BOT)))
    return img


def _skyline(width, height, ink, base_y, scale, seed, lit=False):
    """A run of sheds, chimneys and gantries along `base_y`. Deterministic from `seed`."""
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rnd = _Rand(seed)
    x = -200
    while x < width + 200:
        kind = rnd.pick(4)
        if kind == 0:                                    # shed with a saw-tooth roof
            w = int(rnd.between(160, 340) * scale)
            h = int(rnd.between(90, 170) * scale)
            d.rectangle([x, base_y - h, x + w, base_y], fill=ink)
            step = max(18, int(46 * scale))
            for sx in range(x, x + w, step):
                d.polygon([(sx, base_y - h), (sx + step // 2, base_y - h - step // 2),
                           (sx + step, base_y - h)], fill=ink)
        elif kind == 1:                                  # chimney
            w = int(rnd.between(26, 44) * scale)
            h = int(rnd.between(260, 480) * scale)
            d.polygon([(x, base_y), (x + w, base_y),
                       (x + int(w * 0.78), base_y - h), (x + int(w * 0.22), base_y - h)], fill=ink)
            d.rectangle([x + int(w * 0.14), base_y - h - int(10 * scale),
                         x + int(w * 0.86), base_y - h], fill=ink)
            w += int(rnd.between(80, 200) * scale)
        elif kind == 2:                                  # gantry / cooling frame
            w = int(rnd.between(200, 320) * scale)
            h = int(rnd.between(120, 220) * scale)
            t = max(3, int(9 * scale))
            d.rectangle([x, base_y - t, x + w, base_y], fill=ink)
            d.rectangle([x, base_y - h, x + t, base_y], fill=ink)
            d.rectangle([x + w - t, base_y - h, x + w, base_y], fill=ink)
            d.rectangle([x, base_y - h, x + w, base_y - h + t], fill=ink)
            for i in range(1, 4):                        # cross-bracing
                bx = x + int(w * i / 4.0)
                d.line([(bx, base_y - h), (bx + int(w / 8.0), base_y)], fill=ink, width=t // 2 or 1)
        else:                                            # block with lit windows
            w = int(rnd.between(120, 260) * scale)
            h = int(rnd.between(110, 210) * scale)
            d.rectangle([x, base_y - h, x + w, base_y], fill=ink)
            if lit:
                gap = max(14, int(34 * scale))
                for wy in range(base_y - h + gap, base_y - gap, gap):
                    for wx in range(x + gap, x + w - gap, gap):
                        if rnd.pick(3) == 0:
                            d.rectangle([wx, wy, wx + max(2, int(9 * scale)),
                                         wy + max(2, int(12 * scale))], fill=ACCENT)
        x += w + int(rnd.between(40, 150) * scale)
    return img


class _Rand:
    """Tiny deterministic LCG — no numpy, no global random state to disturb."""

    def __init__(self, seed):
        self.s = seed & 0x7FFFFFFF

    def _next(self):
        self.s = (self.s * 1103515245 + 12345) & 0x7FFFFFFF
        return self.s

    def pick(self, n):
        return self._next() % n

    def between(self, lo, hi):
        return lo + self._next() % max(1, (hi - lo))


def main():
    far_w, near_w = 4200, 9600
    far = _sky(far_w, H)
    far.paste(_skyline(far_w, H, FAR_INK, int(H * 0.74), 0.75, 7, lit=False),
              (0, 0), _skyline(far_w, H, FAR_INK, int(H * 0.74), 0.75, 7, lit=False))
    near = _skyline(near_w, H, NEAR_INK, int(H * 0.95), 1.25, 31, lit=True)

    os.makedirs(OUT_DIR, exist_ok=True)
    far_png = os.path.join(OUT_DIR, "_ph_far.png")
    near_png = os.path.join(OUT_DIR, "_ph_near.png")
    far.save(far_png)
    near.save(near_png)

    # Two crops panning at different rates, overlaid: parallax without rendering 1350 frames.
    fc = (
        "[0:v]crop=%d:%d:'(iw-%d)*t/%d':0,setsar=1[bg];"
        "[1:v]crop=%d:%d:'(iw-%d)*t/%d':0,setsar=1[fg];"
        "[bg][fg]overlay=0:0,format=yuv420p[v]"
        % (W, H, W, SECONDS, W, H, W, SECONDS)
    )
    cmd = [
        "ffmpeg", "-y",
        "-loop", "1", "-i", far_png,
        "-loop", "1", "-i", near_png,
        "-filter_complex", fc, "-map", "[v]",
        "-t", str(SECONDS), "-r", str(FPS),
        "-c:v", "libtheora", "-q:v", "7",
        OUT,
    ]
    print(" ".join(cmd))
    rc = subprocess.call(cmd)
    for p in (far_png, near_png):
        os.remove(p)
    if rc != 0:
        sys.exit(rc)
    print("wrote %s (%.1f MB)" % (OUT, os.path.getsize(OUT) / 1048576.0))


if __name__ == "__main__":
    main()
