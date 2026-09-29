"""Pure water (g_009): an outlet pipe on a post pouring a clean stream into a splash.

Reference: assets/icons/goods/medium/g_009_pure_water.png. The shipped art decides the
composition (symbol kept: it is right about the good and a droplet would collide with
hydrogen's). D = the pipe body's outer diameter = 1; the pipe runs along world Y with its
mouth facing -Y (the front), so the fixed camera draws it lower left to upper right.
v18 numbers (reference measured at a matched body diameter in two review rounds):

  pipe centre height 2.65 D; socket mouth 1.41 D outside, 1.11 D bore, 0.5 D long, the
  bore one dark tone dotted all over; body 1.0 D, 2.6 D from the mouth face to the back
  end; one 1.2 D coupling over the post (0.9 D long, grooved at its middle), a plain back
  end behind it. Post 0.25 D, a 0.37 D collar showing 0.26 D under the pipe, 0.49 D puck.
  Stream 0.86 x 0.70 D at the lip (0.38 D of dark bore above it) rounding to 0.89 x 0.86 D;
  level through the socket, then one bend (radius checked), landing 0.9 D in front of the
  mouth face.
  Splash: a front-only ribbon on an ellipse 1.56 x 1.04 D round the landing point, its rim a
  W (cusps under the stream's edges) with a pale lip band and rounded end lobes; two
  flattened tongues rise beside the stream behind it (left 0.84 D, right 0.58 D), broad face
  to the camera, leaning out. Pool a smooth oval 2.0 x 1.32 D set 0.3 D forward, two arcs.
Water is flat and clean (owner: no halftone on glass) with 6 pale streaks 0.08 D wide.
Khaki: a dominant base, a narrow inset highlight stripe, a short half step, the shadow with
dots. Lines: the set's 12/6 px; dots at the set's density (approved alternates 2.5-3.7 %).
Round-1 asks overruled on the approved set's evidence: the reference's dense full-ink screen
and an 8.5 px interior-line tier.
OWNER (v18 -> v22): "look at the flange and ribs on the pipe. It's ignoring where the flange
meets the pipe." A step must show its face with ink on both edges. From the fixed camera a
flat face turned away (+Y) never shows and a 45 degree shoulder is edge-on, so steps that
face away are 30 degree shoulders (the flange's back, the coupling's back); the coupling's
front face is a crescent inked at both edges and closed by the pipe's own silhouette edges;
the post's collar shows 0.24 D below the coupling. Shoulder edges stay sharp (smoothing 15).
"""
import math, bmesh
from mathutils import Vector

PW_REVISION = 'pure_water_v22'
PW_HC = 2.65
PW_Y_POST = 1.40


def pw_toon(name, colour, steps):
    """Toon emission with any number of flat steps: steps = ((threshold, multiplier), ...),
    the last threshold above the shading range. Same node graph as base_kit.toon_mat."""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial'); emis = nt.nodes.new('ShaderNodeEmission')
    diff = nt.nodes.new('ShaderNodeBsdfDiffuse'); diff.inputs['Color'].default_value = (1, 1, 1, 1)
    s2r = nt.nodes.new('ShaderNodeShaderToRGB'); ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.interpolation = 'CONSTANT'
    els = ramp.color_ramp.elements
    els[0].position = 0.0; els[0].color = (steps[0][1],) * 3 + (1,)
    els[1].position = steps[0][0]; els[1].color = (steps[1][1],) * 3 + (1,)
    for i in range(2, len(steps)):
        e = els.new(steps[i - 1][0]); e.color = (steps[i][1],) * 3 + (1,)
    mix = nt.nodes.new('ShaderNodeMix'); mix.data_type = 'RGBA'; mix.blend_type = 'MULTIPLY'
    mix.inputs['Factor'].default_value = 1.0; mix.inputs[6].default_value = (*colour, 1.0)
    nt.links.new(diff.outputs[0], s2r.inputs[0]); nt.links.new(s2r.outputs['Color'], ramp.inputs['Fac'])
    nt.links.new(ramp.outputs['Color'], mix.inputs[7]); nt.links.new(mix.outputs[2], emis.inputs['Color'])
    emis.inputs['Strength'].default_value = 1.0; nt.links.new(emis.outputs[0], out.inputs[0])
    return m


def pw_flat(name, colour):
    """Unlit flat colour (highlight streaks): pure emission, no specular."""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    e = nt.nodes.new('ShaderNodeEmission'); e.inputs[0].default_value = (*colour, 1)
    o = nt.nodes.new('ShaderNodeOutputMaterial'); nt.links.new(e.outputs[0], o.inputs[0])
    return m


