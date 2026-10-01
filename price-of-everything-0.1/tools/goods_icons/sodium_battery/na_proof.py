"""Proof sheet for the sodium-ion battery: original vs candidate(s) at one height, 450/256/60
derivatives, 3x NEAREST quadrant crops, and the DS2 well at game size beside approved neighbours.
    python3 na_proof.py <candidate_dir> [<previous_dir>]
"""
import sys, json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont

POE = Path('/Users/crisu/Price of Everything/price-of-everything/price-of-everything-0.1')
REF = POE / 'assets/icons/goods/medium/g_060_sodium_battery.png'
ALT = POE / 'assets/icons/goods/alternate_icons'
PAPER = (245, 241, 231); CREAM = (254, 237, 195); STEEL = (30, 35, 43)
F = ImageFont.truetype(str(POE / 'assets/fonts/IBMPlexSans-Medium.ttf'), 20)

cand = Path(sys.argv[1]); prev = Path(sys.argv[2]) if len(sys.argv) > 2 else None
cur = Image.open(cand / 'sodium_battery_800.png').convert('RGBA')
for n in (450, 256, 60):
    cur.resize((n, n), Image.Resampling.LANCZOS).save(cand / ('sodium_battery_%d.png' % n))

def fit(im, h, w=520):
    im = im.crop(im.getbbox()); k = min(h / im.height, w / im.width)
    return im.resize((round(im.width * k), round(im.height * k)), Image.Resampling.LANCZOS)

cols = [('Original (shipped)', Image.open(REF).convert('RGBA'))]
if prev is not None:
    cols.append(('Previous: ' + prev.name, Image.open(prev / 'sodium_battery_800.png').convert('RGBA')))
cols.append(('Candidate: ' + cand.name, cur))
W = 40 + 540 * len(cols); sheet = Image.new('RGB', (W, 820), PAPER); d = ImageDraw.Draw(sheet)
for i, (title, im) in enumerate(cols):
    q = fit(im, 700); x = 20 + i * 540 + (520 - q.width) // 2
    sheet.paste(q, (x, 60), q); d.text((20 + i * 540, 16), title, font=F, fill=(20, 30, 60))
sheet.save(cand / 'comparison.png')

crop = Image.new('RGB', (2400, 2400), PAPER)
for k, box in enumerate([(0, 0, 400, 400), (400, 0, 800, 400), (0, 400, 400, 800), (400, 400, 800, 800)]):
    q = cur.crop(box).resize((1200, 1200), Image.Resampling.NEAREST); crop.paste(q, ((k % 2) * 1200, (k // 2) * 1200), q)
crop.save(cand / 'regions_3x.png')

# DS2 well at game size: 72 px tile, art inset 10%, at 1x (1080p) and 2x (Retina/4K).
WT = Path('/Users/crisu/Price of Everything/poe-goods-icons/price-of-everything-0.1/assets/icons/goods/alternate_icons')
neigh = [('lithium batt. (old)', POE / 'assets/icons/goods/medium/g_059_lithium_battery.png'),
         ('alkaline', WT / 'very_small/g_070_alkaline_battery.png'), ('power', WT / 'very_small/g_010_power.png'),
         ('electrical', ALT / 'very_small/g_036_electrical_components.png'), ('computer', ALT / 'very_small/g_042_computer.png')]
tiles = [('sodium (old)', Image.open(REF).convert('RGBA')), ('sodium (new)', cur)]
tiles += [(n, Image.open(f).convert('RGBA')) for n, f in neigh]
well = Image.new('RGB', (40 + len(tiles) * 170, 420), STEEL); d = ImageDraw.Draw(well)
for i, (name, im) in enumerate(tiles):
    for row, (px, y) in enumerate([(72, 40), (144, 190)]):
        t = Image.new('RGBA', (px, px), (0, 0, 0, 0)); td = ImageDraw.Draw(t)
        td.rounded_rectangle((0, 0, px - 1, px - 1), radius=round(px * 0.074), fill=CREAM)
        inset = round(px * 0.10); art = px - 2 * inset
        src = im.crop(im.getbbox()); k = art / max(src.size)
        a = src.resize((max(1, round(src.width * k)), max(1, round(src.height * k))), Image.Resampling.BOX)
        t.alpha_composite(a, ((px - a.width) // 2, (px - a.height) // 2))
        td.rounded_rectangle((0, 0, px - 1, px - 1), radius=round(px * 0.074), outline=(70, 76, 86), width=max(1, px // 36))
        well.paste(t, (20 + i * 170 + (150 - px) // 2, y), t)
    d.text((20 + i * 170, 350), name, font=F, fill=(232, 238, 247))
d.text((20, 8), '72 px well (1080p) and 144 px (Retina/4K), art inset 10%', font=F, fill=(232, 238, 247))
well.save(cand / 'ds2_well.png')

a = np.array(cur); m = a[..., 3] > 128; ys, xs = np.where(m)
rgb = a[..., :3].astype(int); luma = rgb @ np.array([0.299, 0.587, 0.114])
ink = m & (luma < 60)
green = m & (rgb[..., 1] > rgb[..., 0] + 25) & (rgb[..., 1] > rgb[..., 2])
cream = m & (rgb.min(axis=-1) > 190) & (rgb[..., 0] >= rgb[..., 2])
def peaks(mask):
    h, _ = np.histogram(luma[mask], bins=64, range=(0, 256))
    return [(i * 4, int(h[i])) for i in range(1, 63) if h[i] >= h[i - 1] and h[i] >= h[i + 1] and h[i] > 300]
metrics = {'bbox': [int(xs.min()), int(ys.min()), int(xs.max() + 1), int(ys.max() + 1)],
           'aspect': round(float((xs.max() - xs.min() + 1) / (ys.max() - ys.min() + 1)), 3),
           'ink_mode': [int(v) for v in np.median(rgb[ink], axis=0)] if ink.any() else None,
           'pure_black_px': int((m & (rgb.max(axis=-1) < 12)).sum()),
           'grey_luma_peaks': peaks(m & ~ink & ~green & ~cream),
           'green_share': round(float(green.sum() / m.sum()), 3), 'cream_share': round(float(cream.sum() / m.sum()), 3)}
(cand / 'pixel_metrics.json').write_text(json.dumps(metrics, indent=2) + '\n'); print(json.dumps(metrics))
