"""Street props for the loading scene and future dioramas: tree, grass tuft, fence
run, lamppost. Extends the sprite kit by PATCHING Kit — sprite_kit.py is owner-approved
geometry and stays untouched. exec sprite_kit.py first, then this file, THEN build.

Ordering trap (cost a debugging round elsewhere): open_collection() unlinks every
object from FINE_INK, so props that fine-ink themselves must be built AFTER all
builders have run. If phase1 re-runs, phase3 must re-run too, or the props silently
revert to thick ink.
"""
import math
import bpy
import bmesh

# Palette additions — picked against the measured AgX curve like every kit tone.
PALETTE["canopy"] = (0.150, 0.310, 0.100)      # lit foliage
PALETTE["canopy_dark"] = (0.100, 0.215, 0.075) # shaded foliage mass
PALETTE["bark"] = (0.170, 0.120, 0.080)


def _blob(self, name, cx, cy, cz, r, mat, rng, jitter=0.12, scale=(1.0, 1.0, 0.85)):
    """A FACETED foliage clump (owner reference: classic low-poly tree): icosphere at
    subdiv 2 with seeded vertex noise, FLAT shaded so every facet reads as a distinct
    cel plane — the polygons ARE the look. Mild anisotropy keeps clumps wider than
    tall; the 120-degree crease threshold leaves facet interiors un-inked, so only
    the lumpy silhouette carries line."""
    m = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=3, radius=r)
    for v in bm.verts:
        v.co *= 1.0 + rng.uniform(-jitter, jitter)
    bmesh.ops.scale(bm, vec=scale, verts=bm.verts)
    bmesh.ops.translate(bm, vec=(cx, cy, cz), verts=bm.verts)
    bm.to_mesh(m); bm.free()
    ob = self.obj(name, m, mat)
    for poly in ob.data.polygons:
        poly.use_smooth = False
    return ob


def _taper(self, name, p0, p1, r0, r1, mat, segments=7, smooth=False):
    """Tapered limb between two points. FLAT-shaded low-segment by default now — the
    faceted trunk is part of the reference look."""
    import mathutils
    a, b = mathutils.Vector(p0), mathutils.Vector(p1)
    d = b - a
    m = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segments,
                          radius1=r0, radius2=r1, depth=d.length)
    rot = mathutils.Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix()
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=rot, verts=bm.verts)
    bmesh.ops.translate(bm, vec=(a + b) / 2, verts=bm.verts)
    bm.to_mesh(m); bm.free()
    return self.obj(name, m, mat, smooth=smooth)


