#!/usr/bin/env python3
"""Measure/preview offline game sprites at their real map scale (requires Pillow).
This does not redesign assets: inputs are the engine's own deterministic bakes.
"""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

PROJECT = Path(__file__).resolve().parents[2]
SOURCE = PROJECT / 'assets/supply_chain_3d/far_sprites'
OUT = PROJECT.parent / 'outputs/supply-chain-3d/far-sprites'
OUT.mkdir(parents=True, exist_ok=True)
manifest = json.loads((SOURCE / 'manifest.json').read_text())
rows = []
for key, data in manifest['assets'].items():
    cell = data['cell']
    atlas = Image.open(SOURCE / f'{key}.png').convert('RGBA')
    home = atlas.crop((2 * cell, cell, 3 * cell, 2 * cell))
    sizes = {}
    for label, ppu in [('cutoff', .27), ('continent', 1080 / 10724.780957), ('maximum', 1080 / 28000)]:
        side = max(1, round(data['span'] * data['reference_scale'] * ppu))
        image = home.resize((side, side), Image.Resampling.LANCZOS)
        # Report visible shape, excluding alpha gutter and filter's <10% fringe.
        box = image.getchannel('A').point(lambda x: 255 if x > 25 else 0).getbbox()
        sizes[label] = {'card_px': [side, side], 'visible_px': [box[2] - box[0], box[3] - box[1]] if box else [0, 0]}
        folder = OUT / ('native_' + label)
        folder.mkdir(exist_ok=True)
        image.save(folder / f'{key}.png')
    rows.append({'asset': key, 'world_scale': data['reference_scale'], 'sizes': sizes})
(OUT / 'sizes.json').write_text(json.dumps({'logical_viewport_height': 1080, 'assets': rows}, indent=2) + '\n')

keys = ['tree_lvl1', 'tree_lvl2', 'tree_lvl3', 'warehouse_lvl1',
        'house_lvl1', 'house_lvl3', 'industrial_factory_lvl1', 'industrial_factory_lvl3',
        'furnace_lvl3', 'petro_refinery_lvl3', 'mine_flush_lvl3', 'towers_lvl2']
labels = ['Small tree', 'Fir', 'Large tree', 'Warehouse / NPC depot',
          'Terrace (scale reference)', 'Apartments (scale reference)', 'Factory, level 1', 'Factory, level 3',
          'Furnace, level 3', 'Refinery, level 3', 'Mine, level 3', 'Tower (scale reference)']
font_path = '/System/Library/Fonts/Supplemental/Arial.ttf'
font = ImageFont.truetype(font_path, 16)
small = ImageFont.truetype(font_path, 13)
title = ImageFont.truetype(font_path, 26)
sheet = Image.new('RGB', (1240, 1280), '#ece6d5')
draw = ImageDraw.Draw(sheet)
draw.text((28, 20), 'Far LOD sprites — original world proportions', font=title, fill='#2f3b59')
draw.text((28, 58), 'Each card: actual screen size at the sprite cutoff (0.27 px/u), then a 4× pixel enlargement.', font=font, fill='#4e584e')
draw.text((28, 82), 'Trees stay small beside houses and industry. Tower and housing sprites are scale references; town masses are unchanged.', font=small, fill='#4e584e')
for i, (key, label) in enumerate(zip(keys, labels)):
    x = 28 + i % 4 * 304
    y = 125 + i // 4 * 380
    draw.rounded_rectangle((x, y, x + 285, y + 360), radius=10, fill='#f4efdf', outline='#c6c3ae')
    draw.text((x + 14, y + 12), label, font=font, fill='#2f3b59')
    image = Image.open(OUT / 'native_cutoff' / f'{key}.png')
    sheet.paste(image, (x + (285 - image.width) // 2, y + 46), image)
    zoom = image.resize((image.width * 4, image.height * 4), Image.Resampling.NEAREST)
    sheet.paste(zoom, (x + (285 - zoom.width) // 2, y + 105), zoom)
    row = next(r for r in rows if r['asset'] == key)
    visible = row['sizes']['cutoff']['visible_px']
    far = row['sizes']['maximum']['visible_px']
    draw.text((x + 14, y + 334), f'Visible: {visible[0]} × {visible[1]} px   |   max zoom: {far[0]} × {far[1]} px', font=small, fill='#4e584e')
sheet.save(OUT / 'proportions.png')
print(OUT / 'proportions.png')
