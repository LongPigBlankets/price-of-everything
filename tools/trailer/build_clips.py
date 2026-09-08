"""Rebuild independent launch clips from the untouched 21:11 recording.
Pillow renders code-native title/roller graphics; FFmpeg trims recorded gameplay.
Usage: python3 tools/trailer/build_clips.py [gameplay|graphics|growth|finish|all]
"""
from pathlib import Path
import subprocess as sp, json, math, sys, wave, struct, hashlib
from PIL import Image, ImageDraw, ImageFont, ImageFilter
ROOT=Path(__file__).resolve().parents[2]
GAME=ROOT/'price-of-everything-0.1'
OUT=ROOT/'outputs/launch-clips-2026-09-07'
SOURCE=Path('/Users/crisu/Desktop/Screen Recording 2026-09-07 at 21.11.35.mov')
FF='/Users/crisu/.local/bin/ffmpeg'
for d in ['clips','clean','stills','audio','assets','work']: (OUT/d).mkdir(parents=True,exist_ok=True)
FPS=30; W=1920; H=1080
FONT=GAME/'assets/fonts/IBMPlexSans-SemiBold.ttf'
HEAD=GAME/'assets/fonts/BebasNeue-Regular.ttf'
CREAM='#f4e6c0'; GOLD='#e6b34a'; NAVY='#03121d'
def run(args):
    sp.run([FF,'-v','error','-y',*map(str,args)],check=True)
def enc(path): return ['-an','-c:v','libx264','-preset','fast','-crf','17','-pix_fmt','yuv420p','-movflags','+faststart',path]
def crop(rect):
    x,y,w,h=rect
    return f'crop={w}:{h}:{x}:{y},scale=1920:1080:flags=lanczos,setsar=1'
def segment(name,start,length,rect,outlen=None,source=SOURCE):
    outlen=outlen or length
    path=OUT/'work'/f'{name}.mp4'
    run(['-ss',start,'-i',source,'-t',outlen,'-vf',f'{crop(rect)},setpts={outlen/length}*(PTS-STARTPTS),fps=30',*enc(path)])
    return path

def join(paths,path):
    listing=OUT/'work'/'concat.txt'
    listing.write_text(''.join("file '"+str(p).replace("'","'\\''")+"'\n" for p in paths))
    run(['-f','concat','-safe','0','-i',listing,'-c','copy','-movflags','+faststart',path])
def still(sec,source=SOURCE):
    tag=hashlib.sha1(str(source).encode()).hexdigest()[:8]
    path=OUT/'work'/f'source-{tag}-{sec}.png'
    if not path.exists():run(['-ss',sec,'-i',source,'-frames:v','1',path])
    return Image.open(path).convert('RGB')
def thumb(im,box):return im.crop(box).resize((W,H),Image.Resampling.LANCZOS)
def center(d,text,y,font,fill=CREAM,x=960):
    d.text((x,y),text,font=font,fill=fill,anchor='mm')
def font(size,head=False):return ImageFont.truetype(str(HEAD if head else FONT),size)
def frames(name,duration,draw):
    path=OUT/'clean'/f'{name}.mp4'
    proc=sp.Popen([FF,'-v','error','-y','-f','rawvideo','-pixel_format','rgb24','-video_size','1920x1080','-framerate','30','-i','-',*map(str,enc(path))],stdin=sp.PIPE)
    for i in range(round(duration*FPS)):
        im=draw(i/FPS)
        if i in [0,round(duration*FPS/2),round(duration*FPS)-1]:im.save(OUT/'stills'/f'{name}-{i:03d}.jpg',quality=95)
        proc.stdin.write(im.convert('RGB').tobytes())
    proc.stdin.close()
    if proc.wait():raise RuntimeError(name)
    print('rendered',name,flush=True)
    return path

