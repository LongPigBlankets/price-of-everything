from PIL import Image,ImageDraw
from pathlib import Path
import numpy as np,json
R=Path('price-of-everything-0.1/artifacts/goods_icon_ammonia'); O=R/'review_v4'; ims={v:Image.open(R/v/'ammonia_800.png').convert('RGBA') for v in ['v3','v4']}
bg=(245,241,229);sheet=Image.new('RGB',(480,270),bg);d=ImageDraw.Draw(sheet)
for j,(v,im) in enumerate(ims.items()):
 sm=im.resize((60,60),Image.Resampling.LANCZOS);sheet.paste(sm,(j*240+90,25),sm); big=sm.resize((180,180),Image.Resampling.NEAREST);sheet.paste(big,(j*240+30,90),big);d.text((j*240+95,5),v,fill=(20,28,60))
sheet.save(O/'v3_v4_60px.png')
regions=[('valve',(300,30,490,210),(335,30,475,210)),('shoulder',(200,155,590,375),(265,165,530,330)),('label',(220,440,590,610),(280,420,520,585)),('body shadow',(425,610,585,680),(420,595,520,685)),('foot',(330,680,600,765),(330,685,535,765))]
for i,(n,b3,b4) in enumerate(regions):
 aa=ims['v3'].crop(b3);bb=ims['v4'].crop(b4);w=(aa.width+bb.width)*3+30;h=max(aa.height,bb.height)*3+25;out=Image.new('RGB',(w,h),bg);dd=ImageDraw.Draw(out);dd.text((5,5),n+' : v3 / v4 (3x pixels)',fill=(20,28,60));aa=aa.resize((aa.width*3,aa.height*3),Image.Resampling.NEAREST);bb=bb.resize((bb.width*3,bb.height*3),Image.Resampling.NEAREST);out.paste(aa,(0,25),aa);out.paste(bb,(aa.width+30,25),bb);out.save(O/f'crop_{i+1}_{n.replace(" ","_")}.png')
met={}
for v,im in ims.items():
 a=np.array(im);rgb=a[:,:,:3].astype(float);l=rgb[:,:,0]*.2126+rgb[:,:,1]*.7152+rgb[:,:,2]*.0722;o=a[:,:,3]>245;ink=np.linalg.norm(rgb-[20,28,60],axis=2)<30;yy=o&(rgb[:,:,0]>120)&(rgb[:,:,1]>100)&(rgb[:,:,2]<rgb[:,:,1]*.6);bb=im.getbbox();met[v]={'bbox':bb,'bbox_aspect_height_width':(bb[3]-bb[1])/(bb[2]-bb[0]),'yellow_pct_opaque':100*yy.sum()/o.sum(),'pure_black':int(((rgb.max(2)==0)&o).sum())}
(O/'metrics.json').write_text(json.dumps(met,indent=2));print(json.dumps(met,indent=2))
