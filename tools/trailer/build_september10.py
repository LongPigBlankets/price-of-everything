"""September trailer. Real recordings + isolated native UI captures.
Independent picture masters have 0.75s outgoing handles; manifest carries edit slots.
Run: python3 tools/trailer/build_september10.py [picture|finish|all]
"""
from pathlib import Path
import json, math, subprocess as sp, sys, hashlib, html
from PIL import Image, ImageDraw, ImageFont
from build_clips import plate as approved_plate, font as approved_font

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'outputs/trailer-2026-09-10'
CAP = OUT / 'capture'
OLD = ROOT / 'outputs/launch-clips-2026-09-07'
FF = '/Users/crisu/.local/bin/ffmpeg'
FONT = '/System/Library/Fonts/Supplemental/Iowan Old Style.ttc'
A = Path('/Users/crisu/Desktop/Screen Recording 2026-09-10 at 19.38.45.mov')
B = Path('/Users/crisu/Desktop/Screen Recording 2026-09-10 at 19.40.33.mov')
C = Path('/Users/crisu/Desktop/Screen Recording 2026-09-10 at 20.41.32.mov')
MUSIC = ROOT / 'price-of-everything-0.1/assets/audio/music/big_band_jazz.ogg'
W,H,FPS = 1920,1080,60
DISSOLVE = .75
INK = (244,230,192)
NAVY = (3,18,29)
ONLY = tuple(sys.argv[2].split(',')) if len(sys.argv)>2 else ()

def wanted(name):return not ONLY or name.startswith(ONLY)
# Timing is explicit: start times are the start of each incoming dissolve.
SHOTS = [
 ('01_stoneshore',5,'Stoneshore approach — maximum zoom'),
 ('02_power',3,'Power plant smoke'),
 ('03_eaf',2.5,'Electric arc furnace'),
 ('04_assembly',2.5,'Assembly robot arms'),
 ('05_buy_make',3,'Buy / Make roller'),
 ('06_inputs_market',3,'Inputs and market sales'),
 ('12_stay_ahead',2.5,'Stay one step ahead of the market'),
 ('07_ore_impact',2,'Ore buying raises prices'),
 ('07b_factory_shipments',2.5,'L3 hydraulics factory — lorry delivery'),
 ('09_map_management',5,'Stoneshore — build and manage the tile'),
 ('10_research_pick',2,'Free research unlock'),
 ('11_goods_focus',3,'Electric car supply chain — larger cards, actual unlock state'),
 ('13_mettle',3.4,'Test your mettle → metal — original falling ingot'),
 ('13b_empire_growth',9,'Original empire growth and zoom-out'),
 ('14_demo',4,'Original demo end card'),
]
TOTAL = round(sum(s[1] for s in SHOTS), 3)
for d in ['clean','clips','stills','audio','assets','work']:(OUT/d).mkdir(parents=True,exist_ok=True)

def run(args):
    sp.run([FF,'-v','error','-nostdin','-y',*map(str,args)],check=True)

def enc(path,audio=False):
    return (['-c:a','aac','-b:a','256k'] if audio else ['-an'])+['-c:v','libx264','-threads','4','-preset','fast','-crf','17',
            '-pix_fmt','yuv420p','-video_track_timescale','15360','-movflags','+faststart',path]

def face(size=65):return approved_font(size,True)

def center(draw,text,x,y,size=65,fill=INK):
    f=face(size); bb=draw.textbbox((0,0),text,font=f)
    draw.text((x-(bb[0]+bb[2])/2,y-(bb[1]+bb[3])/2),text,font=f,fill=fill)

def plate(im,text=None,box=(200,785,1520,160)):
    approved_plate(im,box)
    x,y,w,h=box
    if text:center(ImageDraw.Draw(im),text.upper(),x+w/2,y+h/2,91)

