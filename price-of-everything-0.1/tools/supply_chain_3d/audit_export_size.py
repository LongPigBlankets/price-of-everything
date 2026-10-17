#!/usr/bin/env python3
"""Inventory a Godot v2/v3 PCK, including imported assets' original folders.

Read-only. The directory format follows Godot's core/io/file_access_pack.cpp.
This measures shipped data, not the source tree or editor import cache.
"""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import re
import struct


def inventory(path):
    with path.open('rb') as stream:
        def read(fmt):
            size = struct.calcsize(fmt)
            return struct.unpack(fmt, stream.read(size))

        magic, version, major, minor, patch, flags = read('<6I')
        if magic != 0x43504447 or version not in (2, 3) or flags & 1:
            raise ValueError('Expected an unencrypted Godot v2/v3 PCK')
        read('<Q')  # file base; directory inventory does not read payloads
        if version == 3:
            stream.seek(read('<Q')[0])
        else:
            stream.read(64)
        count, = read('<I')
        files = []
        for _ in range(count):
            length, = read('<I')
            name = stream.read(length).rstrip(b'\0').decode('utf-8')
            _, size = read('<QQ')
            md5 = stream.read(16).hex()
            file_flags, = read('<I')
            files.append(dict(path=name, bytes=size, md5=md5, flags=file_flags))
    return dict(total_bytes=path.stat().st_size, files=files,
                engine=f'{major}.{minor}.{patch}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pack', type=Path)
    parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--compare', type=Path, help='Previous inventory JSON')
    args = parser.parse_args()
    result = inventory(args.pack)
    sources = {}
    for file in args.project.rglob('*.import'):
        if '.godot' in file.parts:
            continue
        origin = str(file.relative_to(args.project))[:-7]
        for imported in re.findall(r'"res://(\.godot/imported/[^"\n]+)"', file.read_text()):
            sources[imported] = origin
    groups = defaultdict(int)
    for item in result['files']:
        source = sources.get(item['path'], item['path'])
        item['source'] = source
        groups['/'.join(source.split('/')[:3])] += item['bytes']
    result['groups'] = dict(sorted(groups.items(), key=lambda entry: -entry[1]))
    if args.compare:
        before = json.loads(args.compare.read_text())
        old = {item['path']: item for item in before['files']}
        new = {item['path']: item for item in result['files']}
        result['comparison'] = dict(
            saved_bytes=before['total_bytes'] - result['total_bytes'],
            removed=[old[p] for p in sorted(old.keys() - new.keys())],
            added=[new[p] for p in sorted(new.keys() - old.keys())],
            changed=[p for p in sorted(old.keys() & new.keys()) if old[p]['md5'] != new[p]['md5']],
        )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(dict(total_bytes=result['total_bytes'], files=len(result['files']),
                          largest_groups=dict(list(result['groups'].items())[:12])), indent=2))


if __name__ == '__main__':
    main()
