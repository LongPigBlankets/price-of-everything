"""Transparent sprite adaptation of the 14 October Paper WPA Catalog print pass.

The sibling paper_wpa_catalog.py comes from claude/sc3d-colour; colour matrix
contractions use einsum to avoid a local Accelerate/BLAS floating-point warning.
Use its ink/paper mapping and reduced grain strengths, but keep sprite alpha:
the game's paper supplies the background. No border, shadow or shifted alpha.
"""
import importlib.util
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi


EXPORT_SCALE=788/688  # Keep the approved v11 pixel scale when L3's footprint changes.


def export(revision, levels=(1,2,3)):
    revision=Path(revision)
    for level in levels:
        raw=Image.open(revision/f'furnace_L{level}.png').convert('RGBA')
        box=raw.getchannel('A').getbbox()
        w,h=box[2]-box[0],box[3]-box[1]
        size=(round(w*EXPORT_SCALE),round(h*EXPORT_SCALE))
        assert max(size)<=788, 'Furnace exceeds established sprite scale'
        xy=((800-size[0])//2,(800-size[1])//2)
        for suffix in ('','_mask'):
            source=Image.open(revision/f'furnace_L{level}{suffix}.png').convert('RGBA')
            out=Image.new('RGBA',(800,800),(0,0,0,0))
            out.alpha_composite(source.crop(box).resize(size,Image.Resampling.LANCZOS),xy)
            out.save(revision/f'furnace_lvl{level}{suffix}.png')


def finish(path, mask_path):
    spec = importlib.util.spec_from_file_location('furnace_catalog',Path(__file__).with_name('paper_wpa_catalog.py'))
    paper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(paper)
    rgba = np.array(Image.open(path).convert('RGBA'))
    mask = np.array(Image.open(mask_path).convert('RGBA'))
    h,w = rgba.shape[:2]
    rgb = rgba[:,:,:3].astype(float)/255
    # The same normal-derived face separation used by the existing sprite rig.
    # Apply before paper mapping, so texture is a property of the final print.
    rgb *= (.66+.34*mask[:,:,0]/255)[...,None]
    ink = paper.printed(rgb)
    rng = np.random.default_rng(14)
    def noise(sigma):
        n=ndi.gaussian_filter(rng.standard_normal((h,w)),sigma)
        return n/max(n.std(),1e-8)
    fibre,tooth,grain=noise((.8,3.5)),noise(1.2),noise(.7)
    luma=np.sum(ink*np.array([.2126,.7152,.0722]),axis=-1)
    ink *= (1+paper.INK_FIBRE*fibre[...,None])
    ink += (paper.INK_GRAIN*grain*4*luma*(1-luma))[...,None]
    ink *= 1+paper.TOOTH*tooth[...,None]
    assert np.isfinite(ink).all(), 'Non-finite paper colour'
    rgba[:,:,:3]=(np.clip(ink,0,1)*255).astype('uint8')
    rgba[rgba[:,:,3]==0,:3]=0
    Image.fromarray(rgba).save(path)


def proof(revision, destination=None):
    canvas=Image.new('RGB',(1800,860),'#ece0c6')
    d=ImageDraw.Draw(canvas)
    font='/System/Library/Fonts/Supplemental/Arial.ttf'
    title=ImageFont.truetype(font,30); small=ImageFont.truetype(font,19)
    d.text((40,26),'FURNACE  /  PAPER WPA CATALOG',fill='#1f2b36',font=title)
    descriptions=['L1  ·  Compact single line','L2  ·  Full single-furnace works','L3  ·  Twin-furnace works']
    for i in range(3):
        im=Image.open(Path(revision)/f'furnace_lvl{i+1}.png').convert('RGBA')
        x=i*600
        full=im.resize((590,590),Image.Resampling.LANCZOS)
        canvas.paste(full,(x+5,105),full)
        d.text((x+40,83),descriptions[i],font=small,fill='#1f2b36')
        for size,tx in ((64,40),(128,135)):
            thumb=im.resize((size,size),Image.Resampling.LANCZOS)
            canvas.paste(thumb,(x+tx,660),thumb)
    d.text((290,817),'Shared scale · dark metal furnaces · brick halls · bright silver · fine ink',fill='#394b54',font=small)
    canvas.save(destination or Path(revision)/'proof.png')