def roller(im,t):
    plate(im,box=(430,125,1060,170))
    rw,rh=630,110
    wheel=Image.new('RGB',(rw,rh)); d=ImageDraw.Draw(wheel)
    for y in range(rh):
        v=y/(rh-1);lum=round(247-64*(abs(v-.43)/.57)**1.7)
        d.line((0,y,rw,y),fill=(lum,lum,max(0,lum-10)))
    words=['Buy','Power','Sell','Unlock','Upgrade','Make']
    if t<1:idx,e=0,1
    elif t>=2:idx,e=5,1
    else:
        idx=min(5,1+int((t-1)/.2));q=((t-1)%.2)/.2;e=1-(1-q)**3
    center(d,words[idx],rw/2,rh/2+(1-e)*rh,fill=NAVY)
    if idx>0 and e<1:center(d,words[idx-1],rw/2,rh/2-e*rh,fill=NAVY)
    d.rectangle((0,0,rw-1,rh-1),outline=(129,139,143),width=2)
    im.paste(wheel,(585,155));center(ImageDraw.Draw(im),'it',1302,210)

def duration(name):
    i=next(i for i,s in enumerate(SHOTS) if s[0]==name)
    return SHOTS[i][1]+(DISSOLVE if i<len(SHOTS)-1 else 0)

def video(name,source,start,source_length,rect=(0,0,3596,2022)):
    if not wanted(name):return
    length=duration(name);x,y,w,h=rect
    run(['-ss',start,'-i',source,'-vf',
         f'trim=duration={source_length},setpts={length/source_length}*(PTS-STARTPTS),'
         f'crop={w}:{h}:{x}:{y},scale={W}:{H}:flags=lanczos,fps={FPS},setsar=1',
         '-t',length,*enc(OUT/'clean'/f'{name}.mp4')])
    (OUT/'work'/f'{name}-source.json').write_text(json.dumps({
        'recording':str(source),'source_start_s':start,'source_duration_s':source_length,
        'crop_xywh':rect,'retimed_duration_s':length},indent=2))
    print('PICTURE',name,flush=True)

def render(name,draw):
    if not wanted(name):return
    length=duration(name)
    proc=sp.Popen([FF,'-v','error','-y','-f','rawvideo','-pix_fmt','rgb24',
                   '-s',f'{W}x{H}','-r',str(FPS),'-i','-',*map(str,enc(OUT/'clean'/f'{name}.mp4'))],stdin=sp.PIPE)
    for i in range(round(length*FPS)):
        im=draw(i/FPS)
        if i==round(SHOTS[next(j for j,s in enumerate(SHOTS) if s[0]==name)][1]*FPS/2):
            im.save(OUT/'stills'/f'{name}.jpg',quality=95)
        proc.stdin.write(im.convert('RGB').tobytes())
    proc.stdin.close()
    if proc.wait():raise RuntimeError(name)
    print('PICTURE',name,flush=True)

def over_video(name,callback):
    if not wanted(name):return
    src=OUT/'work'/f'{name}-background.mp4'
    (OUT/'clean'/f'{name}.mp4').replace(src)
    dec=sp.Popen([FF,'-v','error','-i',str(src),'-f','rawvideo','-pix_fmt','rgb24','-'],stdout=sp.PIPE)
    last=None
    def draw(t):
        nonlocal last
        data=dec.stdout.read(W*H*3)
        if len(data)==W*H*3:last=Image.frombytes('RGB',(W,H),data)
        if last is None:raise RuntimeError('No background frames')
        im=last.copy();callback(im,t);return im
    render(name,draw)
    dec.stdout.close();dec.wait()

def crop_image(im,rect):return im.crop(rect).resize((W,H),Image.Resampling.LANCZOS)

def push(im,t,length,amount=.025):
    z=1+amount*min(1,t/length);ww=W/z;hh=H/z
    return im.transform((W,H),Image.Transform.EXTENT,((W-ww)/2,(H-hh)/2,(W+ww)/2,(H+hh)/2),Image.Resampling.BICUBIC)