def _tree(self, name, x, y, h=1.9, r=0.45, seed=0):
    """Low-poly stylised tree after the owner's reference: kinked faceted trunk that
    FORKS into limbs, each limb ending in a faceted clump; a couple of pebbles at
    the base. Flat shading throughout — facets are the aesthetic."""
    import random
    rng = random.Random(seed)
    # Kinked main trunk (3 segments, flat, 7-sided).
    pts = [(x, y, 0.0)]
    top_z = h * 0.52
    for si in range(1, 4):
        t = si / 3.0
        pts.append((x + rng.uniform(-0.12, 0.12) * r * (0.5 + t),
                    y + rng.uniform(-0.12, 0.12) * r * (0.5 + t),
                    top_z * t))
    r_base, r_tip = r * 0.20, r * 0.09
    for si in range(3):
        r0 = r_base + (r_tip - r_base) * (si / 3.0)
        r1 = r_base + (r_tip - r_base) * ((si + 1) / 3.0)
        self._taper("%s_t%d" % (name, si), pts[si], pts[si + 1], r0, r1, self.mat("bark"))
        if si > 0:
            jx, jy, jz = pts[si]
            self.sphere("%s_j%d" % (name, si), jx, jy, jz, r0 * 1.05, self.mat("bark"))
    # Root flare + pebbles (the reference scatters rocks at the base).
    for ri in range(2):
        ang = rng.uniform(0, 6.283)
        self._taper("%s_root%d" % (name, ri), (x, y, 0.09),
                    (x + math.cos(ang) * r * 0.24, y + math.sin(ang) * r * 0.24, 0.0),
                    r * 0.08, r * 0.03, self.mat("bark"), segments=6)
    for pi in range(rng.randint(2, 3)):
        ang = rng.uniform(0, 6.283)
        pr = r * rng.uniform(0.055, 0.10)
        m2 = bpy.data.meshes.new("%s_peb%d" % (name, pi))
        bm2 = bmesh.new()
        bmesh.ops.create_icosphere(bm2, subdivisions=1, radius=pr)
        bmesh.ops.scale(bm2, vec=(1.0, 1.0, 0.6), verts=bm2.verts)
        bmesh.ops.translate(bm2, vec=(x + math.cos(ang) * r * rng.uniform(0.3, 0.5),
                                      y + math.sin(ang) * r * rng.uniform(0.3, 0.5),
                                      pr * 0.35), verts=bm2.verts)
        bm2.to_mesh(m2); bm2.free()
        self.obj("%s_peb%d" % (name, pi), m2, self.mat("earth"))
    # Fork: 2-3 limbs from the trunk top, each carrying a clump; plus a top clump.
    top = pts[-1]
    n_limb = rng.randint(2, 3)
    clumps = [(0.0, 0.0, h * 0.78 - top[2], 1.00, False)]
    for li in range(n_limb):
        ang = rng.uniform(0, 6.283)
        dx = math.cos(ang) * r * rng.uniform(0.55, 1.0)
        dy = math.sin(ang) * r * rng.uniform(0.55, 1.0)
        dz = rng.uniform(0.05, 0.45) * r
        rf = rng.uniform(0.5, 0.8)
        clumps.append((dx, dy, dz, rf, True))
    for ci, (dx, dy, dz, rf, limbed) in enumerate(clumps):
        cxx, cyy, czz = x + dx, y + dy, top[2] + dz
        if limbed:
            self._taper("%s_l%d" % (name, ci), top,
                        (cxx - dx * 0.25, cyy - dy * 0.25, czz - r * rf * 0.3),
                        r * 0.06, r * 0.025, self.mat("bark"), segments=6)
        shaded = dy > r * 0.15 or dz < 0.0
        self._blob("%s_c%d" % (name, ci), cxx, cyy, czz, r * rf,
                   self.mat("canopy_dark" if shaded else "canopy"), rng,
                   scale=(1.0 + rng.uniform(0.05, 0.25),
                          1.0 + rng.uniform(0.0, 0.18),
                          rng.uniform(0.72, 0.88)))


def _mark_noink_props(ob):
    mesh = ob.data
    attr = mesh.attributes.get("freestyle_face")
    if attr is None:
        attr = mesh.attributes.new("freestyle_face", 'BOOLEAN', 'FACE')
    for d in attr.data:
        d.value = True


def _grass_patch(self, name, x, y, rx=0.45, ry=0.30, dark=False, blades=3, seed=0):
    """A scatter of tapered grass blades inside an ellipse — NO base disc and NO ink
    (owner 2026-08-06: the old NOINK pad ellipse could cross onto the sidewalk and
    read as spilled paint, and the outlined constant-radius cylinder blades read as
    navy scratches — the outline WAS the blade). Leaning tapered spikes in the two
    canopy greens against the lawn tone carry the meadow texture on their own."""
    import random
    rng = random.Random(seed)
    for i in range(max(6, blades * 3)):
        ang = rng.uniform(0, 6.283)
        rad = math.sqrt(rng.random())          # uniform over the ellipse area
        bx = x + math.cos(ang) * rx * rad
        by = y + math.sin(ang) * ry * rad
        h = rng.uniform(0.06, 0.13)
        lean = rng.uniform(0.15, 0.45) * h
        la = rng.uniform(0, 6.283)
        mat = self.mat("canopy_dark" if (dark or rng.random() < 0.6) else "canopy")
        ob = self._taper("%s_b%d" % (name, i), (bx, by, 0.012),
                         (bx + math.cos(la) * lean, by + math.sin(la) * lean,
                          0.012 + h),
                         rng.uniform(0.014, 0.022), 0.002, mat, segments=5)
        _mark_noink_props(ob)


