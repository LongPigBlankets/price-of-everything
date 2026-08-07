#!/usr/bin/env python3
"""Diagnostic: STATIONARY snapshots down the street, cross-faded.

Owner 2026-08-06: "10 snapshots over double the current distance ... stationary
and blended between each other with a 1s transition. The point is to check the
buildings are all behaving as they should as we pass by."

No homography, no dolly — every station is shown exactly as rendered (d=0), held,
then cross-faded into the next. So anything odd here is the SCENE (a building
mis-set-back, a prop in the wrong place, a hole behind something), not the motion
model. That separation is the whole point: the 2.5D warp has known accuracy limits
for content off its assumed plane, and this run takes the warp out of the picture.

10 stations, 3.0 units apart = 27 units of travel, double the 6-station dolly.

    python3 station_check.py [out.mp4]
"""
import os
import subprocess
import sys
import numpy as np
from PIL import Image

import parallax_preview as P

P.STATIONS_DIR = os.path.join(P.HERE, "renders/loading/stations_check")
N = 10
HOLD = 3.5                       # seconds fully on one station
XFADE = 1.0                      # seconds of cross-fade between neighbours
FPS = P.FPS
W, H = P.W, P.H


def station_still(i):
    """The station exactly as rendered: identity warp, screen-space stipple."""
    st = P.Station(i)             # bypass the 2-deep cache: we want all 10
    fr = st.frame(0.0)
    return (np.clip(fr[..., :3], 0, 1) * 255).astype(np.uint8)


def main(out_path):
    stills = []
    for i in range(N):
        d = os.path.join(P.STATIONS_DIR, "s%d" % i)
        if not os.path.isdir(d):
            sys.exit("missing station: " + d)
        stills.append(station_still(i))
        Image.fromarray(stills[-1]).save(
            os.path.join(P.HERE, "renders/loading/_check_s%d.png" % i))
        print("station %d composited" % i, flush=True)

    hold_n = int(HOLD * FPS)
    fade_n = int(XFADE * FPS)
    ff = subprocess.Popen(
        ["ffmpeg", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (W, H),
         "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-crf", "17",
         "-pix_fmt", "yuv420p", "-movflags", "+faststart", out_path],
        stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for i in range(N):
        for _ in range(hold_n):
            ff.stdin.write(stills[i].tobytes())
        if i + 1 < N:
            a = stills[i].astype(np.float32)
            b = stills[i + 1].astype(np.float32)
            for f in range(fade_n):
                w = (f + 0.5) / fade_n
                w = w * w * (3.0 - 2.0 * w)               # smoothstep
                ff.stdin.write((a * (1 - w) + b * w).astype(np.uint8).tobytes())
    ff.stdin.close()
    ff.wait()
    total = N * HOLD + (N - 1) * XFADE
    print("wrote %s  (%.1fs)" % (out_path, total))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else
         os.path.join(P.HERE, "renders/loading/station_check_10.mp4"))
