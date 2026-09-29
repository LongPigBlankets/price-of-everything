"""Owner sheet: original vs candidate, the progress strip, and the DS2 well at game size."""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
POE = Path('/Users/crisu/Price of Everything/price-of-everything/price-of-everything-0.1')
root = Path(sys.argv[1]); cand = sys.argv[2]; steps = sys.argv[3:]
F = lambda n: ImageFont.truetype(str(POE / 'assets/fonts/IBMPlexSans-Medium.ttf'), n)
H = lambda n: ImageFont.truetype(str(POE / 'assets/fonts/BebasNeue-Regular.ttf'), n)
PAPER = (245, 241, 231); INK = (20, 30, 60); STEEL = (30, 35, 43); CREAM = (254, 237, 195)
def fit(im, w, h):
    im = im.crop(im.getbbox()); k = min(w / im.width, h / im.height)
    return im.resize((round(im.width * k), round(im.height * k)), Image.Resampling.LANCZOS)
ref = Image.open(POE / 'assets/icons/goods/medium/g_009_pure_water.png').convert('RGBA')
cur = Image.open(root / cand / 'pure_water_800.png').convert('RGBA')
W = 1600; sheet = Image.new('RGB', (W, 1720), PAPER); d = ImageDraw.Draw(sheet)
d.text((40, 24), 'PURE WATER (G_009): BLENDER CANDIDATE ' + cand.upper(), font=H(58), fill=INK)
d.text((40, 92), 'Fixed goods camera, the set\'s 12/6 px navy ink and dot density, clean water. Not installed.', font=F(24), fill=INK)
for i, (title, im) in enumerate([('Shipped art (reference)', ref), ('Blender ' + cand, cur)]):
    q = fit(im, 700, 700); x = 40 + i * 780 + (740 - q.width) // 2
    sheet.paste(q, (x, 150), q); d.text((40 + i * 780, 860), title, font=F(26), fill=INK)
d.text((40, 920), 'HOW IT GOT HERE', font=H(40), fill=INK)
for i, st in enumerate(steps):
    q = fit(Image.open(root / st / 'pure_water_800.png').convert('RGBA'), 280, 280)
    x = 40 + i * 300; sheet.paste(q, (x + (280 - q.width) // 2, 975), q); d.text((x, 1262), st, font=F(22), fill=INK)
well = Image.new('RGB', (W - 80, 330), STEEL); wd = ImageDraw.Draw(well)
ALT = POE / 'assets/icons/goods/alternate_icons/very_small'
tiles = [('old art', ref), ('new', cur)] + [(n, Image.open(ALT / (f + '.png')).convert('RGBA')) for n, f in
         [('hydrogen', 'g_014_hydrogen'), ('ethylene', 'g_024_ethylene'), ('crude oil', 'g_026_crude_oil'), ('glass', 'g_038_glass'), ('copper pipe', 'g_021_copper_pipe')]]
for i, (name, im) in enumerate(tiles):
    for px, y in [(72, 30), (144, 130)]:
        t = Image.new('RGBA', (px, px)); td = ImageDraw.Draw(t)
        td.rounded_rectangle((0, 0, px - 1, px - 1), radius=round(px * .074), fill=CREAM)
        q = fit(im, px - 2 * round(px * .1), px - 2 * round(px * .1))
        t.alpha_composite(q, ((px - q.width) // 2, (px - q.height) // 2))
        td.rounded_rectangle((0, 0, px - 1, px - 1), radius=round(px * .074), outline=(70, 76, 86), width=max(1, px // 36))
        well.paste(t, (30 + i * 205 + (150 - px) // 2, y), t)
    wd.text((30 + i * 205, 285), name, font=F(22), fill=(232, 238, 247))
d.text((40, 1310), 'IN A DS2 WELL: 72 PX (1080P) AND 144 PX (RETINA/4K)', font=H(40), fill=INK)
sheet.paste(well, (40, 1360))
out = root / cand / 'owner_sheet.png'; sheet.save(out); print(out)
