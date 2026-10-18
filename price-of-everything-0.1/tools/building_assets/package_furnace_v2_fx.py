"""Align the furnace's raw window/heat masks and chimney anchors to its 800 px sprites.

python3 package_furnace_v2_fx.py <revision>

Applies the same crop and scale as furnace_paper.export, so the masks register with the
sprites pixel for pixel. Writes fx/windows/furnace_lvl{n}.png, fx/light/furnace_lvl{n}.png
and fx/anchors.json (empire_fx.gd ANCHORS["furnace"]). Asserts every mask stays inside
its sprite and covers less than 2% of it.
"""
from pathlib import Path
import json, sys, hashlib
import numpy as np
from PIL import Image

root = Path(sys.argv[1]).resolve()
report = json.loads((root/'fx_raw'/'report.json').read_text())
factor = json.loads((root/'manifest.json').read_text())['sprite_scale']
validation, anchors = {}, {}
for level in (1, 2, 3):
    box = Image.open(root/f'furnace_v2_L{level}.png').getchannel('A').getbbox()
    w, h = box[2]-box[0], box[3]-box[1]
    nw, nh = round(w*factor), round(h*factor)
    xy = ((800-nw)//2, (800-nh)//2)
    sprite = np.array(Image.open(root/f'furnace_v2_lvl{level}.png'))
    anchors[str(level)] = {'stacks': [{'x': round(xy[0]+(a['x']-box[0])*nw/w), 'y': round(xy[1]+(a['y']-box[1])*nh/h),
                                       'r': max(8, round(a['radius']*factor)), 'kind': 'auto'}
                                      for a in report[str(level)]['raw_smoke_anchors']]}
    for kind in ('windows', 'light'):
        a = np.array(Image.open(root/'fx_raw'/f'furnace_v2_lvl{level}_{kind}.png').convert('RGBA')).astype(float)/255
        mask = Image.fromarray(np.round(a[:, :, 0]*a[:, :, 3]*255).astype('uint8'))
        mask = mask.crop(box).resize((nw, nh), Image.Resampling.LANCZOS)
        alpha = Image.new('L', (800, 800)); alpha.paste(mask, xy)
        aa = np.array(alpha); aa[aa < 8] = 0          # drop near-black render dithering
        alpha = Image.fromarray(aa)
        check = {'pixels': int((aa > 128).sum()), 'outside_sprite_pixels': int(((aa > 128) & (sprite[:, :, 3] < 128)).sum())}
        assert check['pixels'] > 0 and check['outside_sprite_pixels'] == 0, (level, kind, check)
        assert check['pixels'] < int((sprite[:, :, 3] > 128).sum())*.02, ('mask leaks onto building materials', level, kind)
        out = Image.new('RGBA', (800, 800), (255, 255, 255, 0)); out.putalpha(alpha)
        dest = root/'fx'/kind; dest.mkdir(parents=True, exist_ok=True)
        target = dest/f'furnace_lvl{level}.png'; out.save(target)
        check['sha256'] = hashlib.sha256(target.read_bytes()).hexdigest()
        validation[f'{level}/{kind}'] = check
        if kind == 'light':
            # Exact mask bounds: the runtime draws one masked breathing rectangle per sprite.
            b = alpha.getbbox()
            anchors[str(level)]['fires'] = [dict(x=b[0], y=b[1], w=b[2]-b[0], h=b[3]-b[1], mode='breathe')]
(root/'fx'/'anchors.json').write_text(json.dumps(anchors, indent=2)+'\n')
(root/'fx'/'mask-validation.json').write_text(json.dumps(validation, indent=2)+'\n')
print(json.dumps(anchors))
print('Aligned', len(validation), 'masks; none outside its sprite.')