def reuse(name,old_name,source_duration):
    if not wanted(name):return
    source=OLD/'clean'/f'{old_name}.mp4'
    run(['-i',source,'-vf',f'fps={FPS},tpad=stop_mode=clone:stop_duration=0.75',
         '-t',duration(name),*enc(OUT/'clean'/f'{name}.mp4')])
    (OUT/'work'/f'{name}-source.json').write_text(json.dumps({
        'approved_master':str(source),'source_start_s':0,'source_duration_s':source_duration,
        'presentation':'Original picture retained; 30 fps duplicated to 60 fps; outgoing handle padded if needed.'},indent=2))
    print('REUSED',name,flush=True)

def map_management():
    name='09_map_management'
    if not wanted(name):return
    # Keep both the build panel and the tile-management panel in view.
    takes=[(3.1,2.9,1.0),(17.8,4.9,1.5),(23.0,6.6,2.25),(32.0,2.5,1.0)]
    pieces=[]
    for i,(start,source_length,length) in enumerate(takes):
        path=OUT/'work'/f'map-management-{i}.mp4'
        run(['-ss',start,'-i',C,'-vf',
             f'trim=duration={source_length},setpts={length/source_length}*(PTS-STARTPTS),'
             f'crop=3596:2022:0:0,scale={W}:{H}:flags=lanczos,fps={FPS},setsar=1',
             '-t',length,*enc(path)])
        pieces.append(path)
    listing=OUT/'work/map-management.txt'
    listing.write_text(''.join("file '"+str(p).replace("'","'\\''")+"'\n" for p in pieces))
    run(['-f','concat','-safe',0,'-i',listing,'-c','copy','-movflags','+faststart',OUT/'clean'/f'{name}.mp4'])
    (OUT/'work'/f'{name}-source.json').write_text(json.dumps({
        'recording':str(C),'cuts':[{'source_start_s':a,'source_duration_s':b,'output_duration_s':c}
                                   for a,b,c in takes],'crop_xywh':[0,0,3596,2022]},indent=2))
    print('PICTURE',name,flush=True)

def pictures():
    if wanted('01_stoneshore'):
        run(['-framerate',30,'-i',CAP/'approach_%03d.png','-vf',f'fps={FPS}',
             '-t',duration('01_stoneshore'),*enc(OUT/'clean/01_stoneshore.mp4')])
        (OUT/'work/01_stoneshore-source.json').write_text(json.dumps({
            'type':'Native maximum-zoom capture','frames':'capture/approach_000..172.png',
            'evidence':'capture/approach_evidence.json'},indent=2))
    video('02_power',B,91.0,3.75)
    video('03_eaf',B,30.7,3.25)
    video('04_assembly',B,24.5,3.25,(0,170,3596,2022))
    reuse('05_buy_make','04_buy_make_roller',4)
    video('06_inputs_market',B,131.6,3.75)

    markets=[Image.open(CAP/f'market_{i:02d}.png').convert('RGB') for i in range(16)]
    def market_at(t,start,move,rect):
        k=min(15,max(0,int((t-start)/move*16)))
        return crop_image(markets[k],rect)
    # Wide enough to preserve threshold headings and the actual price line.
    render('07_ore_impact',lambda t:market_at(t,0,2,(40,0,1880,1035)))
    if wanted('07b_factory_shipments'):
        run(['-framerate',30,'-i',CAP/'hydraulic_%03d.png','-vf',f'fps={FPS}',
             '-t',duration('07b_factory_shipments'),*enc(OUT/'clean/07b_factory_shipments.mp4')])
        (OUT/'work/07b_factory_shipments-source.json').write_text(json.dumps({
            'type':'Native staged L3 hydraulics factory and lorry animation',
            'frames':'capture/hydraulic_000..097.png','evidence':'capture/hydraulic_evidence.json',
            'animation_speed':3.2},indent=2))
    map_management()

    rb=Image.open(CAP/'research_before.png').convert('RGB')
    ra=Image.open(CAP/'research_after.png').convert('RGB')
    def pick(t):
        im=(rb if t<1.15 else ra).copy()
        # Cursor marks the actual panel hit-test position used by the capture.
        x,y=940,545;d=ImageDraw.Draw(im)
        if .75<t<1.65:
            if t<1.15:r=14
            else:r=14+round((t-1.15)*75)
            d.ellipse((x-r,y-r,x+r,y+r),outline=(250,226,158),width=3)
        return im
    render('10_research_pick',pick)
    focused=Image.open(CAP/'graph_unlocked.png').convert('RGB')
    # Hold the native framing so the enlarged cards at the left edge stay intact.
    render('11_goods_focus',lambda t:focused.copy())
    settled=crop_image(markets[0],(40,0,1880,1035))
    def ahead(t):
        im=push(settled,t,2.5,.035);plate(im,'Stay one step ahead of the market');return im
    render('12_stay_ahead',ahead)
    reuse('13_mettle','01_test_your_metal',3.4)
    reuse('13b_empire_growth','12_growth_9s',9)
    reuse('14_demo','13_demo_end_plate',4)

