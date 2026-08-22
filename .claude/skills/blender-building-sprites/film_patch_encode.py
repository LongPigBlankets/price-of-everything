#!/usr/bin/env python3
"""Rebuild the film with repaired regions pasted in, in one streaming pass.

    python film_patch_encode.py --film film.ogv --regions <dir> --out film_new.ogv [-q 6]

`--regions` is what film_patch_frames.py --borders writes: one small PNG per repaired frame
plus manifest.json giving each one's rectangle and its cross-fade weight.

STREAMING, because the alternative is 1350 uncompressed frames on disk (~3.4 GB) to carry a
couple of hundred small rectangles. ffmpeg decodes to raw on one pipe and encodes from raw on
another; this sits between them and paints the repaired rectangles as the frames go past.

USE THE CONCAT PATH INSTEAD WHEN THE REPAIRS ARE ONE RUN STARTING AT FRAME 0. Streaming pulls
EVERY frame through rgb24, so all 1350 pay a YUV -> RGB -> YUV round trip, including the 1274
this never touches. Measured 2026-08-22 on the same repair: streaming 50.9 MB, concat 44.0 MB,
against a shipped 48.2 MB. Same q6, same content — 6.9 MB of pure round-trip. Write the head
as PNGs and let ffmpeg keep the tail in its own colour space:

    ffmpeg -y -r 30 -start_number 0 -i head/p%04d.png -i film_ORIGINAL.ogv       -filter_complex "[1:v]trim=start_frame=<N>,setpts=PTS-STARTPTS[b];                       [0:v]format=yuv420p[a];[a][b]concat=n=2:v=1:a=0[v]"       -map "[v]" -c:v libtheora -q:v 6 -r 30 film.ogv

This tool is for repairs SCATTERED through the film, where there is no tail to keep.

THE WHOLE FILM IS RE-ENCODED, not spliced. Ogg cannot be cut and rejoined with -c copy without
chaining two logical streams, and Godot's Theora decoder is not to be trusted past that join.
One extra generation measured 44.7 dB at q6 — imperceptible on flat-fill art — and q6 lands
SMALLER than the shipped film, which matters because Theora decodes on Godot's main thread.
"""
import argparse
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image

W, H = 1920, 1080


def _ramp(n, feather, at_start):
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


def _weights(cx0, cx1, cy0, cy1, feather):
    wx = np.ones(cx1 - cx0, np.float32)
    if cx0 > 0:
        wx *= _ramp(cx1 - cx0, feather, at_start=True)
    if cx1 < W:
        wx *= _ramp(cx1 - cx0, feather, at_start=False)
    wy = np.ones(cy1 - cy0, np.float32)
    if cy0 > 0:
        wy *= _ramp(cy1 - cy0, feather, at_start=True)
    if cy1 < H:
        wy *= _ramp(cy1 - cy0, feather, at_start=False)
    return (wy[:, None] * wx[None, :])[..., None]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--film", required=True)
    ap.add_argument("--regions", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("-q", "--quality", type=int, default=6)
    ap.add_argument("--fps", type=int, default=30)
    a = ap.parse_args()

    man = json.load(open(os.path.join(a.regions, "manifest.json")))
    feather = int(man.get("feather", 48))
    patches = {}
    for k, v in man["frames"].items():
        cx0, cx1, cy0, cy1 = v["rect"]
        img = np.asarray(Image.open(os.path.join(a.regions, "r%06d.png" % int(k)))
                         .convert("RGB")).astype(np.float32)
        patches[int(k)] = (v["rect"], img, _weights(cx0, cx1, cy0, cy1, feather) * float(v["t"]))
    print("loaded %d repaired regions" % len(patches), flush=True)

    dec = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-i", a.film, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        stdout=subprocess.PIPE)
    enc = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
         "-s", "%dx%d" % (W, H), "-r", str(a.fps), "-i", "-",
         "-c:v", "libtheora", "-q:v", str(a.quality), "-r", str(a.fps), a.out],
        stdin=subprocess.PIPE)

    n = W * H * 3
    i = 0
    done = 0
    try:
        while True:
            buf = dec.stdout.read(n)
            if len(buf) < n:
                break
            if i in patches:
                (cx0, cx1, cy0, cy1), reg, w = patches[i]
                f = np.frombuffer(buf, np.uint8).reshape(H, W, 3).astype(np.float32)
                sub = f[cy0:cy1, cx0:cx1]
                f[cy0:cy1, cx0:cx1] = reg * w + sub * (1.0 - w)
                enc.stdin.write(np.clip(f, 0, 255).astype(np.uint8).tobytes())
                done += 1
            else:
                enc.stdin.write(buf)
            i += 1
            if i % 300 == 0:
                print("  %d frames (%d repaired)" % (i, done), flush=True)
    finally:
        enc.stdin.close()
        dec.stdout.close()
        enc.wait()
        dec.wait()
    missing = sorted(set(patches) - set(range(i)))
    if missing:
        print("WARNING: %d repaired frames past the end of the film: %s"
              % (len(missing), missing[:8]), file=sys.stderr)
    print("wrote %s — %d frames, %d repaired" % (a.out, i, done))
    if done != len(patches):
        print("WARNING: expected %d repairs, applied %d" % (len(patches), done), file=sys.stderr)


if __name__ == "__main__":
    main()
