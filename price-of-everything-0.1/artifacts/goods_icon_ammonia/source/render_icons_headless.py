"""Headless goods-icon render. No MCP, no saved .blend state.

    /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
        --python render_icons_headless.py -- <out_dir> motor aluminium diesel_car

Each name maps to build_<name>() in goods_icon_kit.py; output is <out_dir>/icon_<name>_raw.png
plus the _mask.png shading pass. Then run icon_export.py on each.
"""
import sys, os, traceback

here = os.path.dirname(os.path.abspath(__file__))
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out_dir, names = argv[0], argv[1:]
os.makedirs(out_dir, exist_ok=True)

exec(open(os.path.join(here, "sprite_kit.py")).read())
exec(open(os.path.join(here, "goods_icon_kit.py")).read())

for nm in names:
    fn = globals().get("build_" + nm)
    if fn is None:
        print("NO BUILDER", nm); continue
    try:
        b = fn()
        fr = render_icon("ICON_" + nm, os.path.join(out_dir, "icon_%s_raw.png" % nm))
        print("RENDERED", nm, b, fr)
    except Exception:
        print("FAILED", nm)
        traceback.print_exc()
