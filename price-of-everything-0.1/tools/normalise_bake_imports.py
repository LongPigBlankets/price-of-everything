#!/usr/bin/env python3
"""Make the baked map textures VRAM-compressed (BPTC/S3TC on desktop, ETC2/ASTC where the
export asks for it) instead of the project's Lossless default.

Why: the fabric and road bakes are ~900 tiles of 540x640. Imported Lossless with mipmaps each
one is ~1.8 MB of GPU memory, so a whole-island view holds ~1.5 GB of texture — past the point
where the GL Compatibility driver starts paging every frame (measured: ~185 ms/frame, 5 fps,
at far zoom on a 3600x2260 window; 7 ms with the layer hidden). VRAM compression cuts each
tile to ~0.35 MB and the far view to ~0.3 GB. The plates are flat washes and ink lines, which
BC7 (`high_quality`) reproduces without visible loss.

Run after every bake that adds NEW tiles (existing .import files keep their settings; a new
PNG gets the project default until this is run), then let Godot reimport:

    python3 tools/normalise_bake_imports.py
    <godot> --headless --path . --import

Idempotent: files already normalised are left alone and counted as such.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent / "assets" / "authored_map"
REPLACEMENTS = [
    (re.compile(r"^compress/mode=\d+$", re.M), "compress/mode=2"),
    (re.compile(r"^compress/high_quality=(true|false)$", re.M), "compress/high_quality=true"),
]

def main() -> int:
    changed = 0
    already = 0
    for path in sorted(ROOT.glob("*/*/*.png.import")):
        text = path.read_text()
        new = text
        for pattern, value in REPLACEMENTS:
            new = pattern.sub(value, new)
        if new == text:
            already += 1
            continue
        path.write_text(new)
        changed += 1
    print(f"normalise_bake_imports: {changed} changed, {already} already normalised under {ROOT}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
