#!/usr/bin/env python3
"""Rebuild the Empire bottom-menu icon from the original ringed source art.

Extracts the city (no ring) from the ChatGPT source, then re-applies the
shared alt-icon treatment measured from the other 8 icons:
  - object recoloured flat to the button's fg (#fff2c9)
  - bevel: light top-left edges, dark bottom-right edges
  - drop shadow to the bottom-right, clipped to the disc
  - shared rim/ridge layer = per-pixel median of the 8 good icons (r>=105)
  - glow = shared radial base with the new object silhouette cut out
Outputs into scratchpad/out/ for review; installed separately.
"""
from PIL import Image, ImageFilter
import numpy as np
from scipy import ndimage
import os

SRC = "/Users/crisu/Downloads/ChatGPT Image Aug 1, 2026, 09_19_09 PM.png"
ALT = "/Users/crisu/Price of Everything/price-of-everything/price-of-everything-0.1/assets/icons/ui_icons/alt"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
os.makedirs(OUT, exist_ok=True)

FG = np.array([0xFF, 0xF2, 0xC9], dtype=np.float64)  # ALT_COLORS EmpireButton fg
BG = "#c49a28"                                        # mustard, for preview only
GOOD = ["construct", "goods", "building_ledger", "mapmodes", "market",
        "politics", "research", "people"]
R_MAX = float(os.environ.get("R_MAX", "106"))
TOWER_ONLY = os.environ.get("TOWER_ONLY", "") == "1"

# ---------------------------------------------------------------- extraction
im = np.array(Image.open(SRC).convert("RGB"), dtype=np.float64)
h, w = im.shape[:2]
navy = np.array([9., 48., 94.])
cream = np.array([252., 242., 222.])
axis = cream - navy
den = float(axis @ axis)
t = np.clip(((im - navy) @ axis) / den, 0.0, 1.0)
proj = navy[None, None, :] + t[..., None] * axis[None, None, :]
dist = np.linalg.norm(im - proj, axis=2)
t = np.where(dist > 60, 0.0, t)  # only colours on the navy->cream line count

mask = t > 0.5
lab, nlab = ndimage.label(mask)
sizes = ndimage.sum(mask, lab, range(1, nlab + 1))
ring_lab = int(lab[147, 603])  # a pixel known to be on the ring
assert ring_lab > 0

# Inner circle of the ring: boundary between the ring component and the navy
# interior, least-squares circle fit.
interior = ndimage.binary_fill_holes(lab == ring_lab) & ~(lab == ring_lab)
er = ndimage.binary_erosion(interior, iterations=1)
edge = interior & ~er
eys, exs = np.nonzero(edge)
A = np.c_[2.0 * exs, 2.0 * eys, np.ones(len(exs))]
b = exs.astype(float) ** 2 + eys.astype(float) ** 2
cx, cy, k = np.linalg.lstsq(A, b, rcond=None)[0]
r_in = np.sqrt(k + cx * cx + cy * cy)
print(f"ring inner circle: centre=({cx:.1f},{cy:.1f}) r_in={r_in:.1f}")

yy, xx = np.mgrid[0:h, 0:w]
rr = np.hypot(xx - cx, yy - cy)

# City components: everything but the ring, big enough, fully inside the ring.
city = np.zeros((h, w), dtype=bool)
kept = 0
for lb in range(1, nlab + 1):
    if lb == ring_lab or sizes[lb - 1] < 150:
        continue
    comp = lab == lb
    if rr[comp].max() >= r_in - 2:
        print(f"  drop component {lb} (size {int(sizes[lb-1])}): touches ring zone")
        continue
    if TOWER_ONLY:
        cys, cxs = np.nonzero(comp)
        if cxs.min() < 400 or cxs.max() > 860:
            print(f"  drop component {lb}: outside tower band (tower-only)")
            continue
    city |= comp
    kept += 1
print(f"kept {kept} city components")

# Soft alpha: keep the anti-aliased t values in a slim halo around kept pixels.
halo = ndimage.binary_dilation(city, iterations=3)
alpha = np.where(halo, t, 0.0)
alpha[rr > r_in - 2] = 0.0

# ---------------------------------------------------------------- layout 256
ys, xs = np.nonzero(alpha > 0.02)
x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
crop = alpha[y0:y1 + 1, x0:x1 + 1]
ch, cw = crop.shape
# Scale so no city pixel lands beyond radius R_MAX of the 256 canvas when the
# artwork keeps its source position relative to the disc centre (this preserves
# the composition: tower centred, stacks flanking).
src_r = rr[alpha > 0.02]
scale = R_MAX / src_r.max()
print(f"scale {scale:.4f} (src max radius {src_r.max():.1f})")

big = Image.fromarray((alpha * 255).astype(np.uint8))
nw, nh = int(round(w * scale)), int(round(h * scale))
small = big.resize((nw, nh), Image.LANCZOS)
canvas = np.zeros((256, 256), dtype=np.float64)
# place so the fitted circle centre lands at (127.5, 127.5)
ox = 127.5 - cx * scale
oy = 127.5 - cy * scale
sm = np.array(small, dtype=np.float64) / 255.0
x_lo, y_lo = int(round(ox)), int(round(oy))
xs0, ys0 = max(0, -x_lo), max(0, -y_lo)
xd0, yd0 = max(0, x_lo), max(0, y_lo)
cw2 = min(256 - xd0, nw - xs0)
ch2 = min(256 - yd0, nh - ys0)
canvas[yd0:yd0 + ch2, xd0:xd0 + cw2] = sm[ys0:ys0 + ch2, xs0:xs0 + cw2]
obj = canvas  # 0..1 object alpha on the 256 canvas