def gameplay():
    selects={
      '05_construction':[('steel',25.3,3,(0,200,2800,1576),1.5),('motor',150.0,3.0,(0,200,2800,1576),2.5)],
      '06_chain_running':[('motor_crane',127,1.5,(0,300,3596,2022),1.5,Path('/Users/crisu/Desktop/Screen Recording 2026-09-07 at 16.38.11.mov')),('chain',200.3,2.1,(0,180,2850,1604),2.5)],
      '11_politics':[('levy',308,1.5,(460,420,2666,1500),1.5),('subsidy',315.0,1.5,(460,420,2666,1500),3)],
      '12b_recorded_pullback':[('map',319,6,(0,160,3596,2022),6)]}
    for name,specs in selects.items():
        join([segment(*s) for s in specs],OUT/'clean'/f'{name}.mp4')
        print('rendered',name,flush=True)
    # Stable chart framing after the panel has stopped scrolling; 24 seconds -> 1.8s.
    decay=segment('decay',274.5,23.4,(460,200,2780,1564),1.8)
    run(['-i',decay,'-vf','tpad=start_mode=clone:start_duration=0.6:stop_mode=clone:stop_duration=0.6',*enc(OUT/'clean/08_price_decay.mp4')])
    sales_frames()

def sales_frames():
    # Fresh windowed game capture: actual market settlement, stable zero/positive rows.
    proof=json.loads((OUT/'sales-frames/settlement.json').read_text())
    assert proof['before_steel_qty']==0 and proof['after_steel_qty']>0
    assert proof['after_revenue']>proof['before_revenue']
    run(['-framerate',FPS,'-i',OUT/'sales-frames/%04d.jpg','-t',3,*enc(OUT/'clean/02_sales.mp4')])
    print('rendered 02_sales',flush=True)

def opening_plate():
    # Short metallic strike: decaying inharmonic partials, with no random noise.
    with wave.open(str(OUT/'audio/metallic_ding.wav'),'wb') as wav:
        wav.setnchannels(1);wav.setsampwidth(2);wav.setframerate(48000)
        samples=[]
        for i in range(26400):
            t=i/48000
            value=sum(a*math.sin(2*math.pi*f*t)*math.exp(-t/d) for a,f,d in [(0.5,1560,.22),(.22,2470,.14),(.14,3920,.08)])
            value*=min(1,t/.0015)*min(1,(.55-t)/.03)
            samples.append(struct.pack('<h',round(value*26000)))
        wav.writeframes(b''.join(samples))
    # The ingot detaches from the original BDP recipe screen.
    source_frame=still(15)
    bdp_crop=(1100,170,2600,1014)
    background=thumb(source_frame,bdp_crop)
    # Exact artwork cut from the recorded recipe, rather than a substitute icon.
    import numpy as np
    ingot=still(15).crop((1888,445,2134,668)).convert('RGBA')
    pixels=np.array(ingot)
    pixels[:,:,3]=np.clip((240-pixels[:,:,0].astype(float))/60,0,1)*255
    # Keep only the connected ingot silhouette; discard the nearby quantity badge.
    mask=Image.fromarray(np.where(pixels[:,:,3]>0,255,0).astype('uint8')).copy()
    ImageDraw.floodfill(mask,(120,110),128)
    pixels[:,:,3]=np.where(np.array(mask)==128,pixels[:,:,3],0)
    ingot=Image.fromarray(pixels)
    bounds=ingot.getbbox()
    # Remove only the original silhouette, preserving the recipe and quantity badge.
    erase=ingot.getchannel('A').point(lambda p:255 if p else 0).filter(ImageFilter.MaxFilter(5))
    source_without=source_frame.copy()
    source_without.paste(Image.new('RGB',ingot.size,source_frame.getpixel((1890,447))),(1888,445),erase)
    background_without=thumb(source_without,bdp_crop)
    ingot=ingot.crop(bounds)
    ingot.save(OUT/'assets/recipe_iron_ingot.png')
    start_x=(1888+(bounds[0]+bounds[2])/2-bdp_crop[0])*W/(bdp_crop[2]-bdp_crop[0])
    start_y=(445+(bounds[1]+bounds[3])/2-bdp_crop[1])*H/(bdp_crop[3]-bdp_crop[1])
    ingot=ingot.resize((round(ingot.width*W/(bdp_crop[2]-bdp_crop[0])),round(ingot.height*H/(bdp_crop[3]-bdp_crop[1]))),Image.Resampling.LANCZOS)
    face=font(112,True);prefix='TEST YOUR';text_y=952
    layout=ImageDraw.Draw(background)
    pb=layout.textbbox((0,0),prefix,font=face)
    mb=layout.textbbox((0,0),'METTLE',font=face)
    pw=pb[2]-pb[0];mw=mb[2]-mb[0];gap=26
    impact_x=(W-pw-gap-mw)/2+pw+gap+mw/2
    icon_height=ingot.height
    impact_y=text_y-(mb[3]-mb[1])/2-icon_height/2+3
    def opening(t):
        im=(background if t<1 else background_without).copy()
        plate(im,(320,864,1280,176))
        d=ImageDraw.Draw(im)
        word='METTLE' if t<1.6 else 'METAL'
        wb=d.textbbox((0,0),word,font=face)
        ww=wb[2]-wb[0];left=(W-pw-gap-ww)/2
        d.text((left-pb[0],text_y-(pb[1]+pb[3])/2),prefix,font=face,fill=CREAM)
        shake=round(4*math.sin((t-1.6)*90)*max(0,1-(t-1.6)/.18)) if 1.6<=t<1.78 else 0
        d.text((left+pw+gap-wb[0],text_y-(wb[1]+wb[3])/2+shake),word,font=face,fill=GOLD)
        if 1.0<=t<2.65:
            if t<1.6:
                u=(t-1.0)/.6
                x=start_x+(impact_x-start_x)*u
                y=start_y+(impact_y-start_y)*u*u
                angle=0
            else:
                u=(t-1.6)/1.05
                x=impact_x+1100*u;y=impact_y-550*u+950*u*u
                angle=-250*u
            icon=ingot.rotate(angle,resample=Image.Resampling.BICUBIC,expand=True)
            im.paste(icon,(round(x-icon.width/2),round(y-icon.height/2)),icon)
        return im
    frames('01_test_your_metal',3.4,opening)

