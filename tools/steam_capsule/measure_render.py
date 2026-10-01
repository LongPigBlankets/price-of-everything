#!/usr/bin/env python3
"""Read back the colours a render actually produced at its probe points.

    python3 tools/steam_capsule/measure_render.py renders/earth_plate.png

Samples the median of a small patch at each point in the render's .probe.json (so a
stray ink pixel cannot move the reading), prints each top colour against its in-game
target with the next linear albedo to try, and lists the wall bands it can see. The
last line is ready to paste as --albedo arguments.
"""
import json
import os
import statistics
import sys

from PIL import Image


def srgb_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def sample(im, x, y, half=6):
    box = (int(x) - half, int(y) - half, int(x) + half + 1, int(y) + half + 1)
    px = [p for p in im.crop(box).getdata() if p[3] == 255]
    return tuple(int(statistics.median(p[i] for p in px)) for i in range(3)) if px else None


def main(path):
    probe = json.load(open(os.path.splitext(path)[0] + ".probe.json"))
    im = Image.open(path).convert("RGBA")
    args = []
    for top in probe["tops"]:
        target = tuple(int(top["target"][i:i + 2], 16) for i in (1, 3, 5))
        got = [c for c in (sample(im, *p, half=4) for p in top["px"]) if c]
        if not got:
            print("%-10s no readable probe" % top["mat"])
            continue
        m = tuple(int(statistics.median(c[i] for c in got)) for i in range(3))
        nxt = [min(4.0, a * srgb_to_linear(t) / max(srgb_to_linear(v), 1e-4))
               for a, t, v in zip(top["albedo"], target, m)]
        print("%-10s rendered #%02x%02x%02x  target #%02x%02x%02x  diff %s"
              % (top["mat"], *m, *target, tuple(a - b for a, b in zip(m, target))))
        args.append("--albedo %s=%s" % (top["mat"], ",".join("%.4f" % v for v in nxt)))
    for w in probe["walls"]:
        c = sample(im, *w["px"], half=3)
        if c:
            luma = round(0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2])
            print("  %s %s band %2d %-10s #%02x%02x%02x  L%d" % (w["cell"], w["wall"], w["band"], w["mat"], *c, luma))
    print("next: " + " ".join(args))


if __name__ == "__main__":
    main(sys.argv[1])