def finish():
    # Reuse unchanged encoded segments only when the archived prior cut proves the
    # timeline and every unselected master are identical. Adjacent dissolves rebuild.
    selective=False
    if ONLY and (OUT/'manifest.json').exists():
        previous=json.loads((OUT/'manifest.json').read_text())
        archive=OUT/f'revision-{previous.get("revision",0)}'
        same_order=[(s['id'],s['duration_s']) for s in previous['timeline']]==[(n,d) for n,d,_ in SHOTS]
        def identical(name):
            a=OUT/'clean'/f'{name}.mp4';b=archive/'clean'/f'{name}.mp4'
            return a.exists() and b.exists() and hashlib.sha256(a.read_bytes()).digest()==hashlib.sha256(b.read_bytes()).digest()
        selective=same_order and all(wanted(n) or identical(n) for n,_,_ in SHOTS)
    def redo(name):return not selective or wanted(name)
    pieces=[];timeline=[];at=0.
    for i,(name,slot,label) in enumerate(SHOTS):
        path=OUT/'clean'/f'{name}.mp4'
        if i:
            prev,pdur,_=SHOTS[i-1]
            transition=OUT/'work'/f'transition-{i:02d}.mp4'
            if redo(name) or redo(prev) or not transition.exists():run(['-ss',pdur,'-t',DISSOLVE,'-i',OUT/'clean'/f'{prev}.mp4',
                 '-t',DISSOLVE,'-i',path,'-filter_complex_threads',1,'-filter_complex',
                 f'[0:v]setpts=PTS-STARTPTS,settb=AVTB[a];[1:v]setpts=PTS-STARTPTS,settb=AVTB[b];'
                 f'[a][b]blend=all_expr=A*(1-T/{DISSOLVE})+B*T/{DISSOLVE},format=yuv420p[v]',
                 '-map','[v]','-t',DISSOLVE,*enc(transition)])
            pieces.append(transition)
        normal=OUT/'work'/f'body-{i:02d}.mp4';skip=DISSOLVE if i else 0
        if redo(name) or not normal.exists():run(['-ss',skip,'-i',path,'-t',slot-skip,*enc(normal)])
        pieces.append(normal)
        # A clean per-shot review clip is trimmed to the editorial slot, not the handle.
        audio_args=['-i',OLD/'audio/01_test_your_metal_effects.wav','-map','0:v','-map','1:a'] if name=='13_mettle' else []
        if redo(name) or not (OUT/'clips'/f'{name}.mp4').exists():
            run(['-i',path,*audio_args,'-t',slot,*enc(OUT/'clips'/f'{name}.mp4',audio=bool(audio_args))])
            run(['-ss',slot/2,'-i',path,'-frames:v',1,OUT/'stills'/f'{name}.jpg'])
        timeline.append({'id':name,'label':label,'start_s':at,'duration_s':slot,'master_duration_s':duration(name),
                         'incoming_dissolve_s':DISSOLVE if i else 0,'picture':f'clean/{name}.mp4','review':f'clips/{name}.mp4'})
        source=OUT/'work'/f'{name}-source.json'
        if source.exists():timeline[-1]['source']=json.loads(source.read_text())
        else:
            timeline[-1]['source']={'type':'native staged capture','evidence':'capture/evidence.json',
                'frames':{'07_ore_impact':'market_00..15.png',
                    '10_research_pick':'research_before.png, research_after.png',
                    '11_goods_focus':'graph_unlocked.png','12_stay_ahead':'market_00.png'}.get(name,'see builder')}
            if name in ('10_research_pick','11_goods_focus'):
                timeline[-1]['source']['evidence']='capture/research_evidence.json'
        at+=slot;print('ASSEMBLED',name,flush=True)
    assert abs(at-TOTAL)<.001
    listing=OUT/'work/assembly.txt'
    listing.write_text(''.join("file '"+str(p).replace("'","'\\''")+"'\n" for p in pieces))
    run(['-f','concat','-safe',0,'-i',listing,'-c','copy','-movflags','+faststart',OUT/'picture_master.mp4'])
    run(['-i',MUSIC,'-t',TOTAL,'-af',f'volume=0.15,afade=t=in:st=0:d=0.3,afade=t=out:st={TOTAL-.8}:d=0.8',
         '-ar',48000,'-ac',2,'-c:a','pcm_s24le',OUT/'audio/music.wav'])
    ding_start=next(s['start_s'] for s in timeline if s['id']=='13_mettle')
    run(['-i',OLD/'audio/01_test_your_metal_effects.wav','-af',
         f'adelay={round(ding_start*1000)}|{round(ding_start*1000)},apad,atrim=duration={TOTAL}',
         '-ar',48000,'-ac',2,'-c:a','pcm_s24le',OUT/'audio/effects.wav'])
    run(['-i',OUT/'picture_master.mp4','-i',OUT/'audio/music.wav','-i',OUT/'audio/effects.wav',
         '-filter_complex','[1:a][2:a]amix=inputs=2:normalize=0[a]','-map','0:v','-map','[a]',
         '-c:v','copy','-c:a','aac','-b:a','256k','-t',TOTAL,'-movflags','+faststart',OUT/'Carbon and Capital - September Demo Trailer.mp4'])
    manifest={'revision':4,'duration_s':TOTAL,'width':W,'height':H,'fps':FPS,'dissolve_s':DISSOLVE,
              'font':{'headings':'Bebas Neue','roller_and_body':'IBM Plex Sans Semibold','heading_size_px':91},
              'plate_style':'Original bevelled octagon, blue gradient, cream outline and gold accents',
              'effects':{'source':str(OLD/'audio/01_test_your_metal_effects.wav'),'clip_start_s':ding_start,'impact_s':ding_start+1.6,'music_ducking':False},
              'plate_rgb':NAVY,'music':{'source':str(MUSIC),'gain':.15},'timeline':timeline,
              'recordings':[str(B),str(C)],'capture_evidence':'capture/evidence.json',
              'research_evidence':'capture/research_evidence.json',
              'hydraulic_delivery_evidence':'capture/hydraulic_evidence.json',
              'removed_clips':['08_market_chart','09_construction_eta'],
              'notes':['Original falling-ingot ding restored over unchanged 0.15 music; separate WAV stems.',
                       'One price-growth shot remains, immediately after the market plate.',
                       'The 2.5-second factory shot uses native L3 Hydraulics Manufacturing and the lorry bay animation at 3.2x speed.',
                       'Newly captured graph uses larger cards and the current native unlocked state.',
                       'The construction ETA shot is replaced by building and managing Stoneshore in the latest recording.',
                       'Market and construction are staged through native game APIs; source captures retained.',
                       'Each clean master includes an outgoing 0.75-second handle except the last.']}
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2))
    (OUT/'README.md').write_text(f'''# September demo trailer

Revision 4: {TOTAL:g} seconds, 1920×1080, 60 fps. Earlier reviews are archived in `revision-1/` through `revision-3/`.

- `clips/`: fifteen separate review clips, trimmed to their slots; the ingot clip includes its ding.
- `clean/`: picture masters with a 0.75-second outgoing dissolve handle (except the final shot).
- `audio/music.wav`: separate 48 kHz stereo music stem, gain 0.15, with opening/closing fades.
- `audio/effects.wav`: original ingot ding placed at its new timeline position, with no music ducking.
- `capture/`: original native screenshots and simulation evidence; market history is accelerated.
- `manifest.json`: ordered timeline, source selections, typography and production settings.
- `index.html`: final trailer and individual clip review gallery.

Rebuild from the repository root with `python3 tools/trailer/build_september10.py all`.
To revise selected pictures, use `python3 tools/trailer/build_september10.py picture 07,08`,
then `python3 tools/trailer/build_september10.py finish` to rebuild the assembly and gallery.
Use `finish 07b` after a single-clip revision to rebuild its body and adjacent dissolves;
reuse is allowed only if unselected masters match the archived prior cut byte for byte.
Source recordings must remain at the paths in the manifest.
The original approved clips in `outputs/launch-clips-2026-09-07/` supply the roller,
falling ingot, empire growth and end card. The original bevelled octagon renderer supplies
the remaining heading. Colours, logo, icons and original fonts are retained.

Supplemental shots use `tools/trailer_growth.tscn -- --launch-20260910` from the Godot project.
The capture uses an isolated session and does not save a match. Its native price chart is
enlarged for legibility; purchases, price changes, construction deliveries and the research
grant come from game APIs. One price-growth shot follows the market plate. The focused
graph now uses the game's larger cards and native unlock state. Add `--research-only`
to recapture research and the graph without rerunning the map or market captures.
Add `--approach` to capture the native maximum-zoom Stoneshore approach separately.
Add `--hydraulic-delivery` to capture the L3 factory's native lorry/crate bay animation.
Its animation phase is accelerated 3.2x to fit the 2.5-second shot; the recipe is r_236.
The port arrival follows the native ship timetable, with its clock chosen for the shot.
Run `python3 tools/trailer/verify_september10.py` to decode and check the finished media.
''')
    cards=''.join(f'<article><h3>{s["start_s"]:g}s · {html.escape(s["label"])}</h3>'
                  f'<video controls preload="none" poster="stills/{s["id"]}.jpg?v=4" src="{s["review"]}?v=4"></video></article>' for s in timeline)
    (OUT/'index.html').write_text(f'''<!doctype html><html><meta charset="utf-8"><title>Carbon and Capital · September trailer</title>
<style>body{{margin:40px auto;max-width:1200px;padding:0 24px;background:#0c1424;color:#e8eef7;font:18px system-ui}}h1{{font-family:Georgia}}video{{width:100%;background:#000}}section{{display:grid;grid-template-columns:1fr 1fr;gap:24px}}h3{{font-size:16px}}a{{color:#ffe7af}}</style>
<h1>Carbon and Capital</h1><p>Revision 4 · {TOTAL:g} seconds · 1080p60 · September demo trailer</p>
<video controls preload="metadata" src="Carbon%20and%20Capital%20-%20September%20Demo%20Trailer.mp4?v=4"></video>
<p><a href="manifest.json">Timeline and provenance</a> · Music gain 0.15 · 0.75-second dissolves</p><section>{cards}</section></html>''')
    print('TRAILER COMPLETE',flush=True)

if __name__=='__main__':
    mode=sys.argv[1] if len(sys.argv)>1 else 'all'
    if mode in ('picture','all'):pictures()
    if mode in ('finish','all'):finish()
