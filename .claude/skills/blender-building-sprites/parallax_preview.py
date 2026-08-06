#!/usr/bin/env python3
"""Loading-screen dolly: multi-station plane-homography compositor.

Motion (step 1-3, unchanged): the street is three families of planes PARALLEL to
the travel axis — ground z=0, facade rows y=+/-2.57, lamp line y=+/-0.92. For a
camera translating along +X any such plane maps by an EXACT homography, so each
layer gets the true warp for the plane it rides and the stills produce real dolly
motion: facades shear open, road and dashes stream toward the camera.
    ground z=0 :  advancing d maps Y -> Y/(1 - (d/(F*h))*Y)
    wall  y=Y0 :  advancing d maps X -> X/(1 + (d/(F*Y0))*X)
The inverse (what PIL needs) is the same form with d negated.

STEP 4 — STATIONS. One still can only be dollied ~4.5 units before the nearest
building tears apart, because nothing was rendered behind it. So the scene is
rendered from N camera positions down the street and the player is cross-faded
from one to the next WHILE BOTH ARE WARPING, which is what makes a join read as
continued travel instead of a cut (impostor/LOD morphing). During the overlap the
incoming station is warped BACKWARD (negative d) to the same instant in space as
the outgoing one. Backward warping samples outside the source and leaves thin
transparent margins at the frame edge — harmless, because the outgoing station is
still underneath at exactly the moment the incoming one is most transparent.

STEP 5 — SCREEN-SPACE STIPPLE. Dots are no longer baked into the layers, where
they warped along with the world and stretched. Layers now ship raw colour plus
their light mask; both are warped, and the dots are laid on a grid fixed in OUTPUT
space, so the stipple sits on the page like a real print screen while the world
moves under it. Density still comes from the mask, per layer, with that layer's
own cuts (the ground's mask is a diffuse render, the walls' is geometric, and the
two do not share a scale).

    python3 parallax_preview.py [out.mp4]
"""
import subprocess
import sys
import os
import numpy as np
from PIL import Image

try:
    from scipy.ndimage import binary_erosion as _erode_fast
except Exception:
    _erode_fast = None

HERE = os.path.dirname(os.path.abspath(__file__))
STATIONS_DIR = os.path.join(HERE, "renders/loading/stations")
SKY_FILE = os.path.join(HERE, "renders/loading/layers/L0_sky_graded.png")

# (layer, plane, mask?, stipple cuts) — paint order far -> near.
# plane: ("ground", z) | ("wall", y) | ("depth", x)
LAYERS = [
    ("L0_sky",    ("depth", 210.0), False, None),
    ("L1_city",   ("depth", 74.0),  False, None),
    ("L2_ground", ("ground", 0.0),  True,  (0.70, 0.63, True)),
    ("L3_north",  ("wall", 2.57),   True,  (0.775, 0.60, False)),
    ("L4_south",  ("wall", -2.57),  True,  (0.775, 0.60, False)),
    ("L5_lamp_n", ("wall", 0.92),   True,  (0.775, 0.60, False)),
    ("L6_lamp_s", ("wall", -0.92),  True,  (0.775, 0.60, False)),
]

W, H = 1920, 1080
SRC_W, SRC_H = 2400, 1350
FIT = W / float(SRC_W)
SHIFT_Y = 0.125                  # Blender shift is in units of the LARGER dimension
FX = SRC_W / 2.0
FY = SRC_H / 2.0 + SHIFT_Y * max(SRC_W, SRC_H)
LENS, SENSOR = 32.0, 36.0
F = LENS / SENSOR * SRC_W
CAM_X, CAM_H = -13.0, 0.62

N_STATIONS = 6
SPACING = 2.25
ADVANCE = N_STATIONS * SPACING   # 13.5 world units — 3x the single-still run
FADE = 0.55                      # fraction of a station's span spent cross-fading

FPS = 30
T_TOTAL = 45.0
T_CRUISE = 40.0

# Screen-space stipple, matched to the approved look: the layers used to be
# stippled at 2400 with spacing 14 / r 1.7, shown at FIT — so on screen that was
# spacing 11.2 / r 1.36. Same numbers here, now in output pixels.
DOT_SPACING, DOT_R, DOT_STRENGTH = 11.2, 1.36, 0.38
INK = np.array([0.055, 0.065, 0.13], dtype=np.float32)


def progress(t):
    v0 = 1.0 / (T_CRUISE + (T_TOTAL - T_CRUISE) / 2.0)
    if t <= T_CRUISE:
        return v0 * t
    dt = min(t, T_TOTAL) - T_CRUISE
    span = T_TOTAL - T_CRUISE
    return v0 * (T_CRUISE + dt - dt * dt / (2.0 * span))