# ---------------------------------------------------------------- treatment
def blur(a, radius):
    return np.array(Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
                    .filter(ImageFilter.GaussianBlur(radius)), dtype=np.float64) / 255.0

def shift(a, dx, dy):
    out = np.zeros_like(a)
    sy0, sy1 = max(0, dy), min(256, 256 + dy)
    sx0, sx1 = max(0, dx), min(256, 256 + dx)
    out[sy0:sy1, sx0:sx1] = a[sy0 - dy:sy1 - dy, sx0 - dx:sx1 - dx]
    return out

yy2, xx2 = np.mgrid[0:256, 0:256]
r2 = np.hypot(xx2 - 127.5, yy2 - 127.5)

# object base colour
rgb = np.zeros((256, 256, 3), dtype=np.float64)
rgb[..., :] = FG / 255.0
a_obj = obj.copy()

# bevel: light where the top-left edge of the object is, dark on bottom-right
core = np.minimum.reduce([shift(obj, dx, dy) for dx, dy in
                          [(0, 0), (2, 2), (-2, -2), (2, -2), (-2, 2)]])
lit = np.clip(obj - shift(obj, 2, 2), 0, 1) * obj      # top-left rim
drk = np.clip(obj - shift(obj, -2, -2), 0, 1) * obj    # bottom-right rim
lit = blur(lit, 0.6); drk = blur(drk, 0.6)
rgb = rgb + (1.0 - rgb) * (lit * 0.55)[..., None]      # toward white
rgb = rgb * (1.0 - (drk * 0.38)[..., None])            # toward black

# drop shadow: blurred silhouette offset to the bottom-right, disc-clipped
sh = blur(shift(obj, 6, 6), 4.0) * 0.55
sh = np.clip(sh - obj * sh, 0, 1)          # not under the opaque object itself
sh *= np.clip((113.0 - r2) / 6.0, 0, 1)    # fade out at the disc edge

# composite object over shadow (premultiplied-style straight alpha merge)
out_rgb = np.zeros((256, 256, 3), dtype=np.float64)
out_a = np.zeros((256, 256), dtype=np.float64)
# shadow first (pure black)
out_a = sh.copy()
# object over
oa = a_obj
out_rgb = (rgb * oa[..., None] + out_rgb * (1 - oa)[..., None] * out_a[..., None])
out_a = oa + out_a * (1 - oa)
nz = out_a > 1e-4
out_rgb[nz] /= out_a[nz][:, None]

# ---------------------------------------------------------------- rim layer
stack = np.stack([np.array(Image.open(os.path.join(ALT, f"{n}.png")).convert("RGBA"),
                           dtype=np.float64) for n in GOOD])
med = np.median(stack, axis=0)  # (256,256,4)
rim_a = med[..., 3] / 255.0
rim_rgb = med[..., :3] / 255.0
rim_zone = np.clip((r2 - 103.0) / 4.0, 0, 1)  # only the outer band is shared
rim_a = rim_a * rim_zone

# rim OVER (object + shadow)
fa = rim_a + out_a * (1 - rim_a)
frgb = (rim_rgb * rim_a[..., None] + out_rgb * out_a[..., None] * (1 - rim_a)[..., None])
nz = fa > 1e-4
frgb[nz] /= fa[nz][:, None]
final = np.dstack([np.clip(frgb, 0, 1) * 255, np.clip(fa, 0, 1) * 255]).astype(np.uint8)
Image.fromarray(final).save(os.path.join(OUT, "empire_city.png"))

# ---------------------------------------------------------------- glow
# base radial = per-radius max over the 8 glows (recovers the uncut gradient)
glows = np.stack([np.array(Image.open(os.path.join(ALT, f"_glow_{n}.png")))[..., 3]
                  for n in GOOD]).astype(np.float64)
gmax = glows.max(axis=0)
prof = np.zeros(129)
ri = np.clip(r2.astype(int), 0, 128)
for k in range(129):
    sel = ri == k
    if sel.any():
        prof[k] = np.percentile(gmax[sel], 98)
base = prof[ri]
# The button draws the icon into its 78px content area (90px minus the 6px
# stylebox border each side) while the glow TextureRect stretches over the full
# 90px, so the cutout must be baked at 78/90 scale about the canvas centre to
# land on the rendered icon (the June-era glows do the same, ~0.85-0.87).
ICON_SCALE = 78.0 / 90.0
sc = Image.fromarray((obj * 255).astype(np.uint8)).resize(
    (int(round(256 * ICON_SCALE)),) * 2, Image.LANCZOS)
obj_sc = np.zeros((256, 256), dtype=np.float64)
off = int(round((256 - sc.width) / 2))
obj_sc[off:off + sc.height, off:off + sc.width] = np.array(sc, dtype=np.float64) / 255.0
cut = 1.0 - blur(obj_sc, 0.5)
glow_a = np.clip(base * cut, 0, 255).astype(np.uint8)
glow = np.dstack([np.full((256, 256), 255, np.uint8)] * 3 + [glow_a])
Image.fromarray(glow).save(os.path.join(OUT, "_glow_empire_city.png"))

# ---------------------------------------------------------------- previews
bgc = np.array([int(BG[i:i + 2], 16) / 255.0 for i in (1, 3, 5)])
fim = np.array(Image.open(os.path.join(OUT, "empire_city.png")), dtype=np.float64) / 255.0
prev = fim[..., :3] * fim[..., 3:] + bgc * (1 - fim[..., 3:])
Image.fromarray((prev * 255).astype(np.uint8)).resize((512, 512), Image.NEAREST)\
    .save(os.path.join(OUT, "preview_on_mustard.png"))
print("wrote", OUT)
