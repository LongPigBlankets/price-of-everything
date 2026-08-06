#!/usr/bin/env python3
"""Preview video of the loading-screen parallax push-in, from the layer PNGs.

This is the same motion the Godot script (P4) will drive: each layer scales
about the camera's true vanishing point at its own rate, so the street appears
to glide toward the city, and the motion EASES OUT to a dead stop at the end.
Budget (owner 2026-08-06): a typical load finishes ~30s in; the creep may run
45s total before the overscan is exhausted and it must halt. This renders the
full 45s worst case: constant creep to t=40, deceleration to zero over the
last 5s. (In Godot the same ease-out fires early, whenever build_complete
lands.)

Geometry: layers are 2400x1350 with the approved frame at full-canvas; the
output window is 1920x1080. All layers start at fit-scale 0.8 (the approved
composition exactly) and the near/street layers grow to 1.0 (native pixels,
central window) — a 25% push. Farther layers grow by their parallax rate
share. The vanishing point of forward motion stays fixed on screen: with the
rig's plumb verticals and shift_y 0.125 it sits at v=0.625 -> (1200, 844) in
layer space.

    python3 parallax_preview.py [out.mp4]
"""
import subprocess
import sys
import os
from PIL import Image

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "renders/loading/layers")
LAYERS = [                       # (file, parallax rate share of the 25% push)
    ("L0_sky_graded.png", 0.08),
    ("L1_city.png", 0.25),
    ("L2_street_stippled.png", 1.00),   # street rides the near rate (plan)
    ("L3_far_stippled.png", 0.70),
    ("L4_near_stippled.png", 1.00),
]
W, H = 1920, 1080
SRC_W, SRC_H = 2400, 1350
FX, FY = 1200.0, 844.0           # vanishing point in layer space
FOX, FOY = FX * 0.8, FY * 0.8    # ...held fixed at its t=0 screen position
FPS = 30
T_TOTAL = 45.0
T_CRUISE = 40.0                  # constant creep until here, then ease to halt


def progress(t):
    """0..1 travelled distance: constant velocity, then linear decel to zero."""
    v0 = 1.0 / (T_CRUISE + (T_TOTAL - T_CRUISE) / 2.0)
    if t <= T_CRUISE:
        return v0 * t
    dt = min(t, T_TOTAL) - T_CRUISE
    span = T_TOTAL - T_CRUISE
    return v0 * (T_CRUISE + dt - dt * dt / (2.0 * span))


def main(out_path):
    imgs = [(Image.open(os.path.join(BASE, f)).convert("RGBA"), r) for f, r in LAYERS]
    n_frames = int(T_TOTAL * FPS)
    ff = subprocess.Popen(
        ["ffmpeg", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
         "-s", "%dx%d" % (W, H), "-r", str(FPS), "-i", "-",
         "-c:v", "libx264", "-crf", "17", "-pix_fmt", "yuv420p",
         "-movflags", "+faststart", out_path],
        stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for i in range(n_frames):
        p = progress(i / FPS)
        frame = None
        for img, rate in imgs:
            k = 0.8 * (1.0 + 0.25 * rate * p)
            a = 1.0 / k
            c = FX - FOX / k
            f = FY - FOY / k
            layer = img.transform((W, H), Image.AFFINE, (a, 0.0, c, 0.0, a, f),
                                  resample=Image.BICUBIC)
            frame = layer if frame is None else Image.alpha_composite(frame, layer)
        ff.stdin.write(frame.convert("RGB").tobytes())
        if i % 150 == 0:
            print("frame %d/%d (t=%.1fs, p=%.3f)" % (i, n_frames, i / FPS, p), flush=True)
    ff.stdin.close()
    ff.wait()
    print("wrote", out_path)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else
         os.path.join(os.path.dirname(BASE), "loading_parallax_45s.mp4"))
