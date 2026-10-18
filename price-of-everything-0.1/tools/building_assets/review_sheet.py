"""Review sheets for a paper-printed building revision: front and rear, and 70 px readability.

python3 review_sheet.py <revision> <family> [--control <sprite.png> ...]

1. Prints the rear renders from review_reverse.py exactly like the front sprites (same crop
   rule and scale, the Paper WPA print from furnace_paper.py) into review/reverse/.
2. Writes review/front-reverse.png: all levels, front above rear, on paper.
3. Writes review/readability.png and prints, for every level and any --control sprites, the
   edge density (edge pixels per opaque pixel) and tone spread at 70 px. The map shows
   buildings at about that size; higher edge density reads as speckle there. For reference,
   the 17 October furnace sits at 0.32 to 0.37.
"""
import argparse, importlib.util
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont

PAPER = (0xec, 0xe0, 0xc6, 255)
GREEN = (120, 140, 90, 255)
FONT = '/System/Library/Fonts/Supplemental/Arial.ttf'


def on(bg, im):
    c = Image.new('RGBA', im.size, bg); c.alpha_composite(im); return c


def fit(im, size):
    im = im.crop(im.getchannel('A').getbbox())
    s = size/max(im.size)
    return im.resize((max(1, round(im.width*s)), max(1, round(im.height*s))), Image.Resampling.LANCZOS)


def readability(im):
    t = fit(im, 70); a = np.array(t.getchannel('A')) > 128
    g = np.array(t.convert('L')).astype(float)
    gx = np.abs(np.diff(g, axis=1))[:-1, :]; gy = np.abs(np.diff(g, axis=0))[:, :-1]
    edges = ((gx+gy) > 40) & a[:-1, :-1]
    return edges.sum()/a.sum(), g[a].std()


def main():
    ap = argparse.ArgumentParser(); ap.add_argument('revision', type=Path); ap.add_argument('family')
    ap.add_argument('--control', nargs='*', default=[], type=Path); a = ap.parse_args()
    R, F = a.revision.resolve(), a.family
    levels = sorted(int(p.stem.rsplit('lvl', 1)[1]) for p in R.glob(f'{F}_lvl[0-9].png'))
    spec = importlib.util.spec_from_file_location('fp', R/'source/furnace_paper.py')
    fp = importlib.util.module_from_spec(spec); spec.loader.exec_module(fp)
    D = R/'review/reverse'
    for L in levels:
        raw = D/f'{F}_L{L}_reverse_raw.png'
        if not raw.exists(): continue
        box = Image.open(raw).convert('RGBA').getchannel('A').getbbox()
        w, h = box[2]-box[0], box[3]-box[1]; s = min(fp.EXPORT_SCALE, 788/max(w, h))
        size = (round(w*s), round(h*s)); xy = ((800-size[0])//2, (800-size[1])//2)
        for suffix, src in (('', raw.name), ('_mask', f'{F}_L{L}_reverse_mask_raw.png')):
            out = Image.new('RGBA', (800, 800), (0, 0, 0, 0))
            out.alpha_composite(Image.open(D/src).convert('RGBA').crop(box).resize(size, Image.Resampling.LANCZOS), xy)
            out.save(D/f'{F}_lvl{L}_reverse{suffix}.png')
        fp.finish(D/f'{F}_lvl{L}_reverse.png', D/f'{F}_lvl{L}_reverse_mask.png')
    font = ImageFont.truetype(FONT, 22)
    sheet = Image.new('RGB', (len(levels)*560+40, 2*560+90), PAPER[:3]); d = ImageDraw.Draw(sheet)
    for i, L in enumerate(levels):
        x = 20+i*560
        for row, (path, label) in enumerate(((R/f'{F}_lvl{L}.png', 'front'), (D/f'{F}_lvl{L}_reverse.png', 'rear'))):
            if not path.exists(): continue
            im = Image.open(path).convert('RGBA').resize((540, 540), Image.Resampling.LANCZOS)
            y = 40+row*570; sheet.paste(im, (x, y), im); d.text((x+10, y-30), f'L{L}  {label}', fill='#1f2b36', font=font)
    sheet.save(R/'review/front-reverse.png')
    items = [(f'L{L}', R/f'{F}_lvl{L}.png') for L in levels]+[(p.stem, p) for p in a.control]
    small = ImageFont.truetype(FONT, 14)
    tiles = Image.new('RGB', (len(items)*180+20, 300), 'white'); d = ImageDraw.Draw(tiles)
    for i, (name, path) in enumerate(items):
        im = Image.open(path).convert('RGBA'); e, t = readability(im)
        print(f'{name:28} edge_px/opaque={e:.2f} tone_std={t:.1f}')
        for j, bg in enumerate((PAPER, GREEN)):
            c = Image.new('RGBA', (70, 70), bg); f = fit(im, 70); c.alpha_composite(f, ((70-f.width)//2, (70-f.height)//2))
            tiles.paste(c.resize((140, 140), Image.Resampling.NEAREST).convert('RGB'), (10+i*180, 10+j*145))
        d.text((10+i*180, 292-14), f'{name} {e:.2f}', fill='black', font=small)
    tiles.save(R/'review/readability.png')
    print('wrote', R/'review/front-reverse.png', 'and', R/'review/readability.png')


if __name__ == '__main__':
    main()
