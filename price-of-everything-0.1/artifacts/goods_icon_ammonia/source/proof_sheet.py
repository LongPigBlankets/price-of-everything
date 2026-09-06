from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import numpy as np,json
root=Path(__file__).resolve().parents[1]
refs=root.parents[1]/'assets/icons/goods/medium'
font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',16)
small=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',13)
items=[('Chlorine',refs/'g_012_chlorine.png'),('Sodium hydroxide',refs/'g_013_sodium_hydroxide.png'),('Industrial acids',refs/'g_065_industrial_acids.png'),('Ammonia - original',refs/'g_025_ammonia.png'),('Ammonia - Blender',root/'v3/ammonia_800.png')]
canvas=Image.new('RGB',(1050,650),'#efeee8'); d=ImageDraw.Draw(canvas)
d.text((20,14),'CHEMICAL GOODS  /  ammonia silhouette and label review',font=font,fill='#141e3c')
metrics={}
for i,(label,path) in enumerate(items):
 im=Image.open(path).convert('RGBA'); im=im.crop(im.getbbox()); metrics[label]={'bbox_aspect':round(im.width/im.height,3)}
 def tile(size):
  t=im.copy(); t.thumbnail((round(size*.92),round(size*.92)),Image.Resampling.LANCZOS)
  square=Image.new('RGBA',(size,size)); square.alpha_composite(t,((size-t.width)//2,(size-t.height)//2)); return square
 x=i*210
 d.text((x+12,52),label,font=small,fill='#141e3c')
 t=tile(195);canvas.paste(t,(x+7,78),t)
 t=tile(60); canvas.paste(t,(x+75,314),t)
 d.text((x+65,385),'60 x 60 px',font=small,fill='#141e3c')
 # Exact 60px PNG, not a separate re-render.
 if i==4:
  full=Image.open(path)
  for n in (60,256,450):full.resize((n,n),Image.Resampling.LANCZOS).save(root/'v3'/f'ammonia_{n}.png')
 t=tile(60); dark=Image.new('RGBA',(90,90),'#252d3d');dark.alpha_composite(t,(15,15));canvas.paste(dark,(x+60,430))
 d.text((x+51,533),'dark background',font=small,fill='#141e3c')
 t=tile(60).convert('LA').convert('RGBA');canvas.paste(t,(x+75,572),t)
canvas.save(root/'comparison.png')
# Four candidate detail crops, explicit 3x nearest.
a=Image.open(root/'v3/ammonia_800.png')
sheet=Image.new('RGB',(1200,680),'#efeee8');dr=ImageDraw.Draw(sheet)
for k,(name,b) in enumerate([('Silver valve',(300,30,490,205)),('Yellow shoulder',(390,190,580,365)),('White label / NH3',(285,440,475,615)),('Foot and lower body',(200,590,390,765))]):
 t=a.crop(b).resize((570,525),Image.Resampling.NEAREST)
 # arrange in a single horizontal strip scaled sheet dimensions below
 if k==0: sheet=Image.new('RGB',(2280,560),'#efeee8');dr=ImageDraw.Draw(sheet)
 sheet.paste(t,(k*570,30),t);dr.text((k*570+12,5),name+' / 3x',font=font,fill='#141e3c')
sheet.save(root/'detail_crops_3x.png')
(root/'reference_metrics.json').write_text(json.dumps(metrics,indent=2))
