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
# The range is joined-then-split so a launcher that passes it as ONE quoted token
# (`-- "0 169"`) still works, and MISSING is a hard error rather than a default.
# Both halves of that are scar tissue from 2026-08-08: three workers launched with
# a quoted range each fell through to the old (0, 89) default and spent twenty
# minutes rendering the same frames on top of each other. `ps` shows a quoted
# "0 169" exactly like two arguments, so nothing looked wrong from outside.
parts = " ".join(argv).split()
if len(parts) < 2:
    raise SystemExit("tools_render_chunk: need a frame range, e.g. `-- 0 169` "
                     "(got %r)" % (argv,))
i0, i1 = int(parts[0]), int(parts[1])
print("CHUNK_RANGE", i0, i1, flush=True)

ns = {}
exec(open(B + "loading_scene.py").read(), ns)
print("CHUNK_BUILD_START", flush=True)
r = ns["render_film_chunk"](i0, i1, rebuild=True)
print("CHUNK_DONE", r, flush=True)
