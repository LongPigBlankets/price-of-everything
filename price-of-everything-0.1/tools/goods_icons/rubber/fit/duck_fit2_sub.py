"""duck_fit2 over a subset of keys: python3 duck_fit2_sub.py <init.json> <rounds> <out> <key,key,...>"""
import json, sys
import numpy as np
import duck_fit2 as f
from best_powell import best_powell
D = json.load(open(sys.argv[1])); rounds = int(sys.argv[2]); out = sys.argv[3]; keys = sys.argv[4].split(',')
lo = np.array([f.LO[k] for k in keys]); hi = np.array([f.HI[k] for k in keys])
def unpack(x):
    Q = dict(D); Q.update({k: float(v) for k, v in zip(keys, np.clip(x, lo, hi))}); return Q
print('start', f.score(D, True), flush=True)
x0, _ = best_powell(lambda x: -f.score(unpack(x)), np.clip([D[k] for k in keys], lo, hi), lo, hi, rounds, log=lambda m: print(m, flush=True))
D = unpack(x0); s, det = f.score(D, True)
json.dump(D, open(out + '.json', 'w'), indent=1); f.view(D, out + '.png')
print('final %.4f' % s, det); print({k: round(D[k], 4) for k in keys})