def pw_smooth(ob, angle_deg=35.0):
    """Smooth faces, sharp edges where neighbours turn more than angle_deg (rims stay crisp)."""
    me = ob.data; bm = bmesh.new(); bm.from_mesh(me); bm.normal_update()
    lim = math.radians(angle_deg)
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        if len(e.link_faces) == 2:
            a, b = e.link_faces
            e.smooth = a.normal.angle(b.normal, 0.0) <= lim
        else:
            e.smooth = False
    bm.to_mesh(me); bm.free()
    return ob


def pw_clean_water(ob):
    """No dots on water: the shade-mask material maxes this attribute into 'lit'."""
    me = ob.data
    attr = me.attributes.get('icon_stipple_clear') or me.attributes.new('icon_stipple_clear', 'FLOAT', 'CORNER')
    for d in attr.data:
        d.value = 1.0
    return ob


def pw_revolve_y(K, name, profile, mat, segments=160, cx=0.0, cz=PW_HC):
    """Closed (y, r) profile loop revolved about the Y axis through (cx, cz). The loop never
    touches the axis, so the solid is one closed manifold ring."""
    n = segments; vs = []
    for (y, r) in profile:
        for k in range(n):
            t = 2 * math.pi * k / n
            vs.append((cx + r * math.cos(t), y, cz + r * math.sin(t)))
    m = len(profile); fs = []
    for i in range(m):
        j = (i + 1) % m
        for k in range(n):
            k2 = (k + 1) % n
            fs.append((i * n + k, i * n + k2, j * n + k2, j * n + k))
    return pw_smooth(mesh(K, name, vs, fs, mat, False), 15)   # 30 degree shoulders stay crisp


def pw_lathe_z(K, name, profile, mat, centre, segments=120):
    """(r, z) profile from the axis back to the axis, revolved about Z at `centre` (baked in)."""
    cx, cy = centre; n = segments; vs = []; fs = []
    rows = []
    for (r, z) in profile:
        if r < 1e-9:
            rows.append([len(vs)]); vs.append((cx, cy, z))
        else:
            rows.append(list(range(len(vs), len(vs) + n)))
            vs.extend((cx + r * math.cos(2 * math.pi * k / n), cy + r * math.sin(2 * math.pi * k / n), z) for k in range(n))
    for a, b in zip(rows, rows[1:]):
        for k in range(n):
            k2 = (k + 1) % n
            if len(a) == 1:
                fs.append((a[0], b[k], b[k2]))
            elif len(b) == 1:
                fs.append((a[k], b[0], a[k2]))
            else:
                fs.append((a[k], b[k], b[k2], a[k2]))
    return pw_smooth(mesh(K, name, vs, fs, mat, False), 35)


def pw_circle_y(K, name, y, r, label, width=6, n=240):
    pts = [(r * math.cos(2 * math.pi * k / n), y, PW_HC + r * math.sin(2 * math.pi * k / n)) for k in range(n)]
    return tagged_line(K, name, pts, label, width, True)


def pw_circle_z(K, name, centre, z, r, label, width=6, n=200):
    pts = [(centre[0] + r * math.cos(2 * math.pi * k / n), centre[1] + r * math.sin(2 * math.pi * k / n), z) for k in range(n)]
    return tagged_line(K, name, pts, label, width, True)


def pw_bezier(p0, p1, p2, p3, n):
    out = []
    for i in range(n + 1):
        t = i / n; u = 1 - t
        out.append(p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t))
    return out


def pw_resample(pts, n):
    d = [0.0]
    for a, b in zip(pts, pts[1:]):
        d.append(d[-1] + (b - a).length)
    L = d[-1]; out = []; j = 1
    for i in range(n + 1):
        s = L * i / n
        while j < len(d) - 1 and d[j] < s:
            j += 1
        t = (s - d[j - 1]) / max(d[j] - d[j - 1], 1e-12)
        out.append(pts[j - 1].lerp(pts[j], min(max(t, 0.0), 1.0)))
    return out, L


def pw_min_radius(pts):
    """Smallest circumradius of consecutive sample triples: the tightest bend of a centreline."""
    best = 1e9
    for a, b, c in zip(pts, pts[1:], pts[2:]):
        ab = (b - a).length; bc = (c - b).length; ca = (a - c).length
        area2 = (b - a).cross(c - a).length
        if area2 > 1e-12:
            best = min(best, ab * bc * ca / (2 * area2))
    return best


def pw_frames(centre):
    """Planar (YZ) centreline frames: X across, N = X x T in the plane of the fall."""
    X = Vector((1, 0, 0)); n = len(centre); frames = []
    for i, c in enumerate(centre):
        t = (centre[min(i + 1, n - 1)] - centre[max(i - 1, 0)]).normalized()
        frames.append((c, X.cross(t).normalized()))
    return frames


