"""Render one film chunk HEADLESSLY.

    blender --background <file>.blend --python tools_render_chunk.py -- I0 I1

Headless is the right way to run these (learned 2026-08-07): the GUI path put the
loop on Blender's main thread, which also serves the MCP socket — so a running
chunk blocked every status call AND could not be told to stop. Headless has none
of that, survives the GUI being closed, and can be killed like any process.
The scene is rebuilt from code each run, so nothing depends on saved .blend state.
"""
import bpy
import sys
import os
import mathutils

B = "/Users/crisu/Price of Everything/blender-assets/"
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
i0, i1 = (int(argv[0]), int(argv[1])) if len(argv) >= 2 else (0, 89)

ns = {}
exec(open(B + "loading_scene.py").read(), ns)
print("CHUNK_BUILD_START", flush=True)
r = ns["render_film_chunk"](i0, i1, rebuild=True)
print("CHUNK_DONE", r, flush=True)