def upgrades():
    # Actual recorded supply-chain states, reframed around each subject.
    specs=[('FURNACE',1,85,(1125,1040),.86),('FURNACE',2,94,(1125,1040),.86),
           ('FURNACE',3,100,(1435,1075),.77),('FACTORY',1,223,(1440,970),.58),
           ('FACTORY',2,237,(1530,500),1.0),('FACTORY',3,250,(1550,500),1.0)]
    shots=[]
    for title,level,sec,subject,scale in specs:
        raw=still(sec);im=Image.new('RGB',(W,H),raw.getpixel((500,200)))
        region=raw.crop((0,220,2580,2190))
        region=region.resize((round(region.width*scale),round(region.height*scale)),Image.Resampling.LANCZOS)
        placement=(round(960-subject[0]*scale),round(490-(subject[1]-220)*scale))
        mask=Image.new('L',region.size,255);md=ImageDraw.Draw(mask)
        for x in range(60):
            if placement[0]>0:md.line((x,0,x,region.height),fill=round(255*x/60))
            if placement[0]+region.width<W:md.line((region.width-1-x,0,region.width-1-x,region.height),fill=round(255*x/60))
        im.paste(region,placement,mask)
        plate(im,(680,20,560,110))
        d=ImageDraw.Draw(im);label=f'{title}   /   L{level}';face=font(59,True);box=d.textbbox((0,0),label,font=face)
        d.text((960-(box[0]+box[2])/2,75-(box[1]+box[3])/2),label,font=face,fill=CREAM)
        im.save(OUT/'stills'/f'upgrade-recorded-{title.lower()}-L{level}.jpg',quality=95)
        shots.append(im)
    frames('07a_furnace_levels',3,lambda t:shots[min(2,int(t))].copy())
    frames('07b_factory_levels',3,lambda t:shots[3+min(2,int(t))].copy())
    frames('07_furnace_factory_upgrades',6,lambda t:shots[min(5,int(t))].copy())