def pw_section_point(frame, a, b, phi):
    c, N = frame
    return c + Vector((1, 0, 0)) * (a * math.cos(phi)) + N * (b * math.sin(phi))


def pw_stream(K, name, frames, a_of, b_of, mat, seg=72):
    n = len(frames); vs = []; fs = []
    for i, fr in enumerate(frames):
        u = i / (n - 1)
        for k in range(seg):
            vs.append(tuple(pw_section_point(fr, a_of(u), b_of(u), 2 * math.pi * k / seg)))
    for i in range(n - 1):
        for k in range(seg):
            k2 = (k + 1) % seg
            fs.append((i * seg + k, i * seg + k2, (i + 1) * seg + k2, (i + 1) * seg + k))
    fs.append(tuple(reversed(range(seg)))); fs.append(tuple((n - 1) * seg + k for k in range(seg)))
    return pw_smooth(mesh(K, name, vs, fs, mat, False), 60)


def pw_frame_at(frames, u):
    f = u * (len(frames) - 1); i = min(int(f), len(frames) - 2); w = f - i
    c = frames[i][0].lerp(frames[i + 1][0], w)
    N = frames[i][1].lerp(frames[i + 1][1], w).normalized()
    return (c, N)


def pw_streak(K, name, frames, a_of, b_of, phi0, u0, u1, half, mat, label, n=90, lift=0.006):
    """Lens-shaped pale streak lying on the stream at angle phi0 between u0 and u1."""
    vs = []; fs = []
    for j in range(n + 1):
        u = u0 + (u1 - u0) * j / n
        fr = pw_frame_at(frames, u)
        hw = half * math.sin(math.pi * j / n) ** 0.7
        for ph in (phi0 - hw, phi0 + hw):
            vs.append(tuple(pw_section_point(fr, a_of(u) + lift, b_of(u) + lift, ph)))
    for j in range(n):
        fs.append((2 * j, 2 * j + 1, 2 * j + 3, 2 * j + 2))
    return surface_patch(K, name, vs, fs, mat, label)


def pw_tongue(K, name, base, u, height, lean, width, thick, tip_deg, mat, n=26, seg=24):
    """A splash tongue rising from `base` (buried in the puddle) and leaning out along the
    horizontal unit u; flattened section (width across the crown, thick radially); round tip."""
    Z = Vector((0, 0, 1)); B = Vector(base); U = Vector((u[0], u[1], 0)).normalized()
    V = Z.cross(U).normalized()                      # across the crown
    P3 = B + U * lean + Z * height
    a0 = math.radians(84); a1 = math.radians(tip_deg)
    P1 = B + (U * math.cos(a0) + Z * math.sin(a0)) * (height * 0.42)
    P2 = P3 - (U * math.cos(a1) + Z * math.sin(a1)) * (height * 0.36)
    pts, _ = pw_resample(pw_bezier(B, P1, P2, P3, 80), n)
    vs = []; fs = []; rings = []
    for i, c in enumerate(pts):
        s = i / n
        t = (pts[min(i + 1, n)] - pts[max(i - 1, 0)]).normalized()
        Nn = V.cross(t).normalized()
        if i == n:
            rings.append([len(vs)]); vs.append(tuple(c)); continue
        round_ = math.sqrt(max(0.0, 1 - ((s - 0.72) / 0.28) ** 2)) if s > 0.72 else 1.0
        w = width * (1 - 0.30 * s) * round_; th = thick * (1 - 0.25 * s) * round_
        rings.append(list(range(len(vs), len(vs) + seg)))
        vs.extend(tuple(c + V * (w * math.cos(2 * math.pi * k / seg)) + Nn * (th * math.sin(2 * math.pi * k / seg))) for k in range(seg))
    for a, b in zip(rings, rings[1:]):
        for k in range(seg):
            k2 = (k + 1) % seg
            if len(b) == 1:
                fs.append((a[k], a[k2], b[0]))
            else:
                fs.append((a[k], a[k2], b[k2], b[k]))
    fs.append(tuple(reversed(rings[0])))
    ob = pw_smooth(mesh(K, name, vs, fs, mat, False), 70)
    return ob


