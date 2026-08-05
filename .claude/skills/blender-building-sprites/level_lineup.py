"""Build all three levels of a building side by side on one board, at ONE camera scale.

Why this exists: the per-building builders each write into a single BLDG_* collection and
hide every other one (skill rule 11), so only one level can be seen at a time. To show an
upgrade story you need the three standing together at identical scale — otherwise relative
size is unreadable, which is the whole point of a level set.

Placement follows the camera's screen axes, not world axes. At this isometric,
screen-horizontal is proportional to (x+y) and (x-y) is DEPTH, so the levels are separated
along EQUAL +x/+y. Separating along x alone would stack them behind each other.

Spacing is MEASURED: each level's span along the screen-horizontal axis is computed from its
own vertices, so a wider L3 gets the room it needs and the gaps stay visually even.

    exec(open("/Users/crisu/Price of Everything/blender-assets/sprite_kit.py").read())
    exec(open("/Users/crisu/Price of Everything/blender-assets/factory_builder.py").read())
    exec(open("/Users/crisu/Price of Everything/blender-assets/level_lineup.py").read())
    build_lineup(build_factory, "factory")
"""
import math
import bpy
import mathutils

ROOT2 = math.sqrt(2.0)


def _world_verts(col):
    """Every vertex of every mesh in a collection, in world space."""
    out = []
    for ob in col.objects:
        if ob.type != 'MESH':
            continue
        mw = ob.matrix_world
        for v in ob.data.vertices:
            out.append(mw @ v.co)
    return out


def _screen_axes():
    """Camera right/up in world space — the axes the render is actually laid out on."""
    cam = bpy.data.objects.get("Camera")
    m = cam.matrix_world.to_3x3()
    return m @ mathutils.Vector((1, 0, 0)), m @ mathutils.Vector((0, 1, 0))