def specialties():
    # The original wide graph pan leads into four real focused game captures.
    old=Path('/Users/crisu/Desktop/Screen Recording 2026-09-07 at 16.38.11.mov')
    wide=segment('specialty_wide',50.2,2.0,(0,160,3596,2022),2.0,old)
    raw=sp.check_output([FF,'-v','error','-i',str(wide),'-f','rawvideo','-pix_fmt','rgb24','-'])
    wide_frames=[Image.frombytes('RGB',(W,H),raw[i*W*H*3:(i+1)*W*H*3]) for i in range(60)]
    focused=[Image.open(OUT/'specialty-stills'/f'{g}.png').convert('RGB') for g in ['silica','hydraulic_components','plastics','iron_ingots']]
    def draw(t):
        im=(wide_frames[min(59,int(t*30))] if t<2 else focused[min(3,int((t-2)/.5))]).copy()
        plate(im,(475,35,970,145));d=ImageDraw.Draw(im);label='PICK YOUR SPECIALTY';face=font(83,True);box=d.textbbox((0,0),label,font=face)
        d.text((960-(box[0]+box[2])/2,107-(box[1]+box[3])/2),label,font=face,fill=CREAM)
        return im
    frames('00_pick_your_specialty',4,draw)

# Faithful enlarged port of PhaseRoller._draw/_blit in scripts/end_turn_dock.gd.
def roller(t):
    w,h=660,190
    body=Image.new('RGB',(w,h));d=ImageDraw.Draw(body)
    top=(219,219,207);mid=(252,252,242);bot=(153,153,140)
    for y in range(h):
        f=y/(h-1); a,b,u=(top,mid,f*2) if f<.5 else (mid,bot,(f-.5)*2)
        d.line((0,y,w,y),fill=tuple(round(a[j]+(b[j]-a[j])*u) for j in range(3)))
    words=['Buy','Power','Sell','Unlock','Upgrade','Make']
    if t<1:idx,e=0,1
    elif t>=2:idx,e=5,1
    else:
        idx=min(5,1+int((t-1)/.2));q=((t-1)% .2)/.2;e=1-(1-q)**3
    for word,offset in [(words[idx],(1-e)*h),(words[max(0,idx-1)],-e*h)]:
        if idx==0 and offset<0:continue
        d.text((w/2,h/2+offset-2),word,font=font(92),fill='#051933',anchor='mm')
    d.rectangle((0,0,w-1,h-1),outline='#6b6b63',width=3)
    return body

def plate(im,box):
    x,y,w,h=box;cut=35
    def pts(pad=0):
        a,b=x+pad,y+pad;c,e=x+w-pad,y+h-pad
        return [(a+cut,b),(c-cut,b),(c,b+cut),(c,e-cut),(c-cut,e),(a+cut,e),(a,e-cut),(a,b+cut)]
    d=ImageDraw.Draw(im);d.polygon([(a+8,b+12)for a,b in pts()],fill='#01070d')
    mask=Image.new('L',im.size);ImageDraw.Draw(mask).polygon(pts(),fill=255)
    fill=Image.new('RGB',im.size);fd=ImageDraw.Draw(fill)
    for j in range(h):
        q=j/max(1,h-1);col=tuple(int(a+(b-a)*q)for a,b in zip((30,78,116),(1,14,29)))
        fd.line((x,y+j,x+w,y+j),fill=col)
    im.paste(fill,(0,0),mask);d=ImageDraw.Draw(im)
    d.line(pts()+[pts()[0]],fill=CREAM,width=3,joint='curve')
    p=pts(7);d.line(p[:3],fill='#718c9e',width=2);d.line(p[3:7],fill='#00101e',width=3)

