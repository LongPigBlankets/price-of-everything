"""Overlay the shipped art's ink (red) on a candidate 800 render (faded), aligned by the inked
composition boxes (heights matched), to compare line by line. Also a side-by-side at the same scale."""
import sys
import numpy as np
from PIL import Image
cand = Image.open(sys.argv[1]).convert('RGBA'); out = sys.argv[2]
ref = Image.open('reference/g_027_plastics.png').convert('RGBA')
ca = np.array(cand); ra = np.array(ref)
def box(a):
    ys, xs = np.where(a[..., 3] > 120); return xs.min(), ys.min(), xs.max(), ys.max()
cb = box(ca); rb = box(ra)
k = (cb[3] - cb[1]) / (rb[3] - rb[1])
print('scale %.4f; widths cand %d ref*k %.0f' % (k, cb[2] - cb[0], (rb[2] - rb[0]) * k))
rs = ref.resize((round(ref.width * k), round(ref.height * k)), Image.LANCZOS)
ox = cb[0] - round(rb[0] * k); oy = cb[1] - round(rb[1] * k)
canvas = Image.new('RGBA', cand.size, (0, 0, 0, 0)); canvas.alpha_composite(rs, (ox, oy)) if ox >= 0 and oy >= 0 else canvas.paste(rs, (ox, oy), rs)
R = np.array(canvas).astype(int)
ink = (R[..., 3] > 120) & (R[..., 0] < 90) & (R[..., 1] < 90) & (R[..., 2] < 130)
base = np.array(Image.alpha_composite(Image.new('RGBA', cand.size, (255, 255, 255, 255)), cand).convert('RGB')).astype(float)
base = 255 - (255 - base) * 0.45
base[ink] = (220, 30, 30)
Image.fromarray(base.astype('uint8')).save(out)
side = Image.new('RGBA', (cand.width * 2 + 20, cand.height), (255, 255, 255, 255)); side.alpha_composite(canvas, (0, 0)); side.alpha_composite(cand, (cand.width + 20, 0))
side.convert('RGB').save(out.replace('.png', '_side.png'))