def _move_to_collection(src, dst_name):
    """Move src's objects into a fresh collection named dst_name, and return it."""
    dst = bpy.data.collections.get(dst_name)
    if dst is None:
        dst = bpy.data.collections.new(dst_name)
        bpy.context.scene.collection.children.link(dst)
    for ob in list(dst.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for ob in list(src.objects):
        src.objects.unlink(ob)
        dst.objects.link(ob)
    dst.hide_render = False
    dst.hide_viewport = False
    return dst


def _translate(col, vec):
    for ob in col.objects:
        ob.location = ob.location + vec
    # matrix_world is a COMPUTED property: without this the reframe below re-measures the
    # pre-translation positions and fits the camera to one building instead of three.
    bpy.context.view_layer.update()


def build_stack(builder, name, levels=(1, 2, 3), margin=1.10, ppu=93.0):
    """Build every level AT THE SAME ORIGIN, framed by one camera that fits them all.

    For an upgrade cross-fade the levels must occupy the same ground, so the building
    appears to grow in place rather than sliding. The camera is fitted to the UNION of all
    levels, so nothing clips at any point in the sequence and the smaller levels render at
    their true relative size inside that fixed frame — which is what sells the growth.

    Returns the per-level collections; render them one at a time with `show_only`.
    """
    cols = []
    for lv in levels:
        builder(lv)
        src = bpy.data.collections.get("BLDG_%s" % name)
        if src is None or not src.objects:
            raise RuntimeError("builder produced nothing in BLDG_%s" % name)
        cols.append(_move_to_collection(src, "STACK_%s_L%d" % (name, lv)))

    # Hide EVERY other building collection, not just BLDG_*. A previous build_lineup leaves
    # SHOWCASE_* collections standing at their spread-out positions; they are not BLDG_*, so
    # a BLDG-only sweep leaves them renderable and they intrude from off-frame (they showed
    # up as an inked strip pinned to the right edge of all three stack renders, including
    # L1, whose own building was nowhere near that edge).
    keep = {c.name for c in cols}
    for c in bpy.data.collections:
        if c.name in keep or c.name == "FINE_INK":
            continue
        if c.name.startswith("BLDG_") or c.name.startswith("SHOWCASE_") or c.name.startswith("STACK_"):
            c.hide_render = True
            c.hide_viewport = True

    # FINE_INK leaks past collection hiding — see geometry rule 12.
    mine = set()
    for col in cols:
        mine.update(o.name for o in col.objects)
    fine = bpy.data.collections.get("FINE_INK")
    if fine:
        for ob in fine.objects:
            stale = ob.name not in mine
            ob.hide_render = stale
            ob.hide_viewport = stale

    right, up = _screen_axes()
    xs, ys = [], []
    for col in cols:
        for v in _world_verts(col):
            xs.append(v.dot(right))
            ys.append(v.dot(up))
    W, H = max(xs) - min(xs), max(ys) - min(ys)
    cam = bpy.data.objects.get("Camera")
    scene = bpy.context.scene
    span = max(W, H) * margin
    cam.data.ortho_scale = span
    cam.location = (right * ((min(xs) + max(xs)) / 2) + up * ((min(ys) + max(ys)) / 2)
                    + mathutils.Vector((1, -1, 1)).normalized() * 60.0)
    # Square canvas: ortho_scale maps to the larger dimension, and a square keeps the
    # framing valid whichever way the union turns out.
    px = int(round(span * ppu))
    scene.render.resolution_x = px
    scene.render.resolution_y = px

    return {"collections": [c.name for c in cols], "levels": list(levels),
            "ortho_scale": round(span, 3), "res": [px, px]}


def fit_stack(name, res=1080, margin=0.06, bottom=0.19, ppu_base=93.0, base_res=None):
    """Frame every visible STACK_<name>_L* level, reserving a caption band at the bottom.

    NDC y is 0 at the BOTTOM, and captions are drawn there, so the fit is ASYMMETRIC:
    x into [margin, 1-margin] but y into [bottom, 1-margin]. Centring symmetrically drops
    the building onto its own caption — the furnace's L3 landed at y=1022 against a caption
    band at 972-1020. Reserve the band in the FRAMING; shifting the rendered pixels up
    instead clips the top, which is where the tallest level's stack lives.

    Also rescales Freestyle to the new canvas: thickness is in ABSOLUTE PIXELS, so a render
    bigger than the sprite rig's 93 px-per-world-unit thins the ink relative to the subject.
    """
    from bpy_extras.object_utils import world_to_camera_view
    scene = bpy.context.scene
    cam = bpy.data.objects["Camera"]

    for c in bpy.data.collections:
        if c.name.startswith("STACK_%s_L" % name):
            c.hide_render = False
            c.hide_viewport = False

    if base_res is None:
        base_res = scene.render.resolution_x
    k = res / float(base_res)
    scene.render.resolution_x = scene.render.resolution_y = res
    fs = scene.view_layers[0].freestyle_settings
    fs.linesets["ink"].linestyle.thickness = 2.4 * k
    fs.linesets["contour"].linestyle.thickness = 7.0 * k
    if "ink_fine" in fs.linesets:
        fs.linesets["ink_fine"].linestyle.thickness = 1.05 * k

    def bbox():
        xs, ys = [], []
        for c in bpy.data.collections:
            if not c.name.startswith("STACK_%s_L" % name) or c.hide_render:
                continue
            for ob in c.objects:
                if ob.type != 'MESH':
                    continue
                mw = ob.matrix_world
                for v in ob.data.vertices:
                    p = world_to_camera_view(scene, cam, mw @ v.co)
                    xs.append(p.x)
                    ys.append(p.y)
        return min(xs), max(xs), min(ys), max(ys)

    for _ in range(4):
        x0, x1, y0, y1 = bbox()
        cam.data.ortho_scale *= max((x1 - x0) / (1 - 2 * margin),
                                    (y1 - y0) / (1 - margin - bottom))
        bpy.context.view_layer.update()
        x0, x1, y0, y1 = bbox()
        m3 = cam.matrix_world.to_3x3()
        cam.location = (cam.location
                        + (m3 @ mathutils.Vector((1, 0, 0)))
                        * (((x0 + x1) / 2 - 0.5) * cam.data.ortho_scale)
                        + (m3 @ mathutils.Vector((0, 1, 0)))
                        * (((y0 + y1) / 2 - (bottom + 1 - margin) / 2) * cam.data.ortho_scale))
        bpy.context.view_layer.update()
    return {"ndc": [round(v, 4) for v in bbox()], "ortho": round(cam.data.ortho_scale, 3),
            "res": res, "ink_scale": round(k, 3)}


def render_stack(name, out_dir, levels=(1, 2, 3)):
    """Render each level alone to out_dir/L<n>.png at the current camera."""
    import os
    os.makedirs(out_dir, exist_ok=True)
    scene = bpy.context.scene
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.film_transparent = True
    for lv in levels:
        show_only(name, lv, levels)
        scene.render.filepath = os.path.join(out_dir, "L%d" % lv)
        bpy.ops.render.render(write_still=True)
    return {"out": out_dir, "levels": list(levels)}


def show_only(name, level, levels=(1, 2, 3)):
    """Make exactly one STACK level renderable. Used between renders.

    Hides per OBJECT as well as per collection. Builders that use a fine-ink assembly
    (transformer / pylon / lattice_mast / insulator_string — the power plant uses several)
    DUAL-LINK those objects into FINE_INK, which stays visible so the ink_fine lineset can
    draw. Hiding only this level's collection therefore leaves the other levels' pylons and
    transformers renderable, and they composite straight over the level being rendered.
    See geometry rule 12.
    """
    for lv in levels:
        c = bpy.data.collections.get("STACK_%s_L%d" % (name, lv))
        if not c:
            continue
        off = lv != level
        c.hide_render = off
        c.hide_viewport = off
        for ob in c.objects:
            ob.hide_render = off
            ob.hide_viewport = off
    return {"visible": level}


def build_lineup(builder, name, levels=(1, 2, 3), gap=0.9, margin=1.06):
    """Build `levels` via `builder(level)` and lay them out left->right on screen.

    builder : the per-level build function, e.g. build_factory
    name    : used for the SHOWCASE_<name>_L<n> collection names
    gap     : clear space between levels, in screen-horizontal world units
    margin  : ortho_scale padding factor
    """
    cols, spans = [], []

    # 1. Build each level and park it in its own collection, measuring its screen span.
    for lv in levels:
        builder(lv)
        src = bpy.data.collections.get("BLDG_%s" % name)
        if src is None or not src.objects:
            raise RuntimeError("builder produced nothing in BLDG_%s" % name)
        col = _move_to_collection(src, "SHOWCASE_%s_L%d" % (name, lv))
        us = [(v.x + v.y) / ROOT2 for v in _world_verts(col)]
        cols.append(col)
        spans.append((min(us), max(us)))

    # 2. Place them: each level's left edge starts one `gap` after the previous right edge.
    #    A shift of du along screen-horizontal is a world translation of du/sqrt2 on BOTH
    #    x and y — equal parts, so depth (x-y) is untouched and nothing stacks.
    cursor = 0.0
    for col, (u0, u1) in zip(cols, spans):
        du = cursor - u0
        t = du / ROOT2
        _translate(col, mathutils.Vector((t, t, 0.0)))
        cursor += (u1 - u0) + gap

    # 3. Hide every BLDG_* (the builders left the last one visible), show the showcase set.
    for c in bpy.data.collections:
        if c.name.startswith("BLDG_"):
            c.hide_render = True
            c.hide_viewport = True
    for col in cols:
        col.hide_render = False
        col.hide_viewport = False

    # 3b. FINE_INK defeats collection hiding. Any builder using a fine-ink assembly
    #     (pylon / transformer / lattice_mast / insulator_string) DUAL-LINKS those objects
    #     into FINE_INK, which must stay visible for the ink_fine lineset. Hiding the
    #     owning BLDG_* therefore does not hide them, and they render into every later
    #     shot — the construction site's 42-object crane mast turned up hanging over L1.
    #     Collections cannot fix this; hide per OBJECT.
    mine = set()
    for col in cols:
        mine.update(o.name for o in col.objects)
    fine = bpy.data.collections.get("FINE_INK")
    hidden = 0
    if fine:
        for ob in fine.objects:
            stale = ob.name not in mine
            ob.hide_render = stale
            ob.hide_viewport = stale
            hidden += int(stale)

    # 4. Reframe: fit the group by projecting every vertex onto the camera's own axes.
    #    Rotation is NOT touched — the locked isometric is the whole style contract; only
    #    ortho_scale and the position perpendicular to the view axis change.
    right, up = _screen_axes()
    xs, ys = [], []
    for col in cols:
        for v in _world_verts(col):
            xs.append(v.dot(right))
            ys.append(v.dot(up))
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    scale = max(max(xs) - min(xs), max(ys) - min(ys)) * margin

    cam = bpy.data.objects.get("Camera")
    cam.data.ortho_scale = scale
    centre = right * cx + up * cy
    cam.location = centre + mathutils.Vector((1, -1, 1)).normalized() * 60.0

    return {
        "levels": list(levels),
        "fine_ink_hidden": hidden,
        "collections": [c.name for c in cols],
        "spans": spans,
        "ortho_scale": round(scale, 3),
        "objects": [len(c.objects) for c in cols],
    }