def diagram(im,t):
    d=ImageDraw.Draw(im)
    active=t>=2
    # Actual motor recipe: steel and copper wiring inputs. No invented quantities.
    edge=GOLD if active else '#657070'
    d.line([(700,575),(900,575),(900,680),(1150,680)],fill=edge,width=6)
    d.line([(700,805),(900,805),(900,680)],fill=edge,width=6)
    d.polygon([(1130,668),(1150,680),(1130,692)],fill=edge)
    for name,key,x,y,hi in [('Steel','g_006_steel',250,500,active),('Copper wiring','g_007_copper_wiring',250,730,active),('Motor','g_008_motor',1150,600,True)]:
        d.rounded_rectangle((x,y,x+460,y+155),radius=10,fill='#0c2031',outline=GOLD if hi else '#657070',width=4)
        d.rounded_rectangle((x+10,y+10,x+145,y+145),radius=6,fill=CREAM)
        icon=Image.open(GAME/f'assets/icons/goods/alternate_icons/medium/{key}.png').convert('RGBA');icon.thumbnail((125,125))
        im.paste(icon,(x+15+(125-icon.width)//2,y+15+(125-icon.height)//2),icon)
        d.text((x+165,y+76),name,font=font(31),fill=CREAM,anchor='lm')
    if active:
        q=((t-2)*.8)%1
        for yy in [575,805]:
            # Incoming flow on both input branches.
            xx=710+180*q;d.ellipse((xx-8,yy-8,xx+8,yy+8),fill=CREAM)

def graphics():
    base=Image.new('RGB',(W,H),NAVY)
    def buy(t):
        im=base.copy();plate(im,(410,125,1100,285));im.paste(roller(t),(485,174))
        ImageDraw.Draw(im).text((1290,267),'it',font=font(100),fill=CREAM,anchor='mm')
        diagram(im,t);return im
    frames('04_buy_make_roller',4,buy)
    opening_plate()
    for name,text,duration in [('09_dont_stand_still',"DON’T STAND STILL.",3),('10_world_changes','THE WORLD CHANGES AROUND YOU.',2.5)]:
        def textplate(t,text=text):
            im=base.copy();plate(im,(165,380,1590,320));d=ImageDraw.Draw(im);center(d,text,505 if text.startswith('DON') else 540,font(91,True))
            if text.startswith('DON'):center(d,'THE MARKET WAITS FOR NO ONE.',605,font(54,True))
            return im
        frames(name,duration,textplate)
    logo=Image.open(GAME/'assets/ui/title_logo.png').convert('RGBA');logo.thumbnail((1350,540))
    def end(t):
        im=base.copy();im.paste(logo,((W-logo.width)//2,130),logo)
        d=ImageDraw.Draw(im);center(d,'PLAY THE FREE DEMO',765,font(82,True),GOLD)
        center(d,'carbonandcapital.itch.io/carbon-and-capital',880,font(38))
        return im
    frames('13_demo_end_plate',4,end)

def growth():
    raw=OUT/'growth-frames'
    run(['-framerate','30','-i',raw/'%04d.jpg','-vf','scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,setsar=1',*enc(OUT/'clean/12a_growth_37s.mp4')])
    run(['-i',OUT/'clean/12a_growth_37s.mp4','-vf','setpts=0.243243243*(PTS-STARTPTS),fps=30','-t','9',*enc(OUT/'clean/12_growth_9s.mp4')])

def finish():
    names=['00_pick_your_specialty','01_test_your_metal','02_sales','04_buy_make_roller','05_construction','06_chain_running','07_furnace_factory_upgrades','09_dont_stand_still','08_price_decay','10_world_changes','11_politics','12_growth_9s','13_demo_end_plate']
    durations=[4,3.4,3,4,4,4,6,3,3,2.5,4.5,9,4]
    effects={
      '01_test_your_metal':[('metallic_ding.wav',1.60,.55,.7)],
      '02_sales':[('slot_lever.wav',.05,1.3,.18),('cash_register.wav',1.5,1.17,.6)],
      '04_buy_make_roller':[('slide_into_slot.wav',1,1.63,.4)],
      '05_construction':[('click_primary.wav',.933,.16,.24),('hammer.wav',1.133,1.27,.18),('click_primary.wav',2.8,.16,.24),('hammer.wav',3.0,1.27,.18)],
      '07_furnace_factory_upgrades':[('tech_unlock.wav',at,2.34,.24) for at in [1,2,4,5]]}
    timeline=[];cursor=0
    for n,duration in zip(names,durations):
        source=OUT/'clean'/f'{n}.mp4'
        if not source.exists():raise FileNotFoundError(source)
        cues=effects.get(n,[])
        stem_duration=max([duration]+[at+length for _,at,length,_ in cues])
        args=['-f','lavfi','-i',f'anullsrc=r=48000:cl=stereo:d={stem_duration}']
        filters=[];mix=['[0:a]']
        for j,(sfx,at,length,volume) in enumerate(cues):
            args+=['-i',OUT/'audio'/sfx if sfx=='metallic_ding.wav' else GAME/'assets/audio/ui_sounds'/sfx]
            # Retain natural tails instead of chopping every effect to 0.65 seconds.
            filters.append(f'[{j+1}:a]atrim=duration={length},asetpts=PTS-STARTPTS,volume={volume},afade=t=out:st={max(0,length-.05)}:d=0.05,adelay={round(at*1000)}|{round(at*1000)}[s{j}]')
            mix.append(f'[s{j}]')
        filters.append(''.join(mix)+f'amix=inputs={len(mix)}:normalize=0,atrim=duration={stem_duration}[a]')
        stem=OUT/'audio'/f'{n}_effects.wav'
        run([*args,'-filter_complex',';'.join(filters),'-map','[a]','-ar','48000','-ac','2',stem])
        # Review clips hold the final frame long enough for their sound to ring out.
        run(['-i',source,'-i',stem,'-vf',f'tpad=stop_mode=clone:stop_duration={max(0,stem_duration-duration)}','-map','0:v','-map','1:a','-c:v','libx264','-preset','fast','-crf','17','-pix_fmt','yuv420p','-c:a','aac','-b:a','192k','-t',stem_duration,'-movflags','+faststart',OUT/'clips'/f'{n}.mp4'])
        run(['-ss',min(duration*.5,2.5),'-i',source,'-frames:v','1',OUT/'stills'/f'{n}.jpg'])
        timeline.append({'clip':n,'start':cursor,'duration':duration,'effects_review_duration':stem_duration,'sfx':cues})
        cursor+=duration
    # Mix each complete effects stem onto the timeline; tails can cross picture cuts.
    args=[];filters=[];links=[]
    for i,item in enumerate(timeline):
        args+=['-i',OUT/'audio'/f"{item['clip']}_effects.wav"]
        delay=round(item['start']*1000)
        filters.append(f'[{i}:a]adelay={delay}|{delay}[a{i}]');links.append(f'[a{i}]')
    filters.append(''.join(links)+f'amix=inputs={len(links)}:normalize=0,apad,atrim=duration={cursor}[a]')
    run([*args,'-filter_complex',';'.join(filters),'-map','[a]','-ar','48000','-ac','2',OUT/'audio/effects_mix.wav'])
    # Only sales and construction duck the music. The other cues play over it unchanged.
    # One broad envelope per scene prevents repeated pumping between adjacent effects.
    windows=[]
    for item in timeline:
        if item['clip']=='02_sales':windows.append((item['start']+.05,item['start']+2.67))
        if item['clip']=='05_construction':windows.append((item['start']+.933,item['start']+4.27))
    vol='0.24'
    for a,b in windows:
        attack=.4;release=.9
        envelope=f'if(lt(t,{a-attack}),1,if(lt(t,{a}),1-0.8*(0.5-0.5*cos(PI*(t-{a-attack})/{attack})),if(lt(t,{b}),0.2,if(lt(t,{b+release}),0.2+0.8*(0.5-0.5*cos(PI*(t-{b})/{release})),1))))'
        vol=f'({vol})*({envelope})'
    run(['-i',GAME/'assets/audio/music/big_band_jazz.ogg','-t',cursor,'-af',f"volume='{vol}':eval=frame,afade=t=in:d=0.25,afade=t=out:st={cursor-.8}:d=0.8",'-ar','48000','-ac','2',OUT/'audio/music_ducked.wav'])
    seqargs=[];seqfilters=[];links=[]
    for i,(n,duration) in enumerate(zip(names,durations)):
        seqargs+=['-i',OUT/'clean'/f'{n}.mp4']
        seqfilters.append(f'[{i}:v]fps=30,trim=duration={duration},setpts=PTS-STARTPTS[v{i}]');links.append(f'[v{i}]')
    seqfilters.append(''.join(links)+f'concat=n={len(names)}:v=1:a=0[v]')
    run([*seqargs,'-filter_complex',';'.join(seqfilters),'-map','[v]','-t',cursor,*enc(OUT/'work/sequence_picture.mp4')])
    run(['-i',OUT/'work/sequence_picture.mp4','-i',OUT/'audio/effects_mix.wav','-i',OUT/'audio/music_ducked.wav','-filter_complex','[1:a][2:a]amix=inputs=2:normalize=0,alimiter=limit=0.97:level=false:latency=true[a]','-map','0:v','-map','[a]','-c:v','copy','-c:a','aac','-b:a','256k','-t',cursor,'-movflags','+faststart',OUT/'sequence_preview.mp4'])
    manifest={'revision':7,'audio_revision':{'construction_gain_relative_to_revision_5':.4,'sales_turn_change_gain_relative_to_revision_5':.4,'cash_register_unchanged':True},'removed_clips':['03_goods_graph'],'sales_capture':json.loads((OUT/'sales-frames/settlement.json').read_text()),'end_holds':{'opener_after_exit_max_seconds':1,'price_after_motion_seconds':.6},'opener':{'background':'Original BDP recipe screen, recording at 15s, crop 1100/170/2600/1014','plate':'lower BDP, y864–1040, centered text','ingot':'Exact recipe artwork from recording at 15s; leaves its BDP recipe diagram, strikes text at 1.6s, arcs off-screen','additional_static_recipe_shot':False},'source':str(SOURCE),'fps':30,'size':[W,H],'timeline':timeline,'specialty_intro':{'wide_pan_source':'16:38:11 recording, 50.2–52.2s','focused_sources':'New in-game captures, specialty-stills/','order':['silica','hydraulic_components','plastics','iron_ingots'],'seconds_per_good':.5},'upgrade_source_seconds':[85,94,100,223,237,250],'upgrades':'Recorded supply-chain view; no replacement background or sprites','price_decay_seconds':1.8,'music_ducking':{'scenes':['02_sales','05_construction'],'attack':.4,'release':.9,'floor':.2,'no_ducking_for':['ding','buy_make','upgrades']},'effects_tails':'Full per-clip WAV stems; carry over picture cuts in the sequence','construction_sound_delay_seconds':.2}
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2))
    cards=''.join(f'<article><h2>{n[:2]}. {n[3:].replace("_"," ")}</h2><video controls preload="none" poster="stills/{n}.jpg?v=7" src="clips/{n}.mp4?v=7"></video><p>{d:g}s picture · <a href="clean/{n}.mp4?v=7">Clean picture</a> · <a href="clips/{n}.mp4?v=7">With full effects tail</a> · <a href="audio/{n}_effects.wav?v=7">Effects WAV</a></p></article>'for n,d in zip(names,durations))
    (OUT/'index.html').write_text('<!doctype html><meta charset="utf-8"><title>Carbon and Capital · clip review</title><style>body{margin:0;background:#071722;color:#f4e6c0;font:17px system-ui;padding:40px;max-width:1500px;margin:auto}h1{font-size:36px}h2{font-size:20px;font-weight:500}a{color:#e6b34a}main{display:grid;grid-template-columns:1fr 1fr;gap:28px}video{width:100%;background:#020b12}article{background:#102735;padding:20px;border:1px solid #476071;border-radius:12px}p{line-height:1.6}.hero{max-width:1000px;margin-bottom:40px}@media(max-width:800px){main{grid-template-columns:1fr}}</style><h1>Carbon and Capital</h1><p>Revision 7 · 1920 × 1080 · 30 fps · Construction and sales turn-change effects reduced by 60% from their original levels.</p><div class="hero"><h2>54.4-second sequence preview</h2><video controls preload="none" src="sequence_preview.mp4?v=7"></video><p>Individual effects versions hold their final frame for the sound tail. The sequence carries those tails across the next picture cut.</p></div><main>'+cards+'</main><p><a href="clean/07a_furnace_levels.mp4?v=7">Furnace levels separately</a> · <a href="clean/07b_factory_levels.mp4?v=7">Factory levels separately</a> · <a href="clean/12a_growth_37s.mp4">Full growth take</a></p><p><a href="audio/music_ducked.wav?v=7">Music stem</a> · <a href="audio/effects_mix.wav?v=7">Effects stem</a> · <a href="manifest.json?v=7">Timing manifest</a></p>')
    print('finished',cursor,'seconds',flush=True)

if __name__=='__main__':
    mode=sys.argv[1] if len(sys.argv)>1 else 'all'
    for name,fn in [('gameplay',gameplay),('graphics',graphics),('opening',opening_plate),('sales',sales_frames),('upgrades',upgrades),('specialties',specialties),('growth',growth),('finish',finish)]:
        if mode==name or (mode=='all' and name not in ['graph','opening','sales']):fn()
