#!/usr/bin/env python3
"""Reproducible build -> render -> measure -> review -> install building pipeline.

python3 tools/building_assets/pipeline.py build --revision v1
python3 tools/building_assets/pipeline.py verify --revision v1
python3 tools/building_assets/pipeline.py models --revision v1
python3 tools/building_assets/pipeline.py install --revision v1
Each immutable revision owns its source, logs, .blend files, masks and sprite exports.
"""
import argparse
import hashlib
import importlib.util
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
GAME = HERE.parents[1]
ROOT = GAME.parent
KIT = ROOT / '.claude/skills/blender-building-sprites'
OUTPUT = ROOT / 'outputs/building-assets-2026-10-08'
SPRITES = GAME / 'assets/icons/buildings/sprites'
FAMILIES = ('farm', 'water_pump', 'new_forest', 'old_forest', 'desal', 'oil_well', 'fracking_oil_well')
LABELS = dict(zip(FAMILIES, ('FARM', 'WATER PUMP', 'NEW GROWTH', 'OLD GROWTH', 'DESALINATION', 'OIL WELL', 'SHALE OIL WELL')))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def module(path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def metrics(path, mask_path=None):
    im = Image.open(path).convert('RGBA')
    a = np.asarray(im)
    bbox = im.getchannel('A').getbbox()
    assert im.size == (800,800), f'Wrong size: {path}'
    assert bbox and min(bbox[0],bbox[1],800-bbox[2],800-bbox[3]) >= 4, f'Clipped: {path}'
    assert np.count_nonzero(a[:,:,3]>128)>15000, f'Empty/small: {path}'
    opaque = a[:,:,:3][a[:,:,3]>240]
    q = (opaque//8)*8
    colours,counts = np.unique(q,axis=0,return_counts=True)
    dominant = colours[np.argsort(counts)[-8:][::-1]].tolist()
    result = dict(size=list(im.size),bbox=list(bbox),opaque_pixels=len(opaque),
                  dominant_rgb=dominant,sha256=sha(path))
    if mask_path:
        mask=np.asarray(Image.open(mask_path).convert('RGBA'))
        values=mask[:,:,0][mask[:,:,3]>240]
        assert values.size and int(values.max())-int(values.min())>35, f'Flat shading mask: {path}'
        result['mask_range']=[int(values.min()),int(values.max())]
    return result


def sheet(revision, families):
    # Proof explicitly includes thumbnail scale and the shipped industrial style control.
    font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',20) if Path('/System/Library/Fonts/Supplemental/Arial.ttf').exists() else ImageFont.load_default()
    small=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',14) if Path('/System/Library/Fonts/Supplemental/Arial.ttf').exists() else font
    canvas=Image.new('RGB',(1400,100+len(families)*335),(238,233,219))
    draw=ImageDraw.Draw(canvas)
    draw.text((28,22),'CARBON & CAPITAL / BUILDING ASSET PROOF',fill='#2f3b59',font=font)
    draw.text((28,53),'Detailed geometry • original isometric rig • shared level scale • 800px transparent sprites',fill='#56606a',font=small)
    control=Image.open(SPRITES/'industrial_factory_lvl2.png').convert('RGBA')
    for row,name in enumerate(families):
        top=95+row*335
        draw.line((25,top,1375,top),fill='#c9c2b1')
        draw.text((30,top+14),LABELS[name],fill='#2f3b59',font=font)
        for level in (1,2,3):
            x=205+(level-1)*310
            im=Image.open(revision/f'{name}_lvl{level}.png').convert('RGBA')
            canvas.paste(im.resize((300,300),Image.Resampling.LANCZOS),(x,top+15),im.resize((300,300),Image.Resampling.LANCZOS))
            draw.text((x+10,top+12),f'L{level}',fill='#2f3b59',font=small)
            thumb=im.resize((64,64),Image.Resampling.LANCZOS)
            canvas.paste(thumb,(5+(level-1)*64,top+230),thumb)
        icon=control.resize((225,225),Image.Resampling.LANCZOS)
        canvas.paste(icon,(1150,top+55),icon)
        draw.text((1155,top+18),'EXISTING STYLE',fill='#56606a',font=small)
    canvas.save(revision/'proof.png')


def verify(revision):
    manifest=json.loads((revision/'manifest.json').read_text())
    for rel,digest in manifest['source_sha256'].items():
        assert sha(revision/'source'/rel)==digest, f'Source changed: {rel}'
    for filename,data in manifest['sprites'].items():
        assert sha(revision/filename)==data['sha256'], f'Output changed: {filename}'
        metrics(revision/filename,revision/filename.replace('.png','_mask.png'))
    for filename,digest in manifest.get('models',{}).items():
        assert sha(revision/'models'/filename)==digest, f'Model changed: {filename}'
    for name in manifest['families']:
        assert len({manifest['sprites'][f'{name}_lvl{l}.png']['sha256'] for l in (1,2,3)})==3, f'Duplicate upgrades: {name}'
    print(f"Verified {len(manifest['sprites'])} sprites and frozen source.",flush=True)
    return manifest


def build(revision,families):
    if revision.exists():
        raise SystemExit(f'Revision already exists: {revision}. Choose a new revision to preserve review evidence.')
    source=revision/'source'
    source.mkdir(parents=True)
    # Freeze the actual renderer and approved kit, not only the parameter file.
    for name in ('sprite_kit.py','props_kit.py','render_sprite.py','sprite_export.py','stylize_shade.py','bake_sprite.py'):
        shutil.copy2(KIT/name,source/name)
    shutil.copy2(HERE/'builders.py',source/'builders.py')
    shutil.copy2(__file__,source/'pipeline.py')
    shutil.copy2(HERE.parent/'supply_chain_3d/export_models.py',source/'export_models.py')
    # The legacy renderer executes one builder in Kit's namespace. This adapter also
    # installs the approved foliage assemblies and retains every editable source mesh.
    (source/'entry.py').write_text(
        "import pathlib, sys\n"
        "_src=pathlib.Path(sys.argv[sys.argv.index('--python')+1]).parent\n"
        "exec((_src/'props_kit.py').read_text(),globals())\n"
        "exec((_src/'builders.py').read_text(),globals())\n")
    with (source/'render_sprite.py').open('a') as f:
        f.write("\n# Editable source scene, saved after restoring colour-pass settings.\n"
                "scene.render.filepath = out_png\n"
                "bpy.ops.wm.save_as_mainfile(filepath=out_png.rsplit('.',1)[0]+'.blend')\n")
    manifest=dict(format_version=1,revision=revision.name,families=list(families),outer_contour=False,
                  source_sha256={p.name:sha(p) for p in source.iterdir() if p.is_file()},sprites={})
    exporter=module(source/'sprite_export.py')
    stylizer=module(source/'stylize_shade.py')
    for name in families:
        for level in (1,2,3):
            out=revision/f'{name}_L{level}.png'
            cmd=['blender','--background','--factory-startup','--python',str(source/'render_sprite.py'),
                 '--','entry.py','build_'+name,str(level),str(out),'BLDG_'+name]
            print(f'Rendering {name} L{level}',flush=True)
            log=revision/f'{name}_L{level}.log'
            with log.open('w') as stream:
                run=subprocess.run(cmd,stdout=stream,stderr=subprocess.STDOUT)
            if run.returncode or 'MASK_OK' not in log.read_text():
                raise RuntimeError(f'Render failed ({run.returncode}): {log}\n{log.read_text()[-4000:]}')
            raw=Image.open(out)
            b=raw.getchannel('A').getbbox()
            assert b and min(b[0],b[1],raw.width-b[2],raw.height-b[3])>8, f'Raw render clipped: {out}'
        # Owner: remove the heavy outer navy line; preserve both Freestyle detail tiers.
        exporter.export(str(revision),name,contour=False)
        for level in (1,2,3):
            out=revision/f'{name}_lvl{level}.png'
            mask=revision/f'{name}_lvl{level}_mask.png'
            stylizer.stylize(str(out),str(mask),str(out),lit=.86,dark=.56,strength=.22)
            manifest['sprites'][out.name]=metrics(out,mask)
        (revision/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    sheet(revision,families)
    verify(revision)


def install(revision):
    manifest=verify(revision)
    backup=revision/'previous-installed'
    backup.mkdir(exist_ok=True)
    for filename in manifest['sprites']:
        target=SPRITES/filename
        if target.exists() and not (backup/filename).exists():
            shutil.copy2(target,backup/filename)
        # Replacing each complete PNG is atomic; existing import UIDs remain untouched.
        temp=SPRITES/(filename+'.tmp')
        shutil.copy2(revision/filename,temp)
        temp.replace(target)
        import_file=SPRITES/(filename+'.import')
        if not import_file.exists():
            # Reuse the set's lossless/mipmapped import contract, with a fresh UID.
            template=SPRITES/'industrial_factory_lvl2.png.import'
            metadata=template.read_text()
            old_path='res://assets/icons/buildings/sprites/industrial_factory_lvl2.png'
            new_path='res://assets/icons/buildings/sprites/'+filename
            old_hash=hashlib.md5(old_path.encode()).hexdigest()
            new_hash=hashlib.md5(new_path.encode()).hexdigest()
            metadata=re.sub(r'^uid=.*\n','',metadata,flags=re.MULTILINE)
            metadata=metadata.replace(old_hash,new_hash).replace('industrial_factory_lvl2.png',filename)
            import_file.write_text(metadata)
    # A partial-family install must retain the other families' provenance.
    record_path=SPRITES/'detailed_buildings_manifest.json'
    previous=json.loads(record_path.read_text()) if record_path.exists() else {}
    if record_path.exists() and not (backup/'sprite_manifest.json').exists():
        shutil.copy2(record_path,backup/'sprite_manifest.json')
    families=dict(previous.get('family_revisions',{}))
    if not families:
        for name in previous.get('families',[]):
            families[name]=dict(revision=previous.get('revision'),source_sha256=previous.get('source_sha256',{}))
    for name in manifest['families']:
        families[name]=dict(revision=manifest['revision'],source_sha256=manifest['source_sha256'],
                            outer_contour=manifest.get('outer_contour',True))
    record=dict(format_version=2,families=sorted(families),family_revisions=families,
                sprites={**previous.get('sprites',{}),**manifest['sprites']},
                models={k:v for k,v in {**previous.get('models',{}),**manifest.get('models',{})}.items()
                        if k!='manifest.json'})
    if manifest.get('models'):
        model_dir=GAME/'assets/supply_chain_3d'
        current=json.loads((model_dir/'manifest.json').read_text())
        additions=json.loads((revision/'models/manifest.json').read_text())
        # Retire only this revision's explicitly disabled contour shells. Keep a
        # rollback copy and remove their import sidecars and stale provenance.
        for key, data in additions.items():
            if data.get('contour',False): continue
            filename=key+'_contour.glb'
            record['models'].pop(filename,None)
            for name in (filename,filename+'.import'):
                target=model_dir/name
                if target.exists():
                    if not (backup/name).exists(): shutil.copy2(target,backup/name)
                    target.unlink()
        for filename in manifest['models']:
            if filename=='manifest.json': continue
            target=model_dir/filename
            if target.exists() and not (backup/filename).exists():
                shutil.copy2(target,backup/filename)
            shutil.copy2(revision/'models'/filename,target)
        if not (backup/'model_manifest.json').exists():
            shutil.copy2(model_dir/'manifest.json',backup/'model_manifest.json')
        current.update(additions)
        (model_dir/'manifest.json').write_text(json.dumps(current,indent=2)+'\n')
    record_path.write_text(json.dumps(record,indent=2)+'\n')
    print(f'Installed {len(manifest["sprites"])} sprites. Run Godot headless import.',flush=True)


def models(revision):
    manifest=verify(revision)
    destination=revision/'models'
    if destination.exists(): raise SystemExit('Models already exported; keep the reviewed snapshot immutable.')
    env=dict(os.environ,POE_PROJECT_ROOT=str(ROOT),POE_SPRITE_KIT=str(revision/'source'),
             POE_DETAIL_SOURCE=str(revision/'source'),POE_MODEL_OUTPUT=str(destination))
    cmd=['blender','--background','--factory-startup','--python',str(revision/'source/export_models.py'),
         '--',*manifest['families']]
    with (revision/'models.log').open('w') as log:
        run=subprocess.run(cmd,env=env,stdout=log,stderr=subprocess.STDOUT)
    assert run.returncode==0 and (destination/'manifest.json').exists(), 'Model export failed; see models.log'
    exported=json.loads((destination/'manifest.json').read_text())
    assert len(exported)==len(manifest['families'])*3
    manifest['models']={p.name:sha(p) for p in destination.iterdir() if p.is_file()}
    (revision/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    verify(revision)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('command',choices=('build','verify','models','install','proof'))
    ap.add_argument('--revision',required=True)
    ap.add_argument('--families',nargs='+',choices=FAMILIES,default=list(FAMILIES))
    ap.add_argument('--output',type=Path,default=OUTPUT)
    a=ap.parse_args()
    if Path(a.revision).name!=a.revision or a.revision in ('.','..'):
        ap.error('revision must be a single directory name')
    revision=a.output.resolve()/a.revision
    if a.command=='build': build(revision,a.families)
    elif a.command=='verify': verify(revision)
    elif a.command=='install': install(revision)
    elif a.command=='models': models(revision)
    else: sheet(revision,json.loads((revision/'manifest.json').read_text())['families'])


if __name__=='__main__': main()
