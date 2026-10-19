"""Measure installed still/atlas alpha offline, without re-rendering valid artwork."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ap = argparse.ArgumentParser()
ap.add_argument('--assets', type=Path, default=ROOT/'price-of-everything-0.1/assets/loading/carousel')
args = ap.parse_args()
manifest = json.loads((args.assets/'provenance.json').read_text())
path = args.assets/'smoke-layouts.json'
layouts = json.loads(path.read_text())
families = ('industrial_factory','furnace','power_plant','petro_refinery','farm','offshore_wind_farm')
tops, sources = {}, {}
for family in families:
    top = 1.0
    for look in ('day','night'):
        names = [f'{family}-{look}.png']
        if family in layouts:
            names.append(f'{family}-smoke-{look}.png')
        for name in names:
            file = args.assets/name
            digest = hashlib.sha256(file.read_bytes()).hexdigest()
            assert digest == manifest[name]['sha256'], f'{name}: stale source fingerprint'
            sources[name] = digest
            alpha = np.asarray(Image.open(file).convert('RGBA'))[:,:,3]
            if '-smoke-' not in name:
                rows = np.nonzero(alpha > 8)[0]
                top = min(top, float(rows.min())/alpha.shape[0])
            else:
                layout = layouts[family]
                cell = alpha.shape[0]//layout['rows']
                rows = np.nonzero(alpha > 8)[0] % cell
                top = min(top, layout['rect'][1]+float(rows.min())/cell*layout['rect'][3])
    tops[family] = top
layouts['_composition_tops'] = tops
layouts['_composition_top_sources'] = sources
path.write_text(json.dumps(layouts,indent=2)+'\n')
print(json.dumps(tops,indent=2))
