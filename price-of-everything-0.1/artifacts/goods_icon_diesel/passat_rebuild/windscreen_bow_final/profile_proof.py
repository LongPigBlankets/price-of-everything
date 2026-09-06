from pathlib import Path
from PIL import Image,ImageDraw
import json,shutil,sys
p=Path(sys.argv[1]);im=Image.open(p/'diesel_car_800.png')
for n in (450,400,256,60):im.resize((n,n),Image.Resampling.LANCZOS).save(p/f'diesel_car_{n}.png')
for name,box in {'front':(28,390,289,633),'rear':(422,91,772,331),'glass':(200,205,652,435),'can':(306,460,467,743)}.items():
 c=im.crop(box);c.resize((c.width*3,c.height*3),Image.Resampling.NEAREST).save(p/(name+'_3x.png'))
shutil.copy2(p/'../source/passat.py',p/'passat.py')
ref=Image.open('/var/folders/d8/48vbgp2s0lx7qzkqj3c7ws580000gn/T/TemporaryItems/NSIRD_screencaptureui_6PzKPF/Screenshot 2026-09-05 at 23.08.09.png').convert('RGB')
m=json.loads((p/'metrics.json').read_text());s=m['profile_scale'];actual=[(325+(y+1.4)/s,710-z/s) for y,z in m['roof_curve']]
overlay=ref.copy();d=ImageDraw.Draw(overlay);d.line(actual,fill=(214,70,37),width=5)
for x,y in m['profile_reference_points']:d.ellipse((x-5,y-5,x+5,y+5),fill=(19,39,73))
d.text((35,40),'Orange: Blender upper body curve   Navy points: sampled reference',fill=(19,39,73));overlay.resize((1061,496),Image.Resampling.LANCZOS).save(p/'profile_overlay.png')
if (p/'side.png').exists():
 side=Image.open(p/'side.png');side=side.crop(side.getbbox());side.thumbnail((950,400),Image.Resampling.LANCZOS)
 canvas=Image.new('RGB',(1000,770),(244,241,234));d=ImageDraw.Draw(canvas)
 photo=ref.crop((0,160,1768,730));photo=photo.resize((950,306),Image.Resampling.LANCZOS);canvas.paste(photo,(25,37))
 d.text((25,15),'Supplied sedan profile',fill=(20,28,60));d.text((25,379),'Blender side view',fill=(20,28,60));canvas.paste(side,((1000-side.width)//2,414),side);canvas.save(p/'profile_comparison.png')
