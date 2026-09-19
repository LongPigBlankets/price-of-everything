"""Decode and verify the September trailer and its independently editable clips."""
from pathlib import Path
import hashlib
import json
import re
import subprocess as sp
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'outputs/trailer-2026-09-10'
FF = '/Users/crisu/.local/bin/ffmpeg'
manifest = json.loads((OUT / 'manifest.json').read_text())
final = OUT / 'Carbon and Capital - September Demo Trailer.mp4'
ids = [s['id'] for s in manifest['timeline']]
assert '08_market_chart' not in ids and '09_construction_eta' not in ids
assert ids[ids.index('12_stay_ahead') + 1] == '07_ore_impact'
assert ids[ids.index('07_ore_impact') + 1] == '07b_factory_shipments'
assert next(s for s in manifest['timeline'] if s['id']=='07b_factory_shipments')['duration_s']==2.5

def decode(path, seconds):
    info = sp.run([FF, '-hide_banner', '-i', str(path)], capture_output=True, text=True).stderr
    assert '1920x1080' in info and '60 fps' in info, (path, info)
    result = sp.run([FF, '-v', 'error', '-nostdin', '-i', str(path), '-progress', 'pipe:1',
                     '-nostats', '-f', 'null', '-'], capture_output=True, text=True, check=True)
    assert not result.stderr.strip(), result.stderr
    frames = int(re.findall(r'^frame=(\d+)$', result.stdout, re.M)[-1])
    assert frames == round(seconds * 60), (path.name, frames, seconds)
    print('DECODED', path.name, frames, flush=True)
    return {'file':str(path.relative_to(OUT)), 'frames':frames, 'decode_errors':0,
            'width':1920, 'height':1080, 'fps':60}

results = [decode(final, manifest['duration_s'])]
for shot in manifest['timeline']:
    results.append(decode(OUT / shot['review'], shot['duration_s']))

def pcm(path):
    data = sp.check_output([FF, '-v', 'error', '-ss', '5', '-i', str(path), '-t', '20',
                            '-ar', '48000', '-ac', '2', '-f', 'f32le', '-'])
    return np.frombuffer(data, dtype='<f4').astype(np.float64)

reference = pcm(manifest['music']['source'])
mixed = pcm(OUT / 'audio/music.wav')
assert reference.shape == mixed.shape
gain = float(np.dot(reference, mixed) / np.dot(reference, reference))
assert abs(gain - .15) < .00001, gain
peak = float(np.max(np.abs(mixed)))
assert peak < 1

effects = np.frombuffer(sp.check_output([FF, '-v', 'error', '-i', str(OUT / 'audio/effects.wav'),
    '-ar', '48000', '-ac', '2', '-f', 'f32le', '-']), dtype='<f4').reshape(-1, 2)
active = np.flatnonzero(np.max(np.abs(effects), axis=1) > .00001)
assert active.size
ding_start = float(active[0] / 48000)
assert abs(ding_start - manifest['effects']['impact_s']) < .02
mixed_audio = np.frombuffer(sp.check_output([FF, '-v', 'error', '-i', str(final), '-vn',
    '-ar', '48000', '-ac', '2', '-f', 'f32le', '-']), dtype='<f4')
final_peak = float(np.max(np.abs(mixed_audio)))
assert final_peak < 1
approach = json.loads((OUT / 'capture/approach_evidence.json').read_text())
assert abs(approach['end_zoom'] - approach['max_zoom']) < .00001
hydraulics = json.loads((OUT / 'capture/hydraulic_evidence.json').read_text())
assert hydraulics['level'] == 3 and hydraulics['instance']['level'] == 3
assert hydraulics['instance']['recipe_id'] == 'r_236'
assert hydraulics['recipe']['display_name'] == 'Hydraulics Manufacturing'
assert hydraulics['bay'] and hydraulics['frames'] == 98

times = [round(s['start_s']+s['duration_s']*.6,3) for s in manifest['timeline']]
times.append(round(manifest['duration_s']-.4,3))
sheet = Image.new('RGB', (1600, 960), (12, 20, 36))
for i, t in enumerate(times):
    path = OUT / 'work' / f'assembled-{t}.jpg'
    sp.run([FF, '-v', 'error', '-y', '-ss', str(t), '-i', str(final), '-frames:v', '1',
            '-vf', 'scale=400:225', str(path)], check=True)
    im = Image.open(path)
    x, y = i % 4 * 400, i // 4 * 240
    sheet.paste(im, (x, y))
    ImageDraw.Draw(sheet).text((x + 5, y + 226), f'{t:g}s', fill='white')
sheet.save(OUT / 'work/assembled-review.jpg', quality=95)

(OUT / 'verification.json').write_text(json.dumps({
    'sha256':hashlib.sha256(final.read_bytes()).hexdigest(),
    'file_size_bytes':final.stat().st_size,
    'decode_checks':results,
    'music_measured_gain':gain, 'music_sample_peak':peak,
    'ding_onset_s':ding_start, 'final_audio_peak':final_peak,
    'maximum_zoom_verified':approach['max_zoom'],
    'hydraulics_verified':{'level':hydraulics['level'],'recipe':hydraulics['instance']['recipe_id'],
        'native_lorry_bay':bool(hydraulics['bay']),'animation_speed':hydraulics['animation_speed']},
    'visual_review_sheet':'work/assembled-review.jpg',
    'godot_logs':['parse.log', 'unit.log', 'e2e.log', 'capture.log']
}, indent=2))
print('MEDIA VERIFIED', flush=True)
