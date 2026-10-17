"""Proof sheets for the engine: shipped art | previous | candidate on the set's cream, the same at 60 px, and 3x crops
of four regions. Usage: engine_proof.py <out_dir> [previous_800.png]"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

GAME = Path(__file__).resolve().parents[3]
REF = GAME / 'assets/icons/goods/medium/g_046_engine.png'
CREAM = (235, 232, 222, 255)
# regions on the 800 px master (and the same fraction of the reference): timing end, covers, intake, exhaust side
REGIONS = {'timing_pulleys': (60, 380, 400, 760), 'covers_intake': (180, 40, 620, 400), 'exhaust_side': (420, 300, 780, 660),
           'pan_sump': (200, 560, 760, 790)}


def on_cream(im, size):
    im = im.convert('RGBA'); im.thumbnail((size, size), Image.Resampling.LANCZOS)
    c = Image.new('RGBA', (size, size), CREAM); c.alpha_composite(im, ((size - im.width) // 2, (size - im.height) // 2)); return c


def main():
    out = Path(sys.argv[1]); cand = Image.open(out / 'engine_800.png')
    prev = Image.open(sys.argv[2]) if len(sys.argv) > 2 else None
    ref = Image.open(REF)
    cols = [ref] + ([prev] if prev else []) + [cand]
    sheet = Image.new('RGBA', (800 * len(cols), 800 + 120), CREAM)
    for k, im in enumerate(cols):
        sheet.alpha_composite(on_cream(im, 800), (800 * k, 0))
        sheet.alpha_composite(on_cream(im, 60), (800 * k + 370, 830))
    sheet.save(out / 'engine_sheet.png')
    ref800 = on_cream(ref, 800); cand800 = on_cream(cand, 800)
    rows = []
    for name, box in REGIONS.items():
        a = ref800.crop(box); b = cand800.crop(box); w, h = a.size
        row = Image.new('RGBA', (w * 2 + 10, h), (255, 255, 255, 255)); row.paste(a, (0, 0)); row.paste(b, (w + 10, 0))
        ImageDraw.Draw(row).text((4, 4), name, fill=(200, 0, 0, 255)); rows.append(row)
    W = max(r.width for r in rows); H = sum(r.height for r in rows)
    crops = Image.new('RGBA', (W, H), (255, 255, 255, 255)); y = 0
    for r in rows:
        crops.paste(r, (0, y)); y += r.height
    crops.resize((W * 3 // 2, H * 3 // 2), Image.Resampling.NEAREST).save(out / 'engine_regions.png')
    print(out / 'engine_sheet.png', out / 'engine_regions.png')


main()