def pw_coronet(K, name, centre, r_base, height_of, flare, thick, mat, z0=0.03, seg=288, rows=14, lip=7):
    """Splash crown: a thin flared wall round the landing point whose rim is scalloped into
    lobes. Each azimuth carries the same closed wall section (outer face up, round lip,
    inner face down, base across), so the solid is one closed ring. Returns (object, rim)."""
    cx, cy = centre; loop = []
    r_of = r_base if callable(r_base) else (lambda th: r_base)
    for j in range(rows + 1):
        loop.append(('o', j / rows))
    for q in range(1, lip):
        loop.append(('l', q / lip))
    for j in range(rows, -1, -1):
        loop.append(('i', j / rows))
    vs = []; rim = []
    for k in range(seg):
        th = 2 * math.pi * k / seg; h = height_of(th); r_base_k = r_of(th)
        ur = Vector((math.cos(th), math.sin(th), 0))
        for kind, v in loop:
            if kind == 'l':
                a = math.pi * v; rr = r_base_k + flare(1.0, th) + (thick / 2) * math.cos(a); z = z0 + h + (thick / 2) * math.sin(a)
            else:
                rr = r_base_k + flare(v, th) + (thick / 2 if kind == 'o' else -thick / 2); z = z0 + v * h
            vs.append((cx + ur.x * rr, cy + ur.y * rr, z))
        rim.append((cx + ur.x * (r_base_k + flare(1.0, th)), cy + ur.y * (r_base_k + flare(1.0, th)), z0 + h + thick / 2 + 0.004))
    m = len(loop); fs = []
    for k in range(seg):
        k2 = (k + 1) % seg
        for j in range(m):
            j2 = (j + 1) % m
            fs.append((k * m + j, k * m + j2, k2 * m + j2, k2 * m + j))
    return pw_smooth(mesh(K, name, vs, fs, mat, False), 60), rim


def pw_ribbon(K, name, centre, r_of, height_of, flare, thick, mat, d_of, th0, th1, z0=0.03, seg=240, rows=14, lip=7):
    """Open splash ribbon: the crown wall between azimuths th0..th1 only (no back), same
    section as pw_coronet, capped at both ends. Returns (object, rim points left to right)."""
    cx, cy = centre; loop = []
    for j in range(rows + 1):
        loop.append(('o', j / rows))
    for q in range(1, lip):
        loop.append(('l', q / lip))
    for j in range(rows, -1, -1):
        loop.append(('i', j / rows))
    vs = []; rim = []
    for k in range(seg + 1):
        th = th0 + (th1 - th0) * k / seg; h = max(height_of(th), 0.004); rb = r_of(th)
        ur = Vector((math.cos(th), math.sin(th), 0))
        for kind, v in loop:
            if kind == 'l':
                a = math.pi * v; rr = rb + flare(1.0, th) + (thick / 2) * math.cos(a); z = z0 + h + (thick / 2) * math.sin(a)
            else:
                rr = rb + flare(v, th) + (thick / 2 if kind == 'o' else -thick / 2); z = z0 + v * h
            vs.append((cx + ur.x * rr, cy + ur.y * rr, z))
        rim.append((cx + ur.x * (rb + flare(1.0, th)), cy + ur.y * (rb + flare(1.0, th)), z0 + h + thick / 2 + 0.004))
    m = len(loop); fs = []
    for k in range(seg):
        for j in range(m):
            j2 = (j + 1) % m
            fs.append((k * m + j, k * m + j2, (k + 1) * m + j2, (k + 1) * m + j))
    fs.append(tuple(reversed(range(m)))); fs.append(tuple(seg * m + j for j in range(m)))
    return pw_smooth(mesh(K, name, vs, fs, mat, False), 60), rim


def pw_tongue2(K, name, base, lean_vec, height, width, thick, width_axis, tip_deg, mat, n=26, seg=24):
    """Flattened splash tongue whose broad face keeps a given horizontal width axis (so it can
    face the fixed camera while leaning sideways). Round tip; the base is buried."""
    Z = Vector((0, 0, 1)); B = Vector(base); U = Vector((lean_vec[0], lean_vec[1], 0))
    lean = U.length; U = U.normalized(); Wd = Vector(width_axis).normalized()
    P3 = B + U * lean + Z * height
    a0 = math.radians(86); a1 = math.radians(tip_deg)
    P1 = B + (U * math.cos(a0) + Z * math.sin(a0)) * (height * 0.42)
    P2 = P3 - (U * math.cos(a1) + Z * math.sin(a1)) * (height * 0.36)
    pts, _ = pw_resample(pw_bezier(B, P1, P2, P3, 80), n)
    vs = []; fs = []; rings = []
    for i, c in enumerate(pts):
        s = i / n
        t = (pts[min(i + 1, n)] - pts[max(i - 1, 0)]).normalized()
        W = (Wd - t * Wd.dot(t)).normalized(); Nn = W.cross(t).normalized()
        if i == n:
            rings.append([len(vs)]); vs.append(tuple(c)); continue
        round_ = math.sqrt(max(0.0, 1 - ((s - 0.70) / 0.30) ** 2)) if s > 0.70 else 1.0
        w = width * (1 - 0.45 * s) * round_; th = thick * (1 - 0.30 * s) * round_
        rings.append(list(range(len(vs), len(vs) + seg)))
        vs.extend(tuple(c + W * (w * math.cos(2 * math.pi * k / seg)) + Nn * (th * math.sin(2 * math.pi * k / seg))) for k in range(seg))
    for a, b in zip(rings, rings[1:]):
        for k in range(seg):
            k2 = (k + 1) % seg
            if len(b) == 1:
                fs.append((a[k], a[k2], b[0]))
            else:
                fs.append((a[k], a[k2], b[k2], b[k]))
    fs.append(tuple(reversed(rings[0])))
    return pw_smooth(mesh(K, name, vs, fs, mat, False), 70)


