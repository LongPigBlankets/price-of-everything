"""Export coal/iron-ore studies, reference comparison, and thumbnail checks."""
from pathlib import Path
import sys,json
from PIL import Image,ImageDraw,ImageFont
import numpy as np
from icon_export import export

out=Path(sys.argv[1]).resolve()
project=Path(__file__).resolve().parents[3]
goods=[('coal','g_001'),('iron_ore','g_002')]
font=ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc',23)
small=ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc',17)
sheet=Image.new('RGB',(1000,1090),'#eee9dd'); d=ImageDraw.Draw(sheet)
lineup=Image.new('RGB',(1000,530),'#eee9dd'); ld=ImageDraw.Draw(lineup)
metrics={}
for i,(name,gid) in enumerate(goods):
    export(str(out/('icon_'+name+'_raw.png')),str(out/(name+'_800.png')),800,.010,
           strength=0 if name=='coal' else .42,outline_straps=False)
    im=Image.open(out/(name+'_800.png')).convert('RGBA')
    for size in (450,256,128,64):
        im.resize((size,size),Image.Resampling.LANCZOS).save(out/(name+'_%d.png'%size))
    refpath=project/'artifacts/goods_material_studies/original_icons/medium'/(gid+'_'+name+'.png')
    if not refpath.exists():refpath=project/'assets/icons/goods/medium'/(gid+'_'+name+'.png')
    ref=Image.open(refpath).convert('RGBA')
    a=np.array(ref);key=(a[:,:,0]>150)&(a[:,:,2]>150)&(a[:,:,1]<130)
    a[key,3]=0; ref=Image.fromarray(a);ref=ref.crop(ref.getbbox());ref.thumbnail((414,414))
    d.text((i*500+30,20),'Original / '+name.replace('_',' ').title(),font=font,fill='#141c3c')
    sheet.paste(ref,(i*500+(500-ref.width)//2,60+(414-ref.height)//2),ref)
    d.text((i*500+30,493),'Blender study',font=font,fill='#141c3c')
    pic=im.resize((450,450),Image.Resampling.LANCZOS)
    sheet.paste(pic,(i*500+25,525),pic)
    for j,bg in enumerate(('#eee9dd','#192239')):
        tile=Image.new('RGBA',(92,92),bg); thumb=im.resize((64,64),Image.Resampling.LANCZOS)
        tile.alpha_composite(thumb,(14,14));sheet.paste(tile.convert('RGB'),(i*500+145+j*100,985))
    ld.text((i*500+30,16),name.replace('_',' ').title(),font=font,fill='#141c3c')
    lineup.paste(pic,(i*500+25,65),pic)
    arr=np.array(im);rgb=arr[:,:,:3].astype(float);solid=arr[:,:,3]>240
    ink=np.linalg.norm(rgb-[20,28,60],axis=2)<30
    luma=np.round(rgb[:,:,0]*.2126+rgb[:,:,1]*.7152+rgb[:,:,2]*.0722).astype(int)
    hist=np.bincount(luma[solid&~ink],minlength=256)
    picks=[]
    for p in sorted(range(3,253),key=lambda p:int(hist[p-2:p+3].sum()),reverse=True):
        if all(abs(p-q)>14 for q in picks):picks.append(p)
        if len(picks)==4:break
    metrics[name]={'alpha_bbox':im.getbbox(),'dominant_luma_peaks':picks,
        'pure_black_pixels':int((solid&(rgb.max(axis=2)==0)).sum())}
sheet.save(out/'comparison.png');lineup.save(out/'lineup.png')
(out/'metrics.json').write_text(json.dumps(metrics,indent=2)+'\n')
print(json.dumps(metrics,indent=2))
