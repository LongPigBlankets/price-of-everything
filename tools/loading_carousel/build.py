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
for family in ((args.building,) if args.building else BUILDINGS):
    with (args.out / f'{family}.log').open('w') as log:
        subprocess.run(['blender', '-b', '--factory-startup', '--python-exit-code', '1',
            '--python', str(Path(__file__).with_name('render_tiles.py')), '--', '--building', family,
            '--out', str(raw), '--res', str(args.res)], stdout=log, stderr=subprocess.STDOUT, check=True)
    for look in ('day', 'night'):
        name = f'{family}-{look}.png'
        target = destination / name
        stylize(str(raw/name), str(raw/f'{family}-shade.png'), str(target),
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
        entry['renderer_sha256'] = hashlib.sha256(Path(__file__).with_name('render_tiles.py').read_bytes()).hexdigest()
        entry['print_sha256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
        entry['sha256'] = hashlib.sha256(target.read_bytes()).hexdigest()
        manifest[name] = entry
    print(f'{family}: day/night installed, footprint inside hex', flush=True)
(args.out / 'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
shutil.copy2(args.out/'manifest.json', manifest_path)
