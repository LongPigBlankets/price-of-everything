"""Export transparent game-size studies and a labelled visual comparison sheet."""
import sys,json
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import numpy as np
from icon_export import export

out=Path(sys.argv[1]).resolve()
project=Path(__file__).resolve().parents[3]
names=['limestone','electrical_components','ethylene']
ids=['g_016','g_036','g_024']
font=ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc',23)
small=ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc',16)
sheet=Image.new('RGB',(1200,1030),'#eee9dd'); d=ImageDraw.Draw(sheet)
d.text((28,22),'GOODS / EDITABLE BLENDER STUDIES',font=font,fill='#141c3c')
d.text((28,60),'Existing reference above · model render below · 64 px check at foot',font=small,fill='#545a65')
metrics={}
for i,(name,gid) in enumerate(zip(names,ids)):
    dst=out/(name+'_800.png')
    # These three goods have no packing straps; grey cable shadows must stay un-outlined.
    export(str(out/('icon_'+name+'_raw.png')),str(dst),800,.010,outline_straps=False)
    im=Image.open(dst).convert('RGBA')
    for size in (450,256,128,64):
        im.resize((size,size),Image.Resampling.LANCZOS).save(out/(name+'_%d.png'%size))
    ref=Image.open(project/'assets/icons/goods/medium'/(gid+'_'+name+'.png')).convert('RGBA')
    a=np.array(ref); key=(a[:,:,0]>180)&(a[:,:,2]>170)&(a[:,:,1]<130)
    a[key,3]=0; ref=Image.fromarray(a); ref=ref.crop(ref.getbbox()); ref.thumbnail((320,320))
    sheet.paste(ref,(i*400+(400-ref.width)//2,110+(320-ref.height)//2),ref)
    d.text((i*400+25,450),name.replace('_',' ').title(),font=font,fill='#141c3c')
    pic=im.resize((390,390),Image.Resampling.LANCZOS)
    sheet.paste(pic,(i*400+5,485),pic)
    for j,bg in enumerate(('#eee9dd','#192239')):
        tile=Image.new('RGBA',(100,100),bg); thumb=im.resize((64,64),Image.Resampling.LANCZOS)
        tile.alpha_composite(thumb,(18,18)); sheet.paste(tile.convert('RGB'),(i*400+95+j*105,905))
    arr=np.array(im); opaque=arr[:,:,3]>240; rgb=arr[:,:,:3].astype(float)
    ink=opaque & (np.linalg.norm(rgb-[20,28,60],axis=2)<30)
    lum=np.round(rgb[:,:,0]*.2126+rgb[:,:,1]*.7152+rgb[:,:,2]*.0722).astype(int)
    hist=np.bincount(lum[opaque&~ink],minlength=256)
    peaks=sorted(range(3,253),key=lambda p:int(hist[p-2:p+3].sum()),reverse=True)
    picked=[]
    for p in peaks:
        if all(abs(p-q)>15 for q in picked): picked.append(p)
        if len(picked)==3: break
    metrics[name]={'alpha_bbox':im.getbbox(),'ink_pixels':int(ink.sum()),
        'pure_black_pixels':int((opaque&(rgb.max(axis=2)==0)).sum()),'dominant_luma_peaks':picked}
sheet.save(out/'comparison.png')
lineup=Image.new('RGB',(1200,465),'#eee9dd'); ld=ImageDraw.Draw(lineup)
for i,name in enumerate(names):
    ld.text((i*400+24,16),name.replace('_',' ').title(),font=font,fill='#141c3c')
    pic=Image.open(out/(name+'_800.png')).resize((400,400),Image.Resampling.LANCZOS)
    lineup.paste(pic,(i*400,55),pic)
lineup.save(out/'lineup.png')
(out/'metrics.json').write_text(json.dumps(metrics,indent=2)+'\n')
print(json.dumps(metrics,indent=2))