def _grass_tuft(self, name, x, y, s=1.0):
    """A clump: tapered blades fanning out from one root, leaning outward — the
    classic grass-tuft silhouette. NOINK for the same reason as _grass_patch."""
    import random
    rng = random.Random((int(x * 37) + int(y * 91)) & 0xFFFF)
    n = rng.randint(5, 6)
    for i in range(n):
        la = (i / n) * 6.283 + rng.uniform(-0.4, 0.4)
        h = rng.uniform(0.07, 0.14) * s
        lean = rng.uniform(0.25, 0.6) * h
        bx = x + math.cos(la) * 0.012 * s
        by = y + math.sin(la) * 0.012 * s
        ob = self._taper("%s_b%d" % (name, i), (bx, by, 0.012),
                         (bx + math.cos(la) * lean, by + math.sin(la) * lean,
                          0.012 + h),
                         0.016 * s, 0.002, self.mat("canopy_dark"), segments=5)
        _mark_noink_props(ob)


def _fence_run(self, name, p0, p1, h=0.42, post_gap=0.95):
    """Post-and-two-rail yard fence between two ground points. Fine ink: at 0.045-wide
    posts the 2.4px line is the whole post."""
    import mathutils
    _fm = self._fine_mode
    self._fine_mode = True
    a = mathutils.Vector((p0[0], p0[1], 0.0))
    b = mathutils.Vector((p1[0], p1[1], 0.0))
    d = b - a
    n = max(2, int(d.length / post_gap) + 1)
    for i in range(n):
        p = a + d * (i / (n - 1))
        self.box("%s_p%d" % (name, i), p.x, p.y, h / 2, 0.045, 0.045, h, self.mat("darkmetal"))
    for tag, z in (("r0", h * 0.55), ("r1", h * 0.95)):
        mid = (a + b) / 2
        ang = mathutils.Vector((1, 0)).angle_signed(mathutils.Vector((d.x, d.y)))
        rail = self.box("%s_%s" % (name, tag), mid.x, mid.y, z,
                        d.length + 0.05, 0.032, 0.032, self.mat("darkmetal"))
        rail.rotation_euler = (0, 0, ang)
    self._fine_mode = _fm


def _lamppost(self, name, x, y, h=1.55, arm=0.45, toward=-1):
    """Street lamp: post, horizontal arm over the road (toward = -1 south / +1 north),
    slab head with a cream lens underneath. Fine ink throughout."""
    _fm = self._fine_mode
    self._fine_mode = True
    self.dircyl(name + "_post", (x, y, 0.0), (x, y, h), 0.034, self.mat("darkmetal"))
    ay = y + toward * arm
    self.dircyl(name + "_arm", (x, y, h - 0.02), (x, ay, h + 0.10), 0.026, self.mat("darkmetal"))
    self.box(name + "_head", x, ay + toward * 0.05, h + 0.115, 0.15, 0.24, 0.07, self.mat("darkmetal"))
    self.box(name + "_lens", x, ay + toward * 0.05, h + 0.072, 0.10, 0.17, 0.022, self.mat("mullion"))
    self._fine_mode = _fm


def _spiky_bush(self, name, x, y, h=0.55, r=0.30, seed=0):
    """Spiky evergreen bush (owner reference: small conifers between the trees):
    a cluster of 3-5 jittered flat-shaded cones at varied heights and leans."""
    import random
    rng = random.Random(seed)
    n = rng.randint(3, 5)
    for ci in range(n):
        ang = rng.uniform(0, 6.283)
        dx = math.cos(ang) * r * (0 if ci == 0 else rng.uniform(0.35, 0.75))
        dy = math.sin(ang) * r * (0 if ci == 0 else rng.uniform(0.35, 0.75))
        ch = h * (1.0 if ci == 0 else rng.uniform(0.5, 0.85))
        cr = r * (0.55 if ci == 0 else rng.uniform(0.3, 0.5))
        m = bpy.data.meshes.new("%s_c%d" % (name, ci))
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=7,
                              radius1=cr, radius2=cr * 0.06, depth=ch)
        for v in bm.verts:
            v.co.x *= 1.0 + rng.uniform(-0.15, 0.15)
            v.co.y *= 1.0 + rng.uniform(-0.15, 0.15)
        bmesh.ops.translate(bm, vec=(x + dx, y + dy, ch / 2), verts=bm.verts)
        bm.to_mesh(m); bm.free()
        self.obj("%s_c%d" % (name, ci), m,
                 self.mat("canopy_dark" if ci % 2 else "canopy"))


Kit.spiky_bush = _spiky_bush
Kit._blob = _blob
Kit._taper = _taper
Kit.tree = _tree
Kit.grass_patch = _grass_patch
Kit.grass_tuft = _grass_tuft
Kit.fence_run = _fence_run
Kit.lamppost = _lamppost
