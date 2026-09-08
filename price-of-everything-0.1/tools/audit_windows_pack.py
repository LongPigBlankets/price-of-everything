#!/usr/bin/env python3
"""Audit a Godot 4.6 PCK v3: python3 tools/audit_windows_pack.py game.pck manifest.json.
Maps imported texture bytes back to source assets for useful size attribution.
"""
import struct,json,collections,re,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
remap={}
for p in root.rglob('*.import'):
 if '.godot' in p.parts: continue
 for path in re.findall(r'res://(\.godot/imported/[^"\]]+)',p.read_text(errors='ignore')): remap[path]=str(p.relative_to(root))[:-7]
items=[]
with open(sys.argv[1],'rb') as f:
 header=f.read(8)
 if header != b'GDPC\x03\x00\x00\x00': raise ValueError('Expected an unencrypted Godot PCK v3')
 f.seek(32);directory=struct.unpack('<Q',f.read(8))[0];f.seek(directory);count=struct.unpack('<I',f.read(4))[0]
 for _ in range(count):
  n=struct.unpack('<I',f.read(4))[0];path=f.read(n).rstrip(b'\0').decode();offset,size=struct.unpack('<QQ',f.read(16));f.read(20)
  source=remap.get(path,path);parts=source.split('/');group='/'.join(parts[:2]) if len(parts)>1 else '[root screenshots/resources]'
  items.append(dict(path=path,source=source,size=size,group=group))
groups=collections.Counter()
for i in items: groups[i['group']]+=i['size']
print('files',len(items),'MiB',round(sum(x['size'] for x in items)/2**20,1))
for k,v in groups.most_common(20):print(round(v/2**20,2),k)
Path(sys.argv[2]).write_text(json.dumps(items,indent=2))
