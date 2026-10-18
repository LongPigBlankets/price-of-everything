"""Align a staged building's raw masks and anchors (building_fx.py) to its 800 px sprites:
the general form of package_furnace_v2_fx.py.

python3 package_building_fx.py <revision> <family>

Applies the same crop and scale as furnace_paper.export, so the masks register with the
sprites pixel for pixel. Writes fx/windows/<game>_lvl{n}.png and fx/light/<game>_lvl{n}.png
where the building has them, and fx/anchors_<game>.json for empire_fx.gd ANCHORS[<game>].
Asserts every mask stays inside its sprite and covers less than 4% of it.
"""
from pathlib import Path
import json, sys, hashlib
import numpy as np
from PIL import Image

GAME_NAME = {'petro_refinery_v2': 'petro_refinery', 'poly_plant_v2': 'poly_plant', 'power_plant_v2': 'power_plant'}

root = Path(sys.argv[1]).resolve()
family = sys.argv[2]
game = GAME_NAME[family]
report = json.loads((root/'fx_raw'/'report.json').read_text())
factor = json.loads((root/'manifest.json').read_text())['sprite_scale']
validation, anchors = {}, {}
for level in (1, 2, 3):
    entry = report[f'{family}/{level}']
    box = Image.open(root/f'{family}_L{level}.png').getchannel('A').getbbox()
    w, h = box[2]-box[0], box[3]-box[1]
    nw, nh = round(w*factor), round(h*factor)
    xy = ((800-nw)//2, (800-nh)//2)

    def at(p):
        return [round(xy[0]+(p[0]-box[0])*nw/w), round(xy[1]+(p[1]-box[1])*nh/h)]
    sprite = np.array(Image.open(root/f'{family}_lvl{level}.png'))
    stacks = []
    for kind, tag in (('smoke', 'auto'), ('steam', 'steam')):
        for a in entry[kind]:
            x, y = at((a['x'], a['y']))
            stacks.append({'x': x, 'y': y, 'r': max(8, round(a['radius']*factor)), 'kind': tag})
    anchors[level] = {'stacks': stacks, 'fires': []}
    if entry['cables']:
        anchors[level]['cables'] = [[at(p) for p in line] for line in entry['cables']]
    for kind in ('windows', 'light'):
        raw = root/'fx_raw'/f'{family}_lvl{level}_{kind}.png'
        if not raw.exists(): continue
        a = np.array(Image.open(raw).convert('RGBA')).astype(float)/255
        mask = Image.fromarray(np.round(a[:, :, 0]*a[:, :, 3]*255).astype('uint8'))
        mask = mask.crop(box).resize((nw, nh), Image.Resampling.LANCZOS)
        alpha = Image.new('L', (800, 800)); alpha.paste(mask, xy)
        aa = np.array(alpha); aa[aa < 8] = 0          # drop near-black render dithering
        alpha = Image.fromarray(aa)
        check = {'pixels': int((aa > 128).sum()), 'outside_sprite_pixels': int(((aa > 128) & (sprite[:, :, 3] < 128)).sum())}
        assert check['pixels'] > 0 and check['outside_sprite_pixels'] == 0, (level, kind, check)
        # 4%, not the furnace's 2%: the power plant's turbine hall has 24 small windows. A mask
        # that leaked onto a wall or roof would cover far more.
        assert check['pixels'] < int((sprite[:, :, 3] > 128).sum())*.04, ('mask leaks onto building materials', level, kind)
        out = Image.new('RGBA', (800, 800), (255, 255, 255, 0)); out.putalpha(alpha)
        dest = root/'fx'/kind; dest.mkdir(parents=True, exist_ok=True)
        target = dest/f'{game}_lvl{level}.png'; out.save(target)
        check['sha256'] = hashlib.sha256(target.read_bytes()).hexdigest()
        validation[f'{level}/{kind}'] = check
        if kind == 'light':
            b = alpha.getbbox()
            anchors[level]['fires'] = [dict(x=b[0], y=b[1], w=b[2]-b[0], h=b[3]-b[1], mode='breathe')]
(root/'fx').mkdir(exist_ok=True)
(root/'fx'/f'anchors_{game}.json').write_text(json.dumps(anchors, indent=2)+'\n')
(root/'fx'/f'mask-validation_{game}.json').write_text(json.dumps(validation, indent=2)+'\n')
print(json.dumps(anchors))
print('Aligned', len(validation), 'masks for', game, '; none outside its sprite.')
