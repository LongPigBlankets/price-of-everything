#!/usr/bin/env python3
"""Preview video of the loading-screen dolly, composited from the layer PNGs.

NOT a zoom. Earlier versions scaled every layer about the vanishing point, which
is only correct for a plane perpendicular to the view — so nothing sheared,
nothing was revealed, and it read as a photograph being enlarged.

This street is three families of planes PARALLEL to the direction of travel: the
ground (z=0) and the two facade rows (y = +/-BUILDING_FRONT_Y, plus the lamp line
at +/-LAMP_Y). For a camera translating along +X, any such plane maps by an exact
HOMOGRAPHY. So each layer gets the true warp for the plane it rides, and a handful
of stills reproduce real dolly motion: facades shear open, the road and its centre
dashes stream toward the camera, near content sweeps out of frame.

Derivation (camera looks +X, up +Z, right -Y; VP at the optical axis):
    screen X = F*(-y)/f,  screen Y = F*(h-z)/f,   f = depth = x - cam_x
  ground z=0 :  f = F*h/Y      -> advancing d maps Y -> Y/(1 - (d/(F*h))*Y)
  wall  y=Y0 :  f = -F*Y0/X    -> advancing d maps X -> X/(1 + (d/(F*Y0))*X)
Both are projective in ONE screen axis, i.e. a homography; the inverse (what PIL
needs) is the same form with d negated. Backdrops (city, sky) are perpendicular
planes and keep a uniform scale f/(f-d) — which is why they barely move.

ADVANCE is in WORLD UNITS, not a zoom factor: the camera really travels. The
ceiling is the nearest content — the construction site's near corner sits ~5.3
units ahead and magnifies by 5.3/(5.3-d), so past ~4.5 it tears apart and leaves
holes (nothing was rendered behind it). Actually passing buildings needs the
multi-station work, not a bigger number here.

    python3 parallax_preview.py [out.mp4]
"""
import subprocess
import sys
import os
from PIL import Image

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "renders/loading/layers")

# (file, plane) — plane is ("ground", z) | ("wall", y) | ("depth", x); mirrors
# LAYER_PLANES in loading_scene.py. Paint order is far -> near.
LAYERS = [
    ("L0_sky_graded.png",       ("depth", 210.0)),
    ("L1_city.png",             ("depth", 74.0)),
    ("L2_ground_stippled.png",  ("ground", 0.0)),
    ("L3_north_stippled.png",   ("wall", 2.57)),
    ("L4_south_stippled.png",   ("wall", -2.57)),
    ("L5_lamp_n_stippled.png",  ("wall", 0.92)),
    ("L6_lamp_s_stippled.png",  ("wall", -0.92)),
]

W, H = 1920, 1080
SRC_W, SRC_H = 2400, 1350
FIT = W / float(SRC_W)           # layers are shown whole: the approved composition
# Vanishing point (where the forward axis lands). Blender's shift_y is in units of
# the LARGER image dimension, not the height — measured against the render, the road
# converges at py ~973 for a 2400x1350 layer and this formula gives 975. The old
# 0.625*H (=844) was 130px high; harmless in a uniform zoom, fatal for a homography.
SHIFT_Y = 0.125
FX = SRC_W / 2.0
FY = SRC_H / 2.0 + SHIFT_Y * max(SRC_W, SRC_H)
LENS, SENSOR = 32.0, 36.0
F = LENS / SENSOR * SRC_W        # focal length in layer pixels
CAM_X, CAM_H = -13.0, 0.62

FPS = 30
T_TOTAL = 45.0
T_CRUISE = 40.0                  # constant creep until here, then ease to halt
ADVANCE = 4.5                    # world units travelled over the whole run


def progress(t):
    """0..1 travelled distance: constant velocity, then linear decel to zero."""
    v0 = 1.0 / (T_CRUISE + (T_TOTAL - T_CRUISE) / 2.0)
    if t <= T_CRUISE:
        return v0 * t
    dt = min(t, T_TOTAL) - T_CRUISE
    span = T_TOTAL - T_CRUISE
    return v0 * (T_CRUISE + dt - dt * dt / (2.0 * span))


def _mul(A, B):
    return [[sum(A[i][k] * B[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def coeffs(plane, d):
    """PIL PERSPECTIVE coefficients (output px -> input px) for this plane at advance d."""
    kind, val = plane
    if kind == "ground":
        a = d / (F * CAM_H)
        winv = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, a, 1.0]]
    elif kind == "wall":
        b = d / (F * val)                      # val is signed: north +, south -
        winv = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [-b, 0.0, 1.0]]
    else:                                       # perpendicular backdrop
        f = val - CAM_X
        m = f / (f - d)
        winv = [[1.0 / m, 0.0, 0.0], [0.0, 1.0 / m, 0.0], [0.0, 0.0, 1.0]]
    win2vp = [[1.0 / FIT, 0.0, -FX], [0.0, 1.0 / FIT, -FY], [0.0, 0.0, 1.0]]
    vp2layer = [[1.0, 0.0, FX], [0.0, 1.0, FY], [0.0, 0.0, 1.0]]
    m3 = _mul(vp2layer, _mul(winv, win2vp))
    s = m3[2][2]
    m3 = [[v / s for v in row] for row in m3]
    return (m3[0][0], m3[0][1], m3[0][2],
            m3[1][0], m3[1][1], m3[1][2],
            m3[2][0], m3[2][1])


def main(out_path):
    imgs = []
    for f, plane in LAYERS:
        path = os.path.join(BASE, f)
        if not os.path.exists(path):
            print("missing, skipping:", f)
            continue
        imgs.append((Image.open(path).convert("RGBA"), plane))
    n_frames = int(T_TOTAL * FPS)
    ff = subprocess.Popen(
        ["ffmpeg", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
         "-s", "%dx%d" % (W, H), "-r", str(FPS), "-i", "-",
         "-c:v", "libx264", "-crf", "17", "-pix_fmt", "yuv420p",
         "-movflags", "+faststart", out_path],
        stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for i in range(n_frames):
        d = ADVANCE * progress(i / FPS)
        frame = None
        for img, plane in imgs:
            layer = img.transform((W, H), Image.PERSPECTIVE, coeffs(plane, d),
                                  resample=Image.BICUBIC, fillcolor=(0, 0, 0, 0))
            frame = layer if frame is None else Image.alpha_composite(frame, layer)
        ff.stdin.write(frame.convert("RGB").tobytes())
        if i % 150 == 0:
            print("frame %d/%d (t=%.1fs, advance=%.2f u)" % (i, n_frames, i / FPS, d),
                  flush=True)
    ff.stdin.close()
    ff.wait()
    print("wrote", out_path)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else
         os.path.join(os.path.dirname(BASE), "loading_dolly_45s.mp4"))
