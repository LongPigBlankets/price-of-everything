"""Trace the owner's puff-smoke drawing into a polygon usable by SmokeVisuals.

Two problems to solve: the drawing has two thin stem lines below the cloud that are not part
of the shape, and a raster silhouette is not something the map can draw. A morphological
OPENING removes anything thinner than the structuring element (the stems) while leaving the
cloud body untouched, and ray-casting from the centroid turns what is left into a radial
polygon -- the right representation here because a puff is star-convex about its middle.
"""
import numpy as np
from PIL import Image, ImageFilter

src = Image.open(r"C:\Users\urigi\Downloads\puff smoke.PNG").convert("RGBA")
a = np.array(src)
# Ink is dark; background is white or transparent.
opaque = a[..., 3] > 128
dark = a[..., :3].mean(axis=2) < 140
mask = (opaque & dark).astype(np.uint8) * 255
print("filled px, raw:", int((mask > 0).sum()))

m = Image.fromarray(mask, "L")
# Opening: erode then dilate by the same amount. Anything narrower than the kernel -- the two
# stems -- does not survive the erosion and never comes back.
K = 11
m = m.filter(ImageFilter.MinFilter(K)).filter(ImageFilter.MaxFilter(K))
mask2 = np.array(m) > 0
print("filled px, opened:", int(mask2.sum()))

ys, xs = np.nonzero(mask2)
cy, cx = ys.mean(), xs.mean()
H, W = mask2.shape
print("centroid", round(cx, 1), round(cy, 1))

N = 40
pts = []
for i in range(N):
    th = 2.0 * np.pi * i / N
    dx, dy = np.cos(th), np.sin(th)
    # March out until we leave the shape; step finely enough not to skip a lobe notch.
    r = 0.0
    last_in = 0.0
    while r < max(W, H):
        r += 0.5
        x, y = int(round(cx + dx * r)), int(round(cy + dy * r))
        if x < 0 or y < 0 or x >= W or y >= H or not mask2[y, x]:
            break
        last_in = r
    pts.append((dx * last_in, dy * last_in))

pts = np.array(pts)
scale = np.abs(pts).max()
pts = pts / scale                      # unit shape, longest reach == 1.0
pts[:, 1] *= 1.0                       # image y already points down, same as Godot 2D
print("radius range %.3f..%.3f" % (np.hypot(*pts.T).min(), np.hypot(*pts.T).max()))

body = ",\n".join(
    "\tVector2(%.4f, %.4f)" % (p[0], p[1]) for p in pts
)
print("\n===GD===")
print("const PUFF_SHAPE: PackedVector2Array = PackedVector2Array([\n%s,\n])" % body)

# Preview so the trace can be eyeballed against the original.
prev = Image.new("RGB", (W * 2, H), (255, 255, 255))
prev.paste(src.convert("RGB"), (0, 0))
from PIL import ImageDraw
d = ImageDraw.Draw(prev)
poly = [(W + cx + p[0] * scale, cy + p[1] * scale) for p in pts]
d.polygon(poly, fill=(60, 60, 60))
prev.save("artifacts/puff_trace_preview.png")
print("preview -> artifacts/puff_trace_preview.png")