def pw_puddle(K, name, centre, rad_of, z_rim, z_mid, mat, rings=16, seg=240):
    """Closed lobed slab on the ground: gently domed top, short side wall, flat bottom."""
    cx, cy = centre; vs = [(cx, cy, z_mid)]; fs = []
    for i in range(1, rings + 1):
        f = i / rings; z = z_rim + (z_mid - z_rim) * (1 - f * f)
        for k in range(seg):
            th = 2 * math.pi * k / seg; r = rad_of(th) * f
            vs.append((cx + r * math.cos(th), cy + r * math.sin(th), z))
    for k in range(seg):
        fs.append((0, 1 + k, 1 + (k + 1) % seg))
    for i in range(1, rings):
        b0 = 1 + (i - 1) * seg; b1 = 1 + i * seg
        for k in range(seg):
            k2 = (k + 1) % seg
            fs.append((b0 + k, b1 + k, b1 + k2, b0 + k2))
    rim = 1 + (rings - 1) * seg; bot = len(vs)
    for k in range(seg):
        th = 2 * math.pi * k / seg; r = rad_of(th)
        vs.append((cx + r * math.cos(th), cy + r * math.sin(th), 0.0))
    for k in range(seg):
        k2 = (k + 1) % seg
        fs.append((rim + k, bot + k, bot + k2, rim + k2))
    fs.append(tuple(bot + k for k in reversed(range(seg))))
    return pw_smooth(mesh(K, name, vs, fs, mat, False), 40)


def pw_puddle_top(centre, rad_of, z_rim, z_mid, f, th):
    r = rad_of(th) * f
    return Vector((centre[0] + r * math.cos(th), centre[1] + r * math.sin(th), z_rim + (z_mid - z_rim) * (1 - f * f)))


