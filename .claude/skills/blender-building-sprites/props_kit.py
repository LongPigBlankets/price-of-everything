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


def _blob(self, name, cx, cy, cz, r, mat, rng, jitter=0.075, squash=0.88):
    """An irregular foliage clump: a dense UV sphere with seeded radial vertex noise.
    This is the actual tutorial technique — the organic read comes from silhouette
    IRREGULARITY, not from more perfect-sphere polygons. 32x20 segments so the jitter
    has vertices to work with; smooth sides keep the cel shading soft."""
    m = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=40, v_segments=26, radius=r)
    for v in bm.verts:
        v.co *= 1.0 + rng.uniform(-jitter, jitter)
    bmesh.ops.scale(bm, vec=(1.0, 1.0, squash), verts=bm.verts)
    bmesh.ops.translate(bm, vec=(cx, cy, cz), verts=bm.verts)
    bm.to_mesh(m); bm.free()
    ob = self.obj(name, m, mat)
    for poly in ob.data.polygons:
        poly.use_smooth = True
    return ob


def _taper(self, name, p0, p1, r0, r1, mat, segments=10):
    """Tapered limb between two points — trunks and branches thin toward the tip,
    which a constant-radius dircyl cannot do."""
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
    return self.obj(name, m, mat, smooth=True)


def _tree(self, name, x, y, h=1.9, r=0.45, seed=0):
    """Stylised street tree, tutorial construction: a TAPERED, slightly leaning trunk
    with root flares, three tapered branches forking into the crown, and a crown of
    jittered blobs (see _blob) — shaded clumps low/back, lit clumps high/front."""
    import random
    rng = random.Random(seed)
    zc = h * 0.70
    lean = (rng.uniform(-0.06, 0.06) * r, rng.uniform(-0.06, 0.06) * r)
    top = (x + lean[0], y + lean[1], h * 0.55)
    self._taper(name + "_trunk", (x, y, 0.0), top, r * 0.17, r * 0.085, self.mat("bark"))
    for ri in range(3):                       # root flares
        ang = rng.uniform(0, 6.283)
        self._taper("%s_root%d" % (name, ri), (x, y, 0.10),
                    (x + math.cos(ang) * r * 0.22, y + math.sin(ang) * r * 0.22, 0.0),
                    r * 0.075, r * 0.03, self.mat("bark"), segments=7)
    clumps = [(0.0, 0.0, 0.10, 1.00)]
    for ci in range(rng.randint(5, 7)):
        ang = rng.uniform(0, 6.283)
        rad = rng.uniform(0.45, 0.85)
        clumps.append((math.cos(ang) * r * rng.uniform(0.45, 0.8),
                       math.sin(ang) * r * rng.uniform(0.45, 0.8),
                       rng.uniform(-0.35, 0.55) * r, rad))
    for bi, (dx, dy, dz, rf) in enumerate(clumps[1:4]):   # branches fork to outer clumps
        self._taper("%s_br%d" % (name, bi), top,
                    (x + dx * 0.8, y + dy * 0.8, zc + dz * 0.6),
                    r * 0.055, r * 0.022, self.mat("bark"), segments=7)
    for ci, (dx, dy, dz, rf) in enumerate(clumps):
        shaded = dy > r * 0.15 or dz < -r * 0.1
        self._blob("%s_c%d" % (name, ci), x + dx, y + dy, zc + dz, r * rf,
                   self.mat("canopy_dark" if shaded else "canopy"), rng,
                   squash=rng.uniform(0.82, 0.92))


def _mark_noink_props(ob):
    mesh = ob.data
    attr = mesh.attributes.get("freestyle_face")
    if attr is None:
        attr = mesh.attributes.new("freestyle_face", 'BOOLEAN', 'FACE')
    for d in attr.data:
        d.value = True


def _grass_patch(self, name, x, y, rx=0.45, ry=0.30, dark=False, blades=3, seed=0):
    """A soft PATCH of grass: a flat NOINK disc of off-tone green lying on the verge
    (no outline — it reads as meadow variation, not an object), with a few fine-ink
    blades on its rim. Patches carry the texture; blades are accents only."""
    import random
    rng = random.Random(seed)
    m = bpy.data.meshes.new(name + "_pad")
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=1.0, radius2=1.0, depth=0.012)
    bm.to_mesh(m); bm.free()
    ob = self.obj(name + "_pad", m, self.mat("canopy_dark" if dark else "canopy"))
    ob.location = (x, y, 0.028)
    ob.scale = (rx, ry, 1.0)
    _mark_noink_props(ob)
    _fm = self._fine_mode
    self._fine_mode = True
    for i in range(blades):
        ang = rng.uniform(0, 6.283)
        bx = x + math.cos(ang) * rx * rng.uniform(0.4, 0.85)
        by = y + math.sin(ang) * ry * rng.uniform(0.4, 0.85)
        self.dircyl("%s_b%d" % (name, i), (bx, by, 0.022),
                    (bx + rng.uniform(-0.03, 0.03), by + rng.uniform(-0.03, 0.03),
                     0.022 + rng.uniform(0.06, 0.10)),
                    0.010, self.mat("canopy_dark"), segments=6, smooth=False)
    self._fine_mode = _fm


def _grass_tuft(self, name, x, y, s=1.0):
    """A few leaning blades — fine ink or they smudge at street scale."""
    _fm = self._fine_mode
    self._fine_mode = True
    for i, (dx, dy, lean_x, lean_y) in enumerate((
            (0.0, 0.0, 0.03, 0.01), (0.035, 0.02, -0.025, 0.02),
            (-0.03, 0.015, 0.01, -0.03), (0.01, -0.03, -0.02, -0.015))):
        base = (x + dx * s, y + dy * s, 0.022)
        tip = (x + (dx + lean_x) * s, y + (dy + lean_y) * s, 0.022 + 0.115 * s)
        self.dircyl("%s_b%d" % (name, i), base, tip, 0.013 * s,
                    self.mat("canopy_dark"), segments=6, smooth=False)
    self._fine_mode = _fm


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


Kit._blob = _blob
Kit._taper = _taper
Kit.tree = _tree
Kit.grass_patch = _grass_patch
Kit.grass_tuft = _grass_tuft
Kit.fence_run = _fence_run
Kit.lamppost = _lamppost
