"""Package staged furnace sprites, aligned effect masks and the review gallery."""
from pathlib import Path
import json, sys, shutil, hashlib
import numpy as np
from PIL import Image
from furnace_paper import proof

root=Path(sys.argv[1]).resolve()
review=root/'review'; review.mkdir(exist_ok=True)
source=review/'source'; source.mkdir(exist_ok=True)
for name in ('furnace_paper.py','furnace_review.py','package_furnace_review.py','furnace_lift_cutaway.py'):
    shutil.copy2(Path(__file__).with_name(name),source/name)
report=json.loads((root/'geometry-review.json').read_text())
boxes={level:Image.open(root/f'furnace_L{level}.png').getchannel('A').getbbox() for level in (1,2,3)}
manifest=json.loads((root/'manifest.json').read_text())
factor=manifest.get('sprite_scale',788/max(max(b[2]-b[0],b[3]-b[1]) for b in boxes.values()))
validation={}; anchors={}
for level,box in boxes.items():
    w,h=box[2]-box[0],box[3]-box[1]
    nw,nh=round(w*factor),round(h*factor)
    xy=((800-nw)//2,(800-nh)//2)
    sprite=np.array(Image.open(root/f'furnace_lvl{level}.png'))
    anchors[str(level)]={'stacks':[{'x':round(xy[0]+(a['x']-box[0])*nw/w),
        'y':round(xy[1]+(a['y']-box[1])*nh/h),'r':round(a['radius']*factor),'kind':'auto'}
        for a in report[str(level)]['raw_smoke_anchors']]}
    for kind in ('windows','light'):
        a=np.array(Image.open(root/'fx_raw'/f'furnace_lvl{level}_{kind}.png').convert('RGBA')).astype(float)/255
        mask=Image.fromarray(np.round(a[:,:,0]*a[:,:,3]*255).astype('uint8'))
        mask=mask.crop(box).resize((nw,nh),Image.Resampling.LANCZOS)
        alpha=Image.new('L',(800,800));alpha.paste(mask,xy)
        aa=np.array(alpha)
        # Remove near-black render dithering before deriving effect extents.
        aa[aa<8]=0
        alpha=Image.fromarray(aa)
        check={'pixels':int((aa>128).sum()),'outside_sprite_pixels':int(((aa>128)&(sprite[:,:,3]<128)).sum())}
        assert check['pixels']>0 and check['outside_sprite_pixels']==0,check
        assert check['pixels'] < int((sprite[:,:,3]>128).sum())*.02, 'Effect mask leaks onto building materials'
        out=Image.new('RGBA',(800,800),(255,255,255,0));out.putalpha(alpha)
        dest=root/'fx'/kind;dest.mkdir(parents=True,exist_ok=True)
        target=dest/f'furnace_lvl{level}.png';out.save(target)
        check['sha256']=hashlib.sha256(target.read_bytes()).hexdigest()
        validation[f'{level}/{kind}']=check
        if kind=='light':
            # Exact mask bounds; the runtime can draw one masked rectangle per sprite.
            b=alpha.getbbox();anchors[str(level)]['fires']=[dict(x=b[0],y=b[1],w=b[2]-b[0],h=b[3]-b[1],mode='breathe')]
(root/'fx'/'anchors.json').write_text(json.dumps(anchors,indent=2)+'\n')
(review/'mask-validation.json').write_text(json.dumps(validation,indent=2)+'\n')
proof(root,review/'proof.png')
cards=''.join(f'<article><h2>L{l}</h2><img src="../furnace_lvl{l}.png"><div><img class="small" src="../furnace_lvl{l}.png"><a href="../furnace_L{l}.blend">Blender source</a> · <a href="../models/furnace_lvl{l}.glb">GLB</a></div></article>' for l in (1,2,3))
(review/'index.html').write_text('''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Furnace · Paper WPA Catalog</title>
<style>body{font:17px system-ui;background:#ece0c6;color:#1f2b36;margin:32px}h1{font-weight:550}header p{max-width:850px;line-height:1.6}section{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:16px}article{border:1px solid #a79e88;padding:16px}article>img{width:100%;display:block}.small{width:64px;vertical-align:middle;margin-right:15px}a{color:inherit}button{padding:9px 15px;margin:0 8px 20px 0}body.dark article{background:#27313b}body.white article{background:#fff}body.check article{background:repeating-conic-gradient(#d7d7d7 0% 25%,#f7f7f7 0% 50%) 0/24px 24px}footer{margin-top:30px;line-height:1.7}@media(max-width:800px){section{grid-template-columns:1fr}}</style>
<header><h1>Furnace · Paper WPA Catalog</h1><p>L1: compact A-inspired single line. L2: fuller A with handling tower and casting access. L3: B-inspired twin lines with one shared two-bay casting hall and a two-stage lift through the handling tower. Dark metal furnaces, polished steel stoves, brick halls and bright silver pipework distinguish these furnaces from grey decorative buildings. The 14 October factory's fine ink and reduced paper grain are retained.</p><p>Staged alternatives: transparent 800 × 800 sprites, editable Blender scenes, GLBs, and aligned window/heat masks.</p></header>
<nav><button onclick="document.body.className=''">Paper</button><button onclick="document.body.className='dark'">Dark</button><button onclick="document.body.className='white'">White</button><button onclick="document.body.className='check'">Transparency</button></nav><section>'''+cards+'''</section><footer><a href="proof.png">Progression sheet</a> · <a href="../../factory-paper-wpa-reference.png">Actual factory style reference — 14 October</a> · <a href="../geometry-review.json">Geometry checks</a> · <a href="mask-validation.json">Mask checks</a><p>Not installed in the game. Runtime lighting anchors, LOD/depth/picking resources and affected production bakes must be installed and verified together when adopting this set. No normal-play load-time claim is made.</p></footer></html>''')
print('Aligned all six effect masks; zero pixels outside sprite silhouette.')