def _mul(A, B):
    return [[sum(A[i][k] * B[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def coeffs(plane, d):
    kind, val = plane
    if kind == "ground":
        a = d / (F * CAM_H)
        winv = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, a, 1.0]]
    elif kind == "wall":
        b = d / (F * val)
        winv = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [-b, 0.0, 1.0]]
    else:
        f = val - CAM_X
        m = f / (f - d)
        winv = [[1.0 / m, 0.0, 0.0], [0.0, 1.0 / m, 0.0], [0.0, 0.0, 1.0]]
    m3 = _mul([[1.0, 0.0, FX], [0.0, 1.0, FY], [0.0, 0.0, 1.0]],
              _mul(winv, [[1.0 / FIT, 0.0, -FX], [0.0, 1.0 / FIT, -FY], [0.0, 0.0, 1.0]]))
    s = m3[2][2]
    m3 = [[v / s for v in row] for row in m3]
    return (m3[0][0], m3[0][1], m3[0][2], m3[1][0], m3[1][1], m3[1][2], m3[2][0], m3[2][1])


def _grid(xx, yy, spacing, off_u=0.0, off_v=0.0):
    u = (xx / spacing + off_u) % 1.0
    v = (yy / spacing + off_v) % 1.0
    return np.sqrt((u - 0.5) ** 2 + (v - 0.5) ** 2) * spacing


yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
_cov = lambda dist, r: np.clip(r + 0.5 - dist, 0.0, 1.0)
G_A = _cov(_grid(xx, yy, DOT_SPACING), DOT_R)
G_B = _cov(_grid(xx, yy, DOT_SPACING, 0.5, 0.5), DOT_R)
G_C = _cov(_grid(xx, yy, DOT_SPACING / 2), DOT_R * 0.9)
del xx, yy


def _erode(m, r):
    if _erode_fast is not None:
        return _erode_fast(m, structure=np.ones((2 * r + 1, 2 * r + 1), bool))
    out = m.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            out &= np.roll(np.roll(m, dy, 0), dx, 1)
    return out


class Station:
    """Lazily-loaded layer set for one camera position."""

    _cache = {}

    def __init__(self, idx):
        self.idx = idx
        self.layers = []
        root = os.path.join(STATIONS_DIR, "s%d" % idx)
        for name, plane, has_mask, cuts in LAYERS:
            path = SKY_FILE if name == "L0_sky" else os.path.join(root, name + ".png")
            if not os.path.exists(path):
                continue
            col = Image.open(path).convert("RGBA")
            mask = None
            mpath = os.path.join(root, "masks", name + ".png")
            if has_mask and os.path.exists(mpath):
                mask = Image.open(mpath).convert("RGBA")
            self.layers.append((col, mask, plane, cuts))

    @classmethod
    def get(cls, idx):
        if idx not in cls._cache:
            if len(cls._cache) > 2:                    # keep only the active pair
                cls._cache.pop(sorted(cls._cache)[0], None)
            cls._cache[idx] = Station(idx)
        return cls._cache[idx]

    def frame(self, d):
        """Composite this station warped by advance d. Returns float RGBA (H,W,4)."""
        acc = np.zeros((H, W, 4), dtype=np.float32)
        for col, mask, plane, cuts in self.layers:
            c = coeffs(plane, d)
            arr = np.asarray(col.transform((W, H), Image.PERSPECTIVE, c,
                                           resample=Image.BICUBIC,
                                           fillcolor=(0, 0, 0, 0))).astype(np.float32) / 255.0
            rgb, alpha = arr[..., :3].copy(), arr[..., 3]
            if mask is not None and cuts is not None:
                mk = np.asarray(mask.transform((W, H), Image.PERSPECTIVE, c,
                                               resample=Image.BICUBIC,
                                               fillcolor=(0, 0, 0, 0))).astype(np.float32) / 255.0
                light = mk[..., 0] * 0.2126 + mk[..., 1] * 0.7152 + mk[..., 2] * 0.0722
                lum = rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722
                is_glass = (rgb[..., 2] > rgb[..., 0] * 1.45) & (lum < 0.38)
                covered = _erode((alpha > 0.01) & (mk[..., 3] > 0.5) & ~is_glass, 2)
                lit_cut, part_cut, deep = cuts
                band_a = _erode(light < lit_cut, 2)
                band_b = _erode(light < part_cut, 2)
                cover = np.maximum(G_A * band_a, G_B * band_b)
                if deep:
                    cover = np.maximum(cover, G_C * band_b)
                cover *= covered
                k = (DOT_STRENGTH * cover)[..., None]
                rgb = rgb * (1 - k) + INK[None, None, :] * k
            a = alpha[..., None]
            acc[..., :3] = rgb * a + acc[..., :3] * (1 - a)
            acc[..., 3:] = a + acc[..., 3:] * (1 - a)
        return acc


def main(out_path):
    if not os.path.isdir(STATIONS_DIR):
        sys.exit("no stations rendered yet: " + STATIONS_DIR)
    n_frames = int(T_TOTAL * FPS)
    ff = subprocess.Popen(
        ["ffmpeg", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (W, H),
         "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-crf", "17",
         "-pix_fmt", "yuv420p", "-movflags", "+faststart", out_path],
        stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    fade_start = SPACING * (1.0 - FADE)
    for i in range(n_frames):
        D = ADVANCE * progress(i / FPS)
        idx = min(int(D / SPACING), N_STATIONS - 1)
        d = D - idx * SPACING
        frame = Station.get(idx).frame(d)
        if d > fade_start and idx + 1 < N_STATIONS:
            w = (d - fade_start) / (SPACING - fade_start)
            w = w * w * (3.0 - 2.0 * w)               # smoothstep
            nxt = Station.get(idx + 1).frame(d - SPACING)
            a = (nxt[..., 3] * w)[..., None]
            frame[..., :3] = nxt[..., :3] * a + frame[..., :3] * (1 - a)
        ff.stdin.write((np.clip(frame[..., :3], 0, 1) * 255).astype(np.uint8).tobytes())
        if i % 90 == 0:
            print("frame %d/%d  t=%.1fs  D=%.2fu  station %d" % (i, n_frames, i / FPS, D, idx),
                  flush=True)
    ff.stdin.close()
    ff.wait()
    print("wrote", out_path)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else
         os.path.join(HERE, "renders/loading/loading_dolly_stations_45s.mp4"))
