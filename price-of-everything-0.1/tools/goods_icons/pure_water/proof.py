from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
from scipy import ndimage
import numpy as np,json,sys
root=Path(sys.argv[1]);project=Path.cwd();names=['refined_ree','solar_panel','alloy_ore']
font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial Bold.ttf',20)
paper=(245,241,231);sheet=Image.new('RGB',(1440,1020),paper);d=ImageDraw.Draw(sheet);metrics={}
for i,name in enumerate(names):
    orig=next((project/'assets/icons/goods/medium').glob('*_'+name+'.png'))
    ref=Image.open(orig).convert('RGBA');arr=np.array(ref);rgb=arr[:,:,:3].astype(float)
    mag=(rgb[:,:,0]>rgb[:,:,1]*1.3)&(rgb[:,:,2]>rgb[:,:,1]*1.3)&(rgb[:,:,0]>130)
    if mag.mean()>.1:
        mask=~mag;labels,n=ndimage.label(mask);sizes=np.bincount(labels.ravel());sizes[0]=0
        mask=np.isin(labels,np.where(sizes>2000)[0]);arr[:,:,3]=ndimage.binary_fill_holes(mask)*255;ref=Image.fromarray(arr)
    cur=Image.open(root/(name+'_800.png')).convert('RGBA')
    d.text((i*480+20,10),name.replace('_',' ').title(),font=font,fill=(20,28,60))
    for im,y,title in [(ref,45,'Original'),(cur,485,'Blender')]:
        q=im.crop(im.getbbox());q.thumbnail((430,390),Image.Resampling.LANCZOS)
        sheet.paste(q,(i*480+(480-q.width)//2,y+(400-q.height)//2),q)
        d.text((i*480+20,y+403),title,font=font,fill=(20,28,60))
    for n in [450,256,60]:cur.resize((n,n),Image.Resampling.LANCZOS).save(root/(name+'_'+str(n)+'.png'))
    q=cur.resize((60,60),Image.Resampling.LANCZOS);sheet.paste(q,(i*480+200,935),q)
    aa=np.array(cur);mask=aa[:,:,3]>128;yy,xx=np.where(mask);labs,n=ndimage.label(mask);sizes=np.bincount(labs.ravel());sizes[0]=0
    metrics[name]={'bbox':[int(xx.min()),int(yy.min()),int(xx.max()+1),int(yy.max()+1)],'aspect':float((xx.max()-xx.min()+1)/(yy.max()-yy.min()+1)),'large_alpha_components':int(np.sum(sizes>100))}
    # Four large quadrants at3x show seams, joins, dot density and contacts.
    crop=Image.new('RGB',(2400,2400),paper)
    for k,box in enumerate([(0,0,400,400),(400,0,800,400),(0,400,400,800),(400,400,800,800)]):
        q=cur.crop(box).resize((1200,1200),Image.Resampling.NEAREST);crop.paste(q,((k%2)*1200,(k//2)*1200),q)
    crop.save(root/(name+'_regions_3x.png'))
sheet.save(root/'comparison.png');(root/'pixel_metrics.json').write_text(json.dumps(metrics,indent=2)+'\n');print(json.dumps(metrics))
