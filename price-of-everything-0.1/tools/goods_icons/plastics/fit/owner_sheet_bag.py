"""Owner sheet for the bag fixes: shipped art, the previous candidate and the new one at one height, then their
bags at 2x.   python3 owner_sheet_bag.py <prev_dir> <new_dir> <out.png>"""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont
F = ImageFont.truetype('/Users/crisu/Price of Everything/price-of-everything/price-of-everything-0.1/assets/fonts/IBMPlexSans-Medium.ttf', 22)
PAPER = (245, 241, 231); INK = (30, 35, 43)
prev, new, out = sys.argv[1:4]
def load(p, key=False):
    a = np.array(Image.open(p).convert('RGBA'))
    if key:
        m = (a[..., 0] > 180) & (a[..., 1] < 110) & (a[..., 2] > 180); a[m, 3] = 0
    ys, xs = np.where(a[..., 3] > 40); a = a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    im = Image.fromarray(a); H = 700; im = im.resize((round(im.width * H / im.height), H), Image.LANCZOS)
    bg = Image.new('RGBA', im.size, PAPER + (255,)); bg.alpha_composite(im); return bg.convert('RGB')
tiles = [('Shipped art', load('reference/g_027_plastics.png', True)), ('Before (what you saw)', load(prev + '/plastics_800.png')),
         ('After: the bag fixed', load(new + '/plastics_800.png'))]
cw = max(t.width for _, t in tiles) + 30
def bag(p):
    im = Image.open(p).convert('RGBA'); bg = Image.new('RGBA', im.size, PAPER + (255,)); bg.alpha_composite(im)
    return bg.convert('RGB').crop((420, 330, 700, 620)).resize((560, 580), Image.LANCZOS)
b1, b2 = bag(prev + '/plastics_800.png'), bag(new + '/plastics_800.png')
W = max(cw * 3, 20 + b1.width * 2 + 40); H = 40 + 700 + 60 + b1.height + 20
sheet = Image.new('RGB', (W, H), PAPER); d = ImageDraw.Draw(sheet)
for k, (t, im) in enumerate(tiles):
    x = k * cw + 10; d.text((x, 8), t, fill=INK, font=F); sheet.paste(im, (x, 40))
y = 40 + 700 + 20
d.text((10, y), 'The bag at 2x: before', fill=INK, font=F); d.text((40 + b1.width, y), 'after', fill=INK, font=F)
sheet.paste(b1, (10, y + 36)); sheet.paste(b2, (40 + b1.width, y + 36))
sheet.save(out); print(sheet.size)
