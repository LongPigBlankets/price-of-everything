"""Parametric Blender builder for the Petrochemical Refinery.

Run inside Blender:
    exec(open(".../factory_builder.py").read())
    exec(open(".../refinery_builder.py").read())
    build_refinery(3)

The factory builder supplies the locked camera, palette, material and render
rig. This builder creates only the refinery collection, so it is safe to keep
alongside other building types in the shared .blend.
"""

import bpy
import bmesh
import math
from mathutils import Matrix, Vector


LEVELS = {
    # The core is a compact distillation unit: two domed process tanks, a hall,
    # and the complete three-flue silhouette requested for this building.
    1: dict(domers=2, flat_tanks=False, pipework=False),
    # Storage expands to the lower-right with two squat, flat-topped tanks.
    2: dict(domers=2, flat_tanks=True, pipework=False),
    # The landmark upgrade is an exposed silver manifold that visibly joins the
    # process and storage yards without moving the established L1/L2 masses.
    3: dict(domers=3, flat_tanks=True, pipework=True),
}

EPS = 0.015


def build_refinery(level: int = 3) -> dict:
    """Delete and rebuild BLDG_refinery for ``level`` (1, 2, or 3)."""
    if level not in LEVELS:
        raise ValueError("refinery level must be 1, 2, or 3")
    # factory_builder.py is deliberately executed first: its setup_rig() guards
    # against stale Blender session state (notably cast shadows and camera drift).
    setup_rig()
    p = LEVELS[level]

    for other in bpy.data.collections:
        if other.name.startswith("BLDG_") and other.name != "BLDG_refinery":
            other.hide_render = True
            other.hide_viewport = True

    col = bpy.data.collections.get("BLDG_refinery")
    if col is None:
        col = bpy.data.collections.new("BLDG_refinery")
        bpy.context.scene.collection.children.link(col)
    col.hide_render = False
    col.hide_viewport = False
    for ob in list(col.objects):
        bpy.data.objects.remove(ob, do_unlink=True)

    # This is an all-process exterior: every visible mass stays desaturated
    # slate/silver, with no enclosed building volume.
    palette = dict(PALETTE)
    palette.update({
        "plant_navy": (0.145, 0.180, 0.235),
        "tank_blue": (0.405, 0.455, 0.515),
        "stack_silver": (0.665, 0.690, 0.730),
        "brick": (0.318, 0.118, 0.082),
    })
    # ``_mat`` is the shared implementation; temporarily extend its palette so
    # new names get the same matte, zero-specular Principled setup.
    old_palette = PALETTE.copy()
    PALETTE.update(palette)
    mats = {name: _mat(name) for name in palette}
    PALETTE.clear(); PALETTE.update(old_palette)
    seam = _seam_material()

    def new_obj(name, mesh, mat=None, smooth=False):
        ob = bpy.data.objects.new(name, mesh)
        col.objects.link(ob)
        if mat:
            ob.data.materials.append(mat)
        for face in ob.data.polygons:
            # Rounded vessel walls only; caps stay flat so their rims ink cleanly.
            face.use_smooth = smooth and len(face.vertices) == 4
        return ob

    def box(name, cx, cy, cz, sx, sy, sz, mat):
        mesh = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
        bmesh.ops.translate(bm, vec=(cx, cy, cz), verts=bm.verts)
        bm.to_mesh(mesh); bm.free()
        return new_obj(name, mesh, mat)

    def cyl(name, cx, cy, cz, r, depth, mat, axis="Z", seg=32, smooth=True):
        mesh = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=seg,
                              radius1=r, radius2=r, depth=depth)
        if axis == "Y":
            bmesh.ops.rotate(bm, cent=(0, 0, 0),
                             matrix=Matrix.Rotation(math.radians(90), 3, "X"), verts=bm.verts)
        elif axis == "X":
            bmesh.ops.rotate(bm, cent=(0, 0, 0),
                             matrix=Matrix.Rotation(math.radians(90), 3, "Y"), verts=bm.verts)
        bmesh.ops.translate(bm, vec=(cx, cy, cz), verts=bm.verts)
        bm.to_mesh(mesh); bm.free()
        return new_obj(name, mesh, mat, smooth)

    def sphere(name, cx, cy, cz, r, mat, seg=24):
        mesh = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=12, radius=r)
        bmesh.ops.translate(bm, vec=(cx, cy, cz), verts=bm.verts)
        bm.to_mesh(mesh); bm.free()
        return new_obj(name, mesh, mat, True)

    def dir_cyl(name, a, b, r, mat, seg=20):
        """Cylinder directly between two points; end spheres hide every joint."""
        a, b = Vector(a), Vector(b)
        mid, delta = (a + b) / 2, b - a
        mesh = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=seg,
                              radius1=r, radius2=r, depth=delta.length)
        bmesh.ops.rotate(bm, cent=(0, 0, 0),
                         matrix=Vector((0, 0, 1)).rotation_difference(delta.normalized()).to_matrix(),
                         verts=bm.verts)
        bmesh.ops.translate(bm, vec=mid, verts=bm.verts)
        bm.to_mesh(mesh); bm.free()
        return new_obj(name, mesh, mat, True)

    def pipe_run(name, points, r=0.105):
        for i, (a, b) in enumerate(zip(points, points[1:])):
            dir_cyl(f"{name}_run_{i}", a, b, r, mats["silver"])
        for i, point in enumerate(points[1:-1]):
            sphere(f"{name}_elbow_{i}", *point, r * 1.32, mats["silver"], 16)

    def dome_tank(name, x, y):
        # A sphere sunk half its height into the cylinder is an actual round cap,
        # not a flat disk; the overlap is intentional to eliminate a T-junction.
        r, h = 0.63, 1.85
        cyl(f"{name}_shell", x, y, h / 2, r, h, mats["tank_blue"])
        sphere(f"{name}_dome", x, y, h, r, mats["tank_blue"])
        cyl(f"{name}_collar", x, y, h + 0.015, r + 0.055, 0.075, seam, seg=32)
        cyl(f"{name}_vent", x, y, h + r + 0.16, 0.075, 0.32, mats["silver"], seg=16)

    def flat_tank(name, x, y):
        r, h = 0.72, 1.12
        cyl(f"{name}_shell", x, y, h / 2, r, h, mats["tank_blue"])
        cyl(f"{name}_lid", x, y, h + 0.035, r + 0.065, 0.07, seam, seg=32)
        cyl(f"{name}_hatch", x, y, h + 0.10, 0.16, 0.10, mats["silver"], seg=16)

    # Small foundation pads keep equipment legible against the transparent
    # ground. They are equipment plinths, not a main building volume.
    box("process_pad", -1.20, 0.35, 0.08, 2.55, 3.20, 0.16, mats["concrete"])

    # Three tall silver flues form a deliberately simple, repeatable refinery
    # silhouette. The square collars are explicit intersection seams.
    flue_specs = ((0.72, 1.18, 4.40), (1.20, 1.66, 4.82), (1.68, 2.14, 4.52))
    for i, (x, y, top) in enumerate(flue_specs):
        base = 0.36
        box(f"flue_{i}_collar", x, y, base + 0.08, 0.58, 0.58, 0.16, seam)
        cyl(f"flue_{i}", x, y, (base + top) / 2, 0.22, top - base, mats["stack_silver"], seg=32)
        cyl(f"flue_{i}_rim", x, y, top + 0.035, 0.245, 0.07, seam, seg=32)

    # Equal +X/+Y separations read side-by-side in the locked camera. Keeping
    # the tank shells just apart avoids them collapsing into one peanut-shaped
    # silhouette while retaining a compact process yard.
    dome_positions = [(-2.05, -0.70), (-1.15, 0.20), (-0.25, 1.10)]
    for i, pos in enumerate(dome_positions[:p["domers"]]):
        dome_tank(f"dome_tank_{i}", *pos)

    if p["flat_tanks"]:
        box("storage_pad", 1.72, -0.73, 0.08, 2.82, 2.48, 0.16, mats["concrete"])
        flat_tank("flat_tank_0", 1.12, -1.33)
        flat_tank("flat_tank_1", 2.28, -0.17)

    if p["pipework"]:
        # Three independent tank-to-stack runs make the refinery's process
        # legible with the hall removed. Every run lands at its flue's BASE;
        # no pipe stops mysteriously in free space. The paths stay orthogonal
        # and use covered elbows so Freestyle produces clean, intentional ink.
        pipe_run("tank_0_to_flue_0", [(-1.42, -0.70, 1.25), (-1.42, -1.52, 1.25),
                                      (0.72, -1.52, 1.25), (0.72, 1.18, 1.25),
                                      (0.72, 1.18, 0.58)], 0.12)
        pipe_run("tank_1_to_flue_1", [(-0.52, 0.20, 1.25), (-0.52, -1.02, 1.25),
                                      (1.20, -1.02, 1.25), (1.20, 1.66, 1.25),
                                      (1.20, 1.66, 0.58)], 0.12)
        pipe_run("tank_2_to_flue_2", [(0.38, 1.10, 1.25), (0.38, 0.50, 1.25),
                                      (1.68, 0.50, 1.25), (1.68, 2.14, 1.25),
                                      (1.68, 2.14, 0.58)], 0.12)
        # A low collector makes the three flue inlets read as one processing
        # train while keeping the round tank caps unobscured.
        pipe_run("flue_collector", [(0.72, 1.18, 0.58), (0.72, 1.66, 0.58),
                                    (1.68, 1.66, 0.58), (1.68, 2.14, 0.58)], 0.10)

    return {"collection": col.name, "level": level}


def _seam_material():
    """Constant navy seam beads, matching the established factory/furnace ink."""
    mat = bpy.data.materials.get("ink_seam") or bpy.data.materials.new("ink_seam")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (0, 0, 0, 1)
    bsdf.inputs["Emission Color"].default_value = (0.012, 0.016, 0.045, 1)
    bsdf.inputs["Emission Strength"].default_value = 1.0
    return mat
