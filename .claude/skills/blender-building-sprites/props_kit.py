"""Street props for the loading scene and future dioramas: tree, grass tuft, fence
run, lamppost. Extends the sprite kit by PATCHING Kit — sprite_kit.py is owner-approved
geometry and stays untouched. exec sprite_kit.py first, then this file, THEN build.

Ordering trap (cost a debugging round elsewhere): open_collection() unlinks every
object from FINE_INK, so props that fine-ink themselves must be built AFTER all
builders have run. If phase1 re-runs, phase3 must re-run too, or the props silently
revert to thick ink.
"""

# Palette additions — picked against the measured AgX curve like every kit tone.
PALETTE["canopy"] = (0.150, 0.310, 0.100)      # lit foliage
PALETTE["canopy_dark"] = (0.100, 0.215, 0.075) # shaded foliage mass
PALETTE["bark"] = (0.170, 0.120, 0.080)


def _tree(self, name, x, y, h=1.9, r=0.45):
    """Poster street tree: short trunk, canopy of three smooth spheres — one dark at
    the back for depth, two lit in front. Spheres keep hard ink silhouettes (smooth
    sides, rule 6) and the two-tone mass reads as foliage without any texture."""
    self.dircyl(name + "_trunk", (x, y, 0.0), (x, y, h * 0.45), r * 0.14, self.mat("bark"))
    self.sphere(name + "_c0", x + r * 0.30, y - r * 0.25, h * 0.68, r, self.mat("canopy"))
    self.sphere(name + "_c1", x - r * 0.45, y + r * 0.30, h * 0.72, r * 0.78, self.mat("canopy_dark"))
    self.sphere(name + "_c2", x + r * 0.15, y + r * 0.15, h * 0.92, r * 0.62, self.mat("canopy"))


def _grass_tuft(self, name, x, y, s=1.0):
    """A few leaning blades — fine ink or they smudge at street scale."""
    _fm = self._fine_mode
    self._fine_mode = True
    for i, (dx, dy, lean_x, lean_y) in enumerate((
            (0.0, 0.0, 0.03, 0.01), (0.035, 0.02, -0.025, 0.02),
            (-0.03, 0.015, 0.01, -0.03), (0.01, -0.03, -0.02, -0.015))):
        base = (x + dx * s, y + dy * s, 0.0)
        tip = (x + (dx + lean_x) * s, y + (dy + lean_y) * s, 0.115 * s)
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


Kit.tree = _tree
Kit.grass_tuft = _grass_tuft
Kit.fence_run = _fence_run
Kit.lamppost = _lamppost
