"""Build/install all six loading tiles, retaining raw renders and source fingerprints.

python3 tools/loading_carousel/build.py --out /absolute/review-directory [--install]
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / '.claude/skills/blender-building-sprites'))
from stylize_shade import stylize

BUILDINGS = ('industrial_factory', 'furnace', 'power_plant', 'petro_refinery', 'farm', 'offshore_wind_farm')
ap = argparse.ArgumentParser()
ap.add_argument('--out', type=Path, required=True)
ap.add_argument('--install', action='store_true')
ap.add_argument('--building', choices=BUILDINGS)
ap.add_argument('--res', type=int, default=1024)
args = ap.parse_args()
raw = args.out / 'raw'
raw.mkdir(parents=True, exist_ok=True)
destination = ROOT / 'price-of-everything-0.1/assets/loading/carousel' if args.install else args.out
destination.mkdir(parents=True, exist_ok=True)
manifest_path = destination / 'provenance.json'
manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
layouts_path = destination / 'smoke-layouts.json'
layouts = json.loads(layouts_path.read_text()) if layouts_path.exists() else {}


def fingerprint(name, entry):
    entry = dict(entry)
    entry['renderer_sha256'] = hashlib.sha256(Path(__file__).with_name('render_tiles.py').read_bytes()).hexdigest()
    entry['print_sha256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    entry['sha256'] = hashlib.sha256((destination/name).read_bytes()).hexdigest()
    manifest[name] = entry


def pack_smoke(family, entry):
    count = entry['smoke_frames']
    if not count:
        return
    assert count == 12, 'Runtime shader uses a 4x3, twelve-frame smoke atlas'
    frames = {look:[Image.open(raw/f'{family}-smoke-{look}-{i:02d}.png').convert('RGBA')
                    for i in range(count)] for look in ('day','night')}
    coverage = np.zeros((args.res,args.res), dtype=np.uint8)
    for images in frames.values():
        for image in images:
            coverage = np.maximum(coverage, np.asarray(image)[:,:,3])
    yy,xx = np.nonzero(coverage > 4)
    assert len(xx), f'{family}: empty smoke loop'
    side = int(max(xx.max()-xx.min()+1, yy.max()-yy.min()+1)+16)
    x = int((xx.max()+xx.min()+1-side)//2)
    y = int((yy.max()+yy.min()+1-side)//2)
    cell = 256
    layouts[family] = {'rect':[x/args.res,y/args.res,side/args.res,side/args.res],
                       'frames':count,'columns':4,'rows':3,'seconds':entry['smoke_seconds']}
    for look,images in frames.items():
        atlas = Image.new('RGBA',(4*cell,3*cell))
        for i,image in enumerate(images):
            tile = image.crop((x,y,x+side,y+side)).resize((cell,cell),Image.Resampling.LANCZOS)
            atlas.paste(tile,((i%4)*cell,(i//4)*cell))
        name = f'{family}-smoke-{look}.png'
        atlas.save(destination/name,optimize=True)
        # Godot fills in remaps/UIDs on import. No atlas mipmaps: they would mix cells.
        sidecar = destination/(name+'.import')
        if not sidecar.exists():
            sidecar.write_text('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n'
                '[params]\n\ncompress/mode=2\ncompress/high_quality=true\n'
                'mipmaps/generate=false\nprocess/fix_alpha_border=true\nprocess/premult_alpha=false\n')
        fingerprint(name,dict(entry,kind='smoke_atlas',**layouts[family]))


for family in ((args.building,) if args.building else BUILDINGS):
    with (args.out / f'{family}.log').open('w') as log:
        subprocess.run(['blender', '-b', '--factory-startup', '--python-exit-code', '1',
            '--python', str(Path(__file__).with_name('render_tiles.py')), '--', '--building', family,
            '--out', str(raw), '--res', str(args.res)], stdout=log, stderr=subprocess.STDOUT, check=True)
    for look in ('day', 'night'):
        name = f'{family}-{look}.png'
        target = destination / name
        shade = raw/f'{family}-shade-night.png'
        if look != 'night' or not shade.exists():
            shade = raw/f'{family}-shade.png'
        stylize(str(raw/name), str(shade), str(target),
                spacing=6.0, dot_r=.85, strength=.18, lit=.86, dark=.56, contrast=1.02)
        if look == 'night':
            # Subtle lamp bloom, restricted to bright warm sources rather than the whole frame.
            image = Image.open(target).convert('RGBA')
            rgba = np.asarray(image).copy()
            r,g,b = [rgba[:,:,i].astype(float)/255 for i in range(3)]
            weight = np.clip((r-.62)/.30,0,1) * (r > b*1.12) * (rgba[:,:,3]/255)
            glow = Image.new('RGBA', image.size, (255,184,84,0))
            glow.putalpha(Image.fromarray((weight*75).astype('uint8')))
            image = Image.alpha_composite(glow.filter(ImageFilter.GaussianBlur(7)), image)
            image.save(target, optimize=True)
        entry = json.loads((raw/f'{family}.json').read_text())
        fingerprint(name,entry)
    pack_smoke(family,entry)
    print(f'{family}: day/night installed, footprint inside hex', flush=True)
(args.out / 'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
shutil.copy2(args.out/'manifest.json', manifest_path)
layouts_path.write_text(json.dumps(layouts,indent=2)+'\n')