def build_pure_water():
    """Pure water v6: review round 1 folded in (reference proportions at a matched body
    diameter; flat water with inset streaks; a smooth oval pool whose crown grows the
    tongues; khaki as a dominant base with a narrow inset stripe; a dark bore; fewer lines).
    Overruled on the approved set's evidence: the reference's dense full-ink screen and an
    8.5 px line tier (approved alternates carry 2.5-3.2 % dots and 12/6 px lines)."""
    setup_icon_rig(); K = Kit(open_collection('ICON_pure_water')); hosts = []
    Hc = PW_HC
    khaki = pw_toon('pw_pipe_khaki', (0.62, 0.52, 0.35), ((0.64, 0.30), (0.70, 0.40), (0.988, 0.50), (9.0, 0.92)))
    bore = pw_flat('pw_pipe_bore', (0.125, 0.105, 0.070))            # one unlit tone (~90), dotted all over
    post_khaki = pw_toon('pw_post_khaki', (0.62, 0.52, 0.35), ((0.70, 0.30), (0.98, 0.50), (9.0, 0.92)))
    khaki_shine = pw_flat('pw_khaki_shine', (0.570, 0.478, 0.322))
    water = pw_flat('pw_water', (0.351, 0.686, 0.686))
    shine = pw_flat('pw_water_shine', (0.60, 0.88, 0.86))
    L_PIPE, L_STREAM, L_POOL, L_POST, L_FOOT = 1, 2, 3, 4, 6
    e = 0.004

    # Pipe: socket mouth, conical reducer inside, body, couplings either side of the post.
    R_HUB, R_BORE, R_BODY, R_IN, R_BAND = 0.705, 0.555, 0.50, 0.40, 0.60
    Y_FRONT, Y_HUB, Y_END = -0.30, 0.20, 2.30
    bands = [(0.95, 1.85)]                           # one coupling over the post, grooved at its middle
    # Owner (v18): "it's ignoring where the flange meets the pipe". A step's face must show
    # and carry ink on both edges. From the fixed camera a flat face turned away (+Y) never
    # shows and a 45 degree shoulder is edge-on (its two edges project onto one curve), so the
    # flange's back and the coupling's back are 30 degree shoulders, which show as a band
    # over the whole upper side. The coupling's front face shows as a crescent inked at both
    # edges, closed by the pipe's own silhouette edges where they pass in front of it.
    SHOULDER = math.tan(math.radians(30))
    SH_HUB = (R_HUB - R_BODY) / SHOULDER; SH_BAND = (R_BAND - R_BODY) / SHOULDER
    prof = [(Y_FRONT, R_BORE), (Y_FRONT, R_HUB), (Y_HUB, R_HUB), (Y_HUB + SH_HUB, R_BODY)]
    for y0, y1 in bands:
        prof += [(y0, R_BODY), (y0, R_BAND), (y1, R_BAND), (y1 + SH_BAND, R_BODY)]
    prof += [(Y_END, R_BODY), (Y_END, R_IN), (0.14, R_IN), (-0.02, R_BORE)]
    pipe = pw_revolve_y(K, 'pipe_shell', prof, khaki); pipe['part_label'] = L_PIPE; hosts.append(pipe.name)
    pipe.data.materials.append(bore)
    me = pipe.data
    occl = me.attributes.new('icon_shade_occlusion', 'FLOAT', 'CORNER')
    normals = [c.vector.copy() for c in me.corner_normals]
    for poly in me.polygons:
        radial = Vector((poly.center.x, 0.0, poly.center.z - Hc))
        if radial.length > 1e-6 and poly.normal.dot(radial.normalized()) < -0.5:
            poly.material_index = 1                  # inward-facing faces are the bore
            for li in poly.loop_indices:
                occl.data[li].value = 1.0            # dots across the whole bore
        elif abs(poly.normal.y) > 0.9 and bands[0][0] - 0.01 < poly.center.y < bands[0][1] + 0.01:
            for li in poly.loop_indices:             # the coupling's ring faces take the barrel's radial
                v = me.vertices[me.loops[li].vertex_index].co   # normal, so tone bands run straight to the ring line
                normals[li] = Vector((v.x, 0.0, v.z - Hc)).normalized()
    me.normals_split_custom_set(normals)
    pw_circle_y(K, 'mouth_outer_rim', Y_FRONT - e, R_HUB + e, L_PIPE)
    pw_circle_y(K, 'mouth_bore_rim', Y_FRONT - e, R_BORE - e, L_PIPE)
    pw_circle_y(K, 'hub_back_rim', Y_HUB + e, R_HUB + e, L_PIPE)
    pw_circle_y(K, 'hub_shoulder_foot', Y_HUB + SH_HUB + e, R_BODY + e, L_PIPE)   # flange meets pipe
    for i, (y0, y1) in enumerate(bands):
        pw_circle_y(K, 'band%d_front' % i, y0 - e, R_BAND + e, L_PIPE)
        pw_circle_y(K, 'band%d_front_foot' % i, y0 - e, R_BODY + e, L_PIPE)      # rib face meets pipe
        pw_circle_y(K, 'band%d_back' % i, y1 + e, R_BAND + e, L_PIPE)
        pw_circle_y(K, 'band%d_back_foot' % i, y1 + SH_BAND + e, R_BODY + e, L_PIPE)
        pw_circle_y(K, 'band%d_groove' % i, (y0 + y1) / 2, R_BAND + e, L_PIPE)
    # The pipe's silhouette edges between the flange and the coupling: where they pass in front
    # of the coupling's face they are interior edges and need ink (elsewhere the outline covers them).
    for nm, ang in (('body_top_edge', 135), ('body_bottom_edge', 315)):
        a = math.radians(ang); r = R_BODY + e
        tagged_line(K, nm, [(r * math.cos(a), Y_HUB + SH_HUB + (bands[0][0] - Y_HUB - SH_HUB) * k / 60, Hc + r * math.sin(a)) for k in range(61)], L_PIPE, 6, False)

    # Post: collar under the pipe, rod with a pill highlight, puck foot.
    pc = (0.0, PW_Y_POST); R_ROD, R_COL, R_FOOT, FOOT_H = 0.125, 0.185, 0.245, 0.13
    Z_COL = Hc - R_BAND - 0.24                       # collar shows 0.24 D below the coupling
    collar = pw_lathe_z(K, 'post_collar', [(0, Z_COL), (R_COL, Z_COL), (R_COL, Hc - 0.40), (0, Hc - 0.40)], post_khaki, pc)
    rod = pw_lathe_z(K, 'post_rod', [(0, 0.10), (R_ROD, 0.10), (R_ROD, Z_COL + 0.04), (0, Z_COL + 0.04)], post_khaki, pc)
    foot = pw_lathe_z(K, 'post_foot', [(0, 0.0), (R_FOOT, 0.0), (R_FOOT, FOOT_H), (0, FOOT_H)], post_khaki, pc)
    collar['part_label'] = L_POST; rod['part_label'] = L_POST; foot['part_label'] = L_FOOT
    hosts += [collar.name, rod.name, foot.name]
    pw_circle_z(K, 'collar_bottom_rim', pc, Z_COL - e, R_COL + e, L_POST)
    pw_circle_z(K, 'foot_top_rim', pc, FOOT_H + e, R_FOOT + e, L_FOOT)
    lit = math.atan2(-0.994, 0.106)                  # the rod's most lit azimuth under the sun
    vs = []; n = 60; z0, z1 = FOOT_H + 0.10, Z_COL - 0.08
    for j in range(n + 1):
        t = j / n; end = min(1.0, min(t, 1 - t) / 0.05)
        hw = math.radians(9.2) * math.sqrt(max(0.0, 1 - (1 - end) ** 2))      # 0.04 D wide
        for a in (lit - hw, lit + hw):
            vs.append((pc[0] + (R_ROD + e) * math.cos(a), pc[1] + (R_ROD + e) * math.sin(a), z0 + (z1 - z0) * t))
    surface_patch(K, 'post_shine', vs, [(2 * j, 2 * j + 1, 2 * j + 3, 2 * j + 2) for j in range(n)], khaki_shine, L_POST)

    # Stream: low in the bore with dark bore above it, level at the lip, vertical at the pool.
    # Level through the socket (a bend inside it sank the stream into the bore wall), then
    # one bend to vertical; the landing moves to 0.9 D out so the bend stays wider than 1.2 b.
    y_land = -1.20; c_lip = 0.175                    # 0.38 D of dark bore above a 0.70 D deep lip section
    P0 = Vector((0, -0.08, Hc - c_lip)); Pm = Vector((0, -0.31, Hc - c_lip)); P3 = Vector((0, y_land, 0.04))
    raw = [P0.lerp(Pm, k / 40) for k in range(40)] + pw_bezier(Pm, Pm + Vector((0, -0.80, 0)), P3 + Vector((0, 0, 1.50)), P3, 400)
    centre, length = pw_resample(raw, 160)
    min_r = pw_min_radius(centre)
    a_of = lambda u: 0.43 + 0.015 * u
    b_of = lambda u: 0.35 + 0.08 * u
    frames = pw_frames(centre)
    stream = pw_clean_water(pw_stream(K, 'stream', frames, a_of, b_of, water))
    stream['part_label'] = L_STREAM; hosts.append(stream.name)
    streaks = [(-78, 0.04, 0.50), (-56, 0.28, 0.78), (-30, 0.08, 0.36), (-22, 0.52, 0.90), (-86, 0.60, 0.94), (-6, 0.20, 0.44)]
    for i, (deg, u0, u1) in enumerate(streaks):
        pw_streak(K, 'streak_%d' % i, frames, a_of, b_of, math.radians(deg), u0, u1, math.radians(5.3), shine, L_STREAM)

    # Pool and ribbon share one label, the stream another, the tongues a third. The tongues
    # fill the gaps between the stream and the ribbon's ends, so the ribbon's W rim always has
    # a different label behind it and is inked across its full width by label boundaries
    # alone (no extra line to double it); the stream stays outlined down to the rim.
    L_WATER = L_POOL; L_TONGUE = 5
    e1 = Vector((1, 1, 0)).normalized(); e2 = Vector((-1, 1, 0)).normalized()   # screen right, screen back
    land = Vector((0.0, y_land, 0.0))
    # Pool: an oval set 0.30 D forward of the landing point, so its far edge stays behind the
    # stream, the ribbon's raised ends and the tongues.
    pc2 = land - e2 * 0.30; pcen = (pc2.x, pc2.y); A, Bm = 1.00, 0.66
    def rad_of(th):
        c = math.cos(th - math.pi / 4); s = math.sin(th - math.pi / 4)
        return 1.0 / math.sqrt((c / A) ** 2 + (s / Bm) ** 2)
    Z_RIM, Z_MID = 0.10, 0.14
    pool = pw_clean_water(pw_puddle(K, 'puddle', pcen, rad_of, Z_RIM, Z_MID, water))
    pool['part_label'] = L_WATER; hosts.append(pool.name)
    for nm, t0, t1 in [('pool_shine_left', 232, 290), ('pool_shine_right', 334, 370)]:
        vs = []; m = 50
        for j in range(m + 1):
            th = math.radians(t0 + (t1 - t0) * j / m); hw = 0.045 * math.sin(math.pi * j / m) ** 0.7
            for f in (0.82 - hw, 0.82 + hw):
                p = pw_puddle_top(pcen, rad_of, Z_RIM, Z_MID, f, th); p.z += 0.006; vs.append(tuple(p))
        surface_patch(K, nm, vs, [(2 * j, 2 * j + 1, 2 * j + 3, 2 * j + 2) for j in range(m)], shine, L_WATER)

    # Ribbon: the front arc of an ellipse 1.56 D across and 1.04 D deep round the landing
    # point. Rim a W (two cusps, a middle bump), rising into side lips that end in rounded
    # lobes; open behind (no basin).
    front = math.radians(315); CR_A, CR_B = 0.78, 0.52; CZ0 = 0.03; THICK = 0.06
    D_LIP, D_END = math.radians(96), math.radians(108)
    def cr_r(th):
        c = math.cos(th - math.pi / 4); s = math.sin(th - math.pi / 4)
        return 1.0 / math.sqrt((c / CR_A) ** 2 + (s / CR_B) ** 2)
    def sd(th):
        return (th - front + math.pi) % (2 * math.pi) - math.pi
    def smooth(e0, e1_, x):
        t = min(1.0, max(0.0, (x - e0) / (e1_ - e0))); return t * t * (3 - 2 * t)
    def ribbon_h(th):
        d = sd(th); ad = abs(d)
        h = 0.18 + 0.15 * (1 + math.cos(5 * d)) / 2 + 0.10 * smooth(math.radians(72), D_LIP, ad)   # cusps under the stream's edges
        if ad > D_LIP:                                  # rounded lobe at each end
            h *= math.sqrt(max(0.0, 1 - ((ad - D_LIP) / (D_END - D_LIP)) ** 2))
        return h
    flare = lambda v, th: 0.05 * v ** 1.6
    rib, rim = pw_ribbon(K, 'crown', (0.0, y_land), cr_r, ribbon_h, flare, THICK, water, sd,
                         front - D_END, front + D_END, z0=CZ0)
    pw_clean_water(rib)['part_label'] = L_WATER
    vs = []; m = 160
    for j in range(m + 1):
        d = math.radians(-94 + 188 * j / m); th = front + d; h = ribbon_h(th)
        ur = Vector((math.cos(th), math.sin(th), 0))
        for dz in (0.085, 0.006):
            v = max(0.0, (h - dz) / h)
            rr = cr_r(th) + flare(v, th) + THICK / 2 + 0.006
            vs.append((ur.x * rr, y_land + ur.y * rr, CZ0 + h - dz))
    surface_patch(K, 'crown_lip_band', vs, [(2 * j, 2 * j + 1, 2 * j + 3, 2 * j + 2) for j in range(m)], shine, L_WATER)

    # Tongues: flattened (5:2), 0.30 D tapering to ~0.12 D with round tips, broad face to the
    # camera, rising just outside the stream behind the ribbon and leaning out sideways so a V
    # of background opens between tongue and stream. Left tall, right shorter.
    tongue_list = [(-0.60, 0.05, 0.84, -0.14, 0.15, 0.06, 72), (0.60, 0.05, 0.58, 0.12, 0.14, 0.055, 74)]
    for i, (xs, bk, h, lean, w, t, tip) in enumerate(tongue_list):
        base = land + e1 * xs + e2 * bk + Vector((0, 0, 0.06))
        tg = pw_clean_water(pw_tongue2(K, 'tongue_%d' % i, tuple(base), tuple(e1 * lean), h, w, t, tuple(e1), tip, water))
        tg['part_label'] = L_TONGUE

    info = contract(K, hosts, 'socket-mouthed pipe on a post pouring a curved stream into an oval pool with a tongued splash crown')
    info['revision'] = PW_REVISION
    info['outline']['component_boundaries'] = True
    info['stipple']['strength'] = 0.38
    info['dimensions'] = {'D': 1.0, 'pipe_centre_height': Hc, 'hub_outer': 2 * R_HUB, 'bore': 2 * R_BORE,
                          'band_outer': 2 * R_BAND, 'pipe_length': Y_END - Y_FRONT, 'post': 2 * R_ROD, 'collar': 2 * R_COL,
                          'foot': 2 * R_FOOT, 'stream_lip': [2 * a_of(0), 2 * b_of(0)], 'stream_land': [2 * a_of(1), 2 * b_of(1)],
                          'dark_bore_above_stream': round(R_BORE - (b_of(0) - c_lip), 3),
                          'stream_length': round(length, 3), 'stream_min_bend_radius': round(min_r, 3),
                          'landing_in_front_of_mouth': round(Y_FRONT - y_land, 3), 'pool_semi_axes': [A, Bm],
                          'ribbon_semi_axes': [CR_A, CR_B], 'tongues': [[xs, h] for xs, bk, h, lean, w, t, tip in tongue_list]}
    assert min_r > 1.2 * b_of(1.0), ('stream bends tighter than its own thickness', min_r)
    return info
