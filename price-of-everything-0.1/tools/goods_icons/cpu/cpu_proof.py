"""Proof sheet for the CPU: the 450/256/60 px tiers (LANCZOS downsizes of the master), the shipped art beside the
candidate, the master's quadrants at 3x, and the DS2 well at game size beside its neighbours.
    python3 ev_proof.py <candidate_dir>"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
POE = Path('/Users/crisu/Price of Everything/price-of-everything/price-of-everything-0.1')
WT = Path(__file__).resolve().parents[3] / 'assets/icons/goods'
REF = POE / 'assets/icons/goods/medium/g_041_cpu.png'
PAPER = (245, 241, 231); CREAM = (254, 237, 195); STEEL = (30, 35, 43)
F = ImageFont.truetype(str(POE / 'assets/fonts/IBMPlexSans-Medium.ttf'), 20)
cand = Path(sys.argv[1]); cur = Image.open(cand / 'cpu_800.png').convert('RGBA')
for n in (450, 256, 60):
    cur.resize((n, n), Image.Resampling.LANCZOS).save(cand / ('cpu_%d.png' % n))
def fit(im, h, w=620):
    im = im.crop(im.getbbox()); k = min(h / im.height, w / im.width)
    return im.resize((round(im.width * k), round(im.height * k)), Image.Resampling.LANCZOS)
sheet = Image.new('RGB', (1320, 760), PAPER); d = ImageDraw.Draw(sheet)
for i, (t, im) in enumerate((('Original (shipped)', Image.open(REF).convert('RGBA')), ('Candidate: ' + cand.name, cur))):
    q = fit(im, 680); sheet.paste(q, (20 + i * 650 + (620 - q.width) // 2, 60), q); d.text((20 + i * 650, 16), t, font=F, fill=(20, 30, 60))
sheet.save(cand / 'comparison.png')
crop = Image.new('RGB', (2400, 2400), PAPER)
for k, box in enumerate([(0, 0, 400, 400), (400, 0, 800, 400), (0, 400, 400, 800), (400, 400, 800, 800)]):
    q = cur.crop(box).resize((1200, 1200), Image.Resampling.NEAREST); crop.paste(q, ((k % 2) * 1200, (k // 2) * 1200), q)
crop.save(cand / 'regions_3x.png')
tiles = [('cpu (old)', Image.open(REF).convert('RGBA')), ('cpu (new)', cur),
         ('computer', Image.open(WT / 'alternate_icons/very_small/g_042_computer.png').convert('RGBA')),
         ('electrical', Image.open(WT / 'alternate_icons/very_small/g_036_electrical_components.png').convert('RGBA'))]
well = Image.new('RGB', (40 + len(tiles) * 170, 420), STEEL); d = ImageDraw.Draw(well)
for i, (name, im) in enumerate(tiles):
    for px, y in ((72, 40), (144, 190)):
        t = Image.new('RGBA', (px, px), (0, 0, 0, 0)); td = ImageDraw.Draw(t)
        td.rounded_rectangle((0, 0, px - 1, px - 1), radius=round(px * 0.074), fill=CREAM)
        art = px - 2 * round(px * 0.10); src = im.crop(im.getbbox()); k = art / max(src.size)
        a = src.resize((max(1, round(src.width * k)), max(1, round(src.height * k))), Image.Resampling.BOX)
        t.alpha_composite(a, ((px - a.width) // 2, (px - a.height) // 2))
        td.rounded_rectangle((0, 0, px - 1, px - 1), radius=round(px * 0.074), outline=(70, 76, 86), width=max(1, px // 36))
        well.paste(t, (20 + i * 170 + (150 - px) // 2, y), t)
    d.text((20 + i * 170, 350), name, font=F, fill=(232, 238, 247))
d.text((20, 8), '72 px well (1080p) and 144 px (Retina/4K), art inset 10%', font=F, fill=(232, 238, 247))
well.save(cand / 'ds2_well.png'); print('proof written')
