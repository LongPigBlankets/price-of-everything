"""The plastics chair's geometry in plain numpy, shared by the silhouette fit (plastics/fit) and the
Blender kit (plastics_kit.py), so the render is exactly the fitted shape. The chair faces +X.

A monobloc shell swept as ONE band: the left front leg up, a bend back into the left arm, round the
backrest (a superellipse half in plan), along the right arm and down the right front leg. Its section
changes along the way: a plate on the legs, a wide flat band on the arms, a tall thin web round the
back whose top arches up from the arms and whose bottom drops to the seat (opening the arm gaps). A
rolled rim runs along the top of the back and fades into the arm bands. Three slots are cut through
the back, each an outline in (arc length, height) on the web. The seat is a slab whose back edge
follows the web; the back legs are L sections; each front leg carries a fin running back (an L).
"""
import math
import numpy as np

# Fitted to the shipped chair's inked silhouette (plastics/fit: P27c: P27b with the front legs one moulding with the arms); world units.
CG_P = dict(seat_z=0.9595, seat_t=0.05, seat_front=0.597, seat_hw=0.54, arm_z=1.4683, arm_drop=0.04,
            arm_dropR=0.0012, arm_w=0.09, arm_h=0.1684, bend=0.2045, back_top=1.7694, lean=0.309,
            wy=0.4639, wyf=0.4625, xa=-0.0891, rx=0.2927, bexp=3.1331, xf=0.3045,
            top_q=0.4339, q0=0.1312, q1=0.1812, back_t=0.045, rim_w=0.05, rim_h=0.015,
            fx=0.5511, fy=0.4574, leg_w=0.1393, leg_t=0.0653, fin_w=0.1393, btx=-0.2746,
            bty=0.4338, bfx=-0.2734, bfy=0.5219, blw0=0.13, blw1=0.075, s0c=0.4088,
            s0z0=1.0759, s0z1=1.6103, s0hw=0.06, s0tilt=0.0, s0e=2.0, s1c=0.4894,
            s1z0=1.0759, s1z1=1.6103, s1hw=0.0419, s1tilt=0.0, s1e=5.0, s2c=0.5699,
            s2z0=1.0759, s2z1=1.6103, s2hw=0.0419, s2tilt=0.0, s2e=5.0, band_follow=1.0,
            band_h=0.1714, arm_wL=0.12, seat_to_arms=1.0, skirt_d=0.104, armL_off=0.18, bendL=0.2045,
            arm_hL=0.07, seat_hwL=0.4, seat_frontL=0.597, skirt_dL=0.16, legs_to_arms=1.0, rim_qend=0.5,
            pad_r=0.028, drop_far_rear_leg=0.0, blw_top=0.03, seat_rR=0.08, leg_boss=0.0, rim_q_fade=0.36,
            leg_top_q=0.56, rear_corner_front=1.0, rear_wx=0.045, blw_mid=[[0.45, 0.112, 0.045], [0.27, 0.09, 0.045], [0.12, 0.082, 0.04]], rear_wx_foot=0.015, legs_as_posts=1.0,
            leg_prof=[[0.0, 0.075, 0.015], [0.1536, 0.082, 0.04], [0.3456, 0.09, 0.045], [0.576, 0.112, 0.045], [1.28, 0.11, 0.045]], far_back_dx=-0.13, far_back_dy=0.13, front_leg_style='u', front_leg_shell_label=1.0)
CG_QB = 0.5          # Q where the arms meet the back
CG_LEG_PLATE = 0.035  # the back legs' and fins' plate thickness


def cg_smooth(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


def cg_rrect(w, h, r, n=3):
    """A centred rounded rectangle (w along x, h along y), CCW, 4(n+1) points."""
    pts = []
    for cx, cy, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
        for k in range(n + 1):
            a = math.radians(a0 + 90 * k / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return np.array(pts)


def cg_frames(path, n0):
    """Parallel-transported frames (T, N, B) along a polyline, N starting as n0 made square to T."""
    m = len(path)
    T = np.zeros((m, 3))
    for i in range(m):
        d = path[min(i + 1, m - 1)] - path[max(i - 1, 0)]
        T[i] = d / (np.linalg.norm(d) + 1e-12)
    N = np.zeros((m, 3))
    n = np.array(n0, float)
    n = n - T[0] * n.dot(T[0])
    N[0] = n / np.linalg.norm(n)
    for i in range(1, m):
        a, b = T[i - 1], T[i]
        v = np.cross(a, b); c = a.dot(b); n = N[i - 1]
        if np.linalg.norm(v) > 1e-9:
            vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
            n = (np.eye(3) + vx + vx @ vx * (1 / (1 + c))) @ n
        n = n - b * n.dot(b)
        N[i] = n / (np.linalg.norm(n) + 1e-12)
    B = np.cross(T, N)
    B /= np.linalg.norm(B, axis=1)[:, None]
    return T, N, B


def cg_lean(p, P):
    """The backrest's recline: points above the seat, toward the back, pushed outward in plan by up to
    lean at the top (the front of the chair does not move)."""
    p = np.asarray(p, float)
    wz = np.clip((p[..., 2] - P['seat_z']) / (P['back_top'] - P['seat_z']), 0, None)
    wx = cg_smooth((-p[..., 0] - 0.05) / 0.40)
    d = p[..., :2]
    ln = np.linalg.norm(d, axis=-1) + 1e-9
    k = P['lean'] * wz * wx / ln
    out = p.copy()
    out[..., 0] += d[..., 0] * k
    out[..., 1] += d[..., 1] * k
    return out


def cg_u_path(P, n_arm=12, n_back=48):
    """The plan U: left arm (front to back), the back (a superellipse half), right arm (back to front),
    with Q per point: 0 at the back centre, CG_QB where the arms meet the back, 1 at the arm fronts."""
    wy, wyf, xa, rx, xf, e = P['wy'], P['wyf'], P['xa'], P['rx'], P['xf'], P['bexp']
    xfL = P.get('xfL', xf)                          # v10: the near arm's own front (its elbow over the leg)
    pts, qs = [], []
    for k in range(n_arm):
        f = k / n_arm
        pts.append((xfL + (xa - xfL) * f, -(wyf + (wy - wyf) * f))); qs.append(1 - (1 - CG_QB) * f)
    for k in range(n_back + 1):
        t = -math.pi / 2 + math.pi * k / n_back
        c, s = math.cos(t), math.sin(t)
        pts.append((xa - rx * abs(c) ** (2 / e), wy * math.copysign(abs(s) ** (2 / e), s))); qs.append(CG_QB * abs(t) / (math.pi / 2))
    for k in range(1, n_arm + 1):
        f = k / n_arm
        pts.append((xa + (xf - xa) * f, wy + (wyf - wy) * f)); qs.append(CG_QB + (1 - CG_QB) * f)
    return np.array(pts), np.array(qs)


def cg_drop(P, side):
    """How far each arm falls from the back to its front bend (side -1: the -Y arm, +1: the +Y arm; the
    shipped chair's near arm comes down almost to the seat, its far arm stays higher)."""
    return P['arm_drop'] if side < 0 else P.get('arm_dropR', P['arm_drop'])


def cg_zfront(P, side):
    """Each arm's height at its front bend."""
    off = P.get('armL_off', 0.0) if side < 0 else 0.0
    return P['arm_z'] - off - cg_drop(P, side)


def cg_zref(P):
    """The level of the U's centre line (each section is offset from it along N)."""
    return P['arm_z']


def cg_sides(U):
    return np.where(np.arange(len(U)) < len(U) // 2, -1, 1)


def cg_heights(P, Q, U=None):
    """Per U point: the band's bottom and top, and the web's width."""
    side = cg_sides(U) if U is not None else -np.ones(len(Q))
    drop = np.where(side < 0, cg_drop(P, -1), cg_drop(P, 1))
    offL = np.where(side < 0, P.get('armL_off', 0.0), 0.0) * cg_smooth((Q - P.get('offL_q0', 0.25)) / max(1e-3, CG_QB - P.get('offL_q0', 0.25)))
    z_arm = P['arm_z'] - offL - drop * np.clip((Q - CG_QB) / (1 - CG_QB), 0, 1)
    ah = np.where(side < 0, P.get('arm_hL', P['arm_h']), P['arm_h'])
    zt = z_arm + ah / 2 + (P['back_top'] - z_arm - ah / 2) * cg_smooth(1 - Q / P['top_q'])
    if P.get('band_follow', 0):
        # v9: past the back panel's side edge the band keeps its height up the back's side, following the top
        # edge (the shipped window between the back and each arm runs up almost to the back's top)
        bh = np.where(side < 0, P.get('band_hL', P.get('band_h', P['arm_h'])), P.get('band_h', P['arm_h']))
        bh = np.where(Q > CG_QB, ah, bh + (ah - bh) * cg_smooth((Q - P['top_q']) / max(1e-3, CG_QB - P['top_q'])))
        zb = P['seat_z'] - 0.03 + (zt - bh - P['seat_z'] + 0.03) * cg_smooth((Q - P['q0']) / max(1e-3, P['q1'] - P['q0']))
    else:
        zb = P['seat_z'] - 0.03 + (z_arm - ah / 2 - P['seat_z'] + 0.03) * cg_smooth((Q - P['q0']) / max(1e-3, P['q1'] - P['q0']))
    aw = np.where(side < 0, P.get('arm_wL', P['arm_w']), P['arm_w'])
    w = P['back_t'] + (aw - P['back_t']) * cg_smooth((Q - 0.46) / 0.22)
    if P.get('leg_boss', 0) and U is not None:        # v13: a boss round the near rear leg's top (the leg merges into the back)
        d = np.hypot(U[:, 0] - P['btx'], U[:, 1] + P['bty'])
        w = np.maximum(w, np.where(side < 0, P['leg_boss'] * np.exp(-(d / 0.07) ** 2), 0.0))
    return zb, zt, w


def cg_shell_path(P):
    """The sweep in three parts (left leg and bend, the U, right bend and leg), each with its own
    frames: [(path, sections, n0)], plus the U data. The U stays level at arm_z (sloping it tilted the
    frames and the tall back sections crossed); each U section is offset along N instead. The bends sit
    at each arm's front height, so their last rings meet the U's end sections exactly."""
    U, Q = cg_u_path(P)
    zb, zt, wq = cg_heights(P, Q, U)
    zr = cg_zref(P); R = P['bend']; RL = P.get('bendL', R)
    zL, zR = cg_zfront(P, -1), cg_zfront(P, 1)
    left, lsec = [], []
    a0 = np.array([U[0][0], U[0][1], zL]); C = a0 - np.array([0.0, 0.0, RL])
    lf = np.array([P['fx'], -P['fy'], 0.0]); b0 = C + np.array([RL, 0.0, 0.0])
    posts = P.get('legs_as_posts', 0)
    if posts:                                   # v23: the front legs are the shared L posts (cg_legs); the bends end on them
        wtop, wxtop = cg_leg_section(P, 10.0); lt, lw = wxtop, wtop
        if P.get('front_leg_style') == 'u':         # v27: on the square top of the owner's front leg
            lt = lw = (wtop + CG_LEG_PLATE) * 0.9
    else:
        lt, lw = P['leg_t'], P['leg_w']
        for k in range(8):
            left.append(lf + (b0 - lf) * k / 8); lsec.append((lt, lw, 0.0))
    awL = P.get('arm_wL', P['arm_w']); ahL = P.get('arm_hL', P['arm_h'])
    for k in range(10):
        t = math.radians(90 * k / 10); f = k / 10
        left.append(C + np.array([RL * math.cos(t), 0.0, RL * math.sin(t)]))
        lsec.append((lt + (ahL - lt) * f, lw + (awL - lw) * f, 0.0))
    mid, msec = [], []
    for (x, y), a, b, w in zip(U, zb, zt, wq):
        mid.append(np.array([x, y, zr])); msec.append((b - a, w, (a + b) / 2 - zr))
    right, rsec = [], []
    a1 = np.array([U[-1][0], U[-1][1], zR]); rf = np.array([P['fx'], P['fy'], 0.0])
    for k in range(1, 11):
        t = math.radians(90 * k / 10); f = k / 10
        right.append(np.array([a1[0] + R * math.sin(t), a1[1], zR - R * (1 - math.cos(t))]))
        rsec.append((P['arm_h'] + (lt - P['arm_h']) * f, P['arm_w'] + (lw - P['arm_w']) * f, 0.0))
    top_r = right[-1]
    if not posts:
        for k in range(1, 9):
            right.append(top_r + (rf - top_r) * k / 8); rsec.append((lt, lw, 0.0))
    # the right part starts with a copy of the U's last ring (the arm's front end at its own height, N up)
    # so its frames start aligned; cg_shell drops that copy
    parts = [(np.array(left), lsec, (1, 0, 0)), (np.array(mid), msec, (0, 0, 1)),
             (np.concatenate([[a1], right]), [(P['arm_h'], P['arm_w'], 0.0)] + rsec, (0, 0, 1))]
    return parts, U, Q, zb, zt


def cg_rings(path, sec, n0, P, nprof=3, rr=0.016):
    """Swept rings (m points each), with the lean applied."""
    T, N, B = cg_frames(path, n0)
    rings = []
    for p, n, b, (h, w, dz) in zip(path, N, B, sec):
        prof = cg_rrect(w, h, min(rr, w * 0.3, h * 0.3), nprof)
        rings.append(p + b * prof[:, :1] + n * (prof[:, 1:] + dz))
    return cg_lean(np.array(rings), P)


def cg_shell(P):
    """All the shell's rings in order, the index range of the U's rings, and the U data."""
    parts, U, Q, zb, zt = cg_shell_path(P)
    L = cg_rings(*parts[0], P); M = cg_rings(*parts[1], P); R = cg_rings(*parts[2], P)[1:]
    rings = np.concatenate([L, M, R])
    i0 = len(L); i1 = i0 + len(M)
    return rings, i0, i1, U, Q, zb, zt


def cg_rim(P, U, Q, zb, zt, q_end=None):
    """The rolled rim along the top of the back. v9: past the back (Q 0.46 -> q_end) it narrows to just
    inside the band and tucks under its top, so its ends hide in the arm bands (v8's poked out as a stub)."""
    q_end = P.get('rim_qend', 0.56) if q_end is None else q_end
    keep = Q <= q_end
    zr = cg_zref(P); side = cg_sides(U)
    aw = np.where(side < 0, P.get('arm_wL', P['arm_w']), P['arm_w'])
    wband = P['back_t'] + (aw - P['back_t']) * cg_smooth((Q - 0.46) / 0.22)
    f = cg_smooth((Q - 0.46) / max(1e-3, q_end - 0.46))
    wr = P['rim_w'] * (1 - f) + np.minimum(P['rim_w'], wband - 0.006) * f   # never wider than on the back
    fade = 1 - cg_smooth((Q - P.get('rim_q_fade', 0.36)) / max(1e-3, q_end - P.get('rim_q_fade', 0.36)))
    hr = np.minimum(P['rim_h'] * np.maximum(fade, 0.04), (zt - zb) * 0.95)   # v13: melts into the web's top
    wr = wband * 0.98 + (wr - wband * 0.98) * fade
    lift = 0.003 - 0.007 * f
    idx = np.where(keep)[0]
    path = np.array([[U[i][0], U[i][1], zr] for i in idx])
    sec = [(hr[i], wr[i], zt[i] + lift[i] - hr[i] / 2 - zr) for i in idx]
    runs, cur = [], [0]
    for j in range(1, len(idx)):
        if idx[j] != idx[j - 1] + 1:
            runs.append(cur); cur = []
        cur.append(j)
    runs.append(cur)
    out = []
    for r in runs:
        if len(r) >= 2:
            out.append(cg_rings(path[r], [sec[j] for j in r], (0, 0, 1), P))
    if P.get('rim_with_q', 0):
        return out, [Q[idx[r]] for r in runs if len(r) >= 2]
    return out


def cg_arc(U):
    L = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(U, axis=0), axis=1))])
    return L


def cg_on_u(U, L, s):
    """Point and unit tangent on the U polyline at arc length s."""
    s = float(np.clip(s, 0.0, L[-1] - 1e-9))
    i = int(np.searchsorted(L, s, side='right') - 1)
    i = min(max(i, 0), len(U) - 2)
    f = (s - L[i]) / max(L[i + 1] - L[i], 1e-12)
    p = U[i] + (U[i + 1] - U[i]) * f
    t = U[i + 1] - U[i]
    return p, t / (np.linalg.norm(t) + 1e-12)


def cg_slots(P, U, Q, n=28, reach=None):
    """Each slot's outline on the web: (front, back) world point arrays (lean applied), offset by
    reach (default: half the local web width) either side of the web's centre surface, plus the
    slot's arc range (for the fit's layering)."""
    L = cg_arc(U); tot = L[-1]
    # v10: positions measured from the back's centre (Q = 0), scaled by the far half's length, so a
    # shorter near arm does not slide the slots (for a symmetric U this is sc * tot, as before)
    Lc = L[int(np.argmin(Q))]; half = tot - Lc
    out = []
    for k in range(3):
        sc, z0, z1 = P['s%dc' % k], P['s%dz0' % k], P['s%dz1' % k]
        hw, tilt, e = P['s%dhw' % k], P['s%dtilt' % k], P['s%de' % k]
        zc, hh = (z0 + z1) / 2, max(1e-3, (z1 - z0) / 2)
        fr, bk = [], []
        for j in range(n):
            th = 2 * math.pi * j / n
            c, s = math.cos(th), math.sin(th)
            x = hw * math.copysign(abs(c) ** (2 / e), c)
            y = hh * math.copysign(abs(s) ** (2 / e), s)
            sa = Lc + (sc - 0.5) * 2 * half + x + tilt * y
            p, t = cg_on_u(U, L, sa)
            nrm = np.array([-t[1], t[0], 0.0])
            q = np.interp(sa, L, Q)
            wloc = P['back_t'] + (P['arm_w'] - P['back_t']) * float(cg_smooth((q - 0.46) / 0.22))
            d = wloc / 2 if reach is None else reach
            base = np.array([p[0], p[1], zc + y])
            fr.append(base - nrm * d); bk.append(base + nrm * d)
        sc_abs = Lc + (sc - 0.5) * 2 * half
        rng = (sc_abs - hw - abs(tilt) * hh, sc_abs + hw + abs(tilt) * hh)
        out.append((cg_lean(np.array(fr), P), cg_lean(np.array(bk), P), rng))
    return out


def cg_seat(P, U, Q):
    """The seat outline (plan, CCW from the back's -y end): the back edge on the web, straight sides to
    rounded front corners. Returns (pts2d, z_bottom, z_top)."""
    back = U[Q <= CG_QB + 1e-9]
    ysR, ysL = cg_seat_hw(P)
    wy = max(abs(back[:, 1]).max(), 1e-6)
    pts = [(x + 0.005, y * 0.97 * ((ysL if y < 0 else ysR) / wy if P.get('seat_to_arms', 0) else 1.0)) for x, y in back]
    FR = P['seat_front']; FL = P.get('seat_frontL', FR)
    for cx_, cy_, s0, r in ((FR, ysR, 90, P.get('seat_rR', 0.10)), (FL, -ysL, 0, 0.10)):
        cx, cy = cx_ - r, cy_ - r if s0 == 90 else cy_ + r
        for k in range(7):
            a = math.radians(s0 - 90 * k / 6)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return np.array(pts), P['seat_z'] - P['seat_t'], P['seat_z']


def cg_seat_hw(P):
    """The seat's front half-widths (+Y, -Y): v9 at each arm's inner face (the arm bends down into its leg
    outside the seat, as shipped); before v9 one seat_hw for both."""
    if P.get('seat_to_arms', 0):
        return P['wyf'] - P['arm_w'] / 2, P.get('seat_hwL', P['wyf'] - P.get('arm_wL', P['arm_w']) / 2)
    return P['seat_hw'], P['seat_hw']


def cg_skirts(P):
    """v9: the seat's side skirts: a plate under each side of the seat from the back leg to the front
    corner, skirt_d deep. Returns [(sy, verts (8,3), faces)]."""
    out = []
    if not P.get('skirt_d', 0):
        return out
    ysR, ysL = cg_seat_hw(P); zt = P['seat_z'] - P['seat_t'] + 0.004
    for sy, ys in ((-1, ysL), (1, ysR)):
        zb = zt - (P.get('skirt_dL', P['skirt_d']) if sy < 0 else P['skirt_d'])
        x0 = P['btx'] - 0.02
        if sy < 0 and P.get('leg_top_q') and P.get('legs_to_arms', 0):
            # v14: the near rear leg now rises to the arm: the skirt starts at the leg (at the skirt's height)
            legs = cg_back_legs(P)
            if legs:
                vs_ = legs[0][0]; top_c, foot_c = vs_[:6].mean(axis=0), vs_[-6:].mean(axis=0)
                f = (zt - foot_c[2]) / max(top_c[2] - foot_c[2], 1e-6)
                k0 = 5 if P.get('legs_as_posts', 0) else 0          # v23: the fixed vertex order (5: the side flange's back end)
                corner_top, corner_foot = vs_[k0], vs_[-6 + k0]; cx_ = corner_foot[0] + (corner_top[0] - corner_foot[0]) * f
                x0 = cx_ + (0.004 if P.get('rear_corner_front', 0) else CG_LEG_PLATE + 0.004)   # just in front of the leg's front face
        xtop = (P.get('xfL', P['xf']) + P.get('bendL', P['bend'])) if sy < 0 else (P['xf'] + P['bend'])
        x1 = min(P.get('seat_frontL', P['seat_front']) if sy < 0 else P['seat_front'], xtop) + 0.02   # v12: into the front leg
        yo = sy * ys; yi = yo - sy * 0.03                 # v12: flush with the seat's edge (a 4 mm step drew a hairline)
        vs = np.array([(x0, yo, zb), (x1, yo, zb), (x1, yo, zt), (x0, yo, zt), (x0, yi, zb), (x1, yi, zb), (x1, yi, zt), (x0, yi, zt)])
        fs = [(0, 1, 2, 3), (5, 4, 7, 6), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
        out.append((sy, vs, fs))
    return out


def cg_clip(poly, xc, keep_left):
    """Sutherland-Hodgman clip of a closed 2D polygon by the line x = xc."""
    out = []; n = len(poly)
    inside = (lambda p: p[0] <= xc + 1e-12) if keep_left else (lambda p: p[0] >= xc - 1e-12)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        if inside(b):
            if not inside(a):
                t = (xc - a[0]) / (b[0] - a[0]); out.append((xc, a[1] + (b[1] - a[1]) * t))
            out.append(tuple(b))
        elif inside(a):
            t = (xc - a[0]) / (b[0] - a[0]); out.append((xc, a[1] + (b[1] - a[1]) * t))
    return out


def cg_seat_solid(P, U, Q):
    """v7 seat: the outline with the crease points inserted; the top flat back to the crease (x_c), then
    sloping down to the seat's bottom at the front edge (so the front reads as one thin edge, as shipped).
    Returns (outline2d, z_top per point, z_bottom, [top polygons as index lists], crease endpoints)."""
    pts, z0, z1 = cg_seat(P, U, Q)
    ysR, ysL = cg_seat_hw(P); FR = P['seat_front']; FL = P.get('seat_frontL', FR); cd = P.get('crease_d', 0.07)
    # the front line x = F(y): through (FL, -ysL) and (FR, ysR); the crease cd behind it (along x)
    def Fy(y):
        return FL + (FR - FL) * (y + ysL) / max(ysL + ysR, 1e-6)
    d = lambda p: p[0] - (Fy(p[1]) - cd)         # > 0 in front of the crease
    ring = []; n = len(pts)
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]; ring.append(tuple(a))
        da, db = d(a), d(b)
        if da * db < 0:
            t = da / (da - db); ring.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    ring = np.array(ring)
    dd = np.array([d(p) for p in ring])
    zt = z1 - (z1 - z0) * np.clip(dd / max(cd, 1e-6), 0, 1) * 0.98
    on = [i for i in range(len(ring)) if abs(dd[i]) < 1e-9]
    back_poly = [i for i in range(len(ring)) if dd[i] <= 1e-9]
    front_poly = [i for i in range(len(ring)) if dd[i] >= -1e-9]
    ends = [ring[i] for i in on]
    return ring, zt, z0, (back_poly, front_poly), ends


def cg_leg_section(P, z):
    """v23: the legs' shared section at height z above the floor: (w, the dotted front flange across Y; wx, the
    lit side flange back along X). The owner: all four legs one shape, the near back leg's (v22: straight to
    the knee, tapered beside the bottle's cap, the lit flange closing at the foot), set by absolute height."""
    prof = P['leg_prof']
    if z <= prof[0][0]:
        return prof[0][1], prof[0][2]
    for (z0, w0, x0), (z1, w1, x1) in zip(prof, prof[1:]):
        if z <= z1:
            f = (z - z0) / max(z1 - z0, 1e-9); return w0 + (w1 - w0) * f, x0 + (x1 - x0) * f
    return prof[-1][1], prof[-1][2]


def cg_leg_L(P, foot, top, sy, rot=0.0):
    """v23: one leg, the shared L swept straight from its foot corner to its top corner. The corner is the
    leg's front outer edge: the front flange (w across Y, facing +X) runs inward, the side flange (wx back
    along X) faces outward. Rings top first, then down through the profile's breakpoints to the foot; each
    ring in a fixed order: 0 the corner, 1 the front flange's inner front edge, 2 its inner back edge, 3 the
    inside corner, 4 the side flange's inner back edge, 5 its outer back edge."""
    t = CG_LEG_PLATE; zt_ = float(top[2])
    zs = [zt_] + [z for z, _, _ in reversed(P['leg_prof']) if 1e-6 < z < zt_ - 1e-6] + [0.0]
    rings = []
    for z in zs:
        c = foot + (top - foot) * (z / zt_); w, wx = cg_leg_section(P, z); th = min(t, w)
        L = [(0, 0), (0, -sy * w), (-th, -sy * w), (-th, -sy * th), (-wx, -sy * th), (-wx, 0)]
        if rot:                                   # v26: turned about its footprint's centre (the near leg anticlockwise)
            a = math.radians(-sy * rot); ca, sa = math.cos(a), math.sin(a); mx, my = -wx / 2, -sy * w / 2
            L = [(mx + (dx - mx) * ca - (dy - my) * sa, my + (dx - mx) * sa + (dy - my) * ca) for dx, dy in L]
        rings.append([c + np.array([dx, dy, 0.0]) for dx, dy in L])
    n = 6; nr = len(rings)
    faces = [tuple(range(n)), tuple((nr - 1) * n + k for k in range(n))]
    for r in range(nr - 1):
        faces += [(r * n + k, r * n + (k + 1) % n, (r + 1) * n + (k + 1) % n, (r + 1) * n + k) for k in range(n)]
    if sy > 0:                                          # keep the faces outward on the mirrored side
        faces = [tuple(reversed(f)) for f in faces]
    return np.array([v for ring in rings for v in ring]), faces


def cg_legs(P):
    """v23: all four legs, the shared L post (cg_leg_L) from each foot up to where it meets the chair: the back
    legs into their arms' undersides (the U point at leg_top_q on each side, centred on the band, leaned with
    the back), the front legs into their arm bends' lower ends (the bend's last section is the post's top
    footprint). Returns [dict(name, sy, kind, verts, faces)] with the near back leg first."""
    U, Q = cg_u_path(P); zb_, zt_, _ = cg_heights(P, Q, U); sides = cg_sides(U); out = []
    for kind in (('back',) if P.get('front_leg_style') == 'u' else ('back', 'front')):   # v27: front legs in cg_front_leg_u
        for sy in (-1, 1):
            if kind == 'back':
                cand = np.where(sides == sy)[0]; j = int(cand[np.argmin(np.abs(Q[cand] - P['leg_top_q']))])
                w0, wx0 = cg_leg_section(P, zb_[j] + 0.03)
                top = cg_lean(np.array([U[j][0] - wx0 / 2, U[j][1] + sy * w0 / 2, zb_[j] + 0.03]), P)
                foot = np.array([P['bfx'] + (P.get('far_back_dx', 0.0) if sy > 0 else 0.0),
                                 sy * P['bfy'] + (P.get('far_back_dy', 0.0) if sy > 0 else 0.0), 0.0])
                # v25: the far back foot splays back and out by the same amount: on screen that moves it straight up,
                # behind the seat (review v23: its stub below the seat read as a hook), and the leg stays parallel to the
                # near back leg on screen (review v24: straight back tilted it to 14 degrees against 8)
            else:
                if sy < 0:
                    RL = P.get('bendL', P['bend']); p = np.array([U[0][0] + RL, U[0][1], cg_zfront(P, -1) - RL])
                else:
                    p = np.array([U[-1][0] + P['bend'], U[-1][1], cg_zfront(P, 1) - P['bend']])
                w0, wx0 = cg_leg_section(P, p[2])
                top = p + np.array([wx0 / 2, sy * w0 / 2, 0.01])
                wf, wxf = cg_leg_section(P, 0.0)
                foot = np.array([P['fx'] + wxf / 2, sy * (P['fy'] + wf / 2), 0.0])
            vs, fs = cg_leg_L(P, foot, top, sy, P.get('front_leg_rot', 0.0) if kind == 'front' else 0.0)
            out.append(dict(name='%s_leg_%s' % (kind, 'left' if sy < 0 else 'right'), sy=sy, kind=kind, verts=vs, faces=fs))
    return out


def cg_front_leg_u(P, sy):
    """v27 (owner: "two very tall rectangles at 90 degrees and a quarter circle at the bottom. This quarter circle's
    radius is a bit larger than the short side of the two rectangles. Then the quarter circle merges into a thin
    connecting band at 90 degree angle with the rightmost rectangle and follows it until near the seat where it
    curves out and further to the right"): the front leg, seen into its inside corner Q (concave from the camera).
    Local offsets (dx along +X, dy) map to the world as x = Q.x + dx, y = Q.y - sy * dy (dy > 0 is away from the
    viewer on the near leg). The left plate runs from Q to dy = -s, the right plate from Q to dx = s, both s wide
    (the legs' shared width profile) and CG_LEG_PLATE thick; a quarter-circle foot pad in their corner, radius
    front_foot_r * s; a thin band at the right plate's free end, square to it, reaching bw0 past the plate's back and
    flaring along a quarter circle to meet the seat's underside. Returns [(name, verts, faces)]."""
    th = CG_LEG_PLATE; tb = P.get('front_band_t', 0.012); bw0 = P.get('front_band_w', 0.03); Rb = P.get('front_band_r', 0.1)
    U, Q = cg_u_path(P)
    if sy < 0:
        RL = P.get('bendL', P['bend']); top = np.array([U[0][0] + RL, U[0][1], cg_zfront(P, -1) - RL])
    else:
        top = np.array([U[-1][0] + P['bend'], U[-1][1], cg_zfront(P, 1) - P['bend']])
    foot = np.array([P['fx'], sy * P['fy'], 0.0]); zt = float(top[2])
    def corner(z):                                  # the L's footprint (dx -th..s, dy -s..th) centred on the leg's line
        s_ = cg_leg_section(P, z)[0]; c = foot + (top - foot) * (z / zt)
        return np.array([c[0] - (s_ - th) / 2, c[1] + sy * (th - s_) / 2]), s_
    def W(q, dx, dy, z):
        return np.array([q[0] + dx, q[1] - sy * dy, z])
    def prism(rings):
        n = len(rings[0]); nr = len(rings)
        fs = [tuple(range(n)), tuple((nr - 1) * n + k for k in range(n))]
        for r_ in range(nr - 1):
            fs += [(r_ * n + k, r_ * n + (k + 1) % n, (r_ + 1) * n + (k + 1) % n, (r_ + 1) * n + k) for k in range(n)]
        return np.array([v for ring in rings for v in ring]), fs
    nm = 'left' if sy < 0 else 'right'; out = []
    zs = [zt] + [z for z, _, _ in reversed(P['leg_prof']) if 1e-6 < z < zt - 1e-6] + [0.0]
    rings = []
    for z in zs:
        q, s_ = corner(z)
        rings.append([W(q, dx, dy, z) for dx, dy in [(-th, th), (s_, th), (s_, 0.0), (0.0, 0.0), (0.0, -s_), (-th, -s_)]])
    out.append(('front_leg_' + nm,) + prism(rings))
    q0, s0 = corner(0.0); r = P.get('front_foot_r', 1.1) * s0; tf = P.get('front_foot_t', 0.022)
    ov = 0.004                                      # a hair into both plates, so the pad is joined to them
    arc = [(-ov, ov)] + [(-ov + r * math.cos(a), ov - r * math.sin(a)) for a in np.radians(np.linspace(0, 90, 13))]
    out.append(('front_foot_' + nm,) + prism([[W(q0, dx, dy, z) for dx, dy in arc] for z in (0.0, tf)]))
    zc = P['seat_z'] - P['seat_t'] - Rb; ztop = P['seat_z'] - P['seat_t'] + 0.004
    bz = sorted(set([0.0] + [float(z) for z in np.linspace(0, zc, 6)] + [float(zc + Rb * math.sin(a)) for a in np.radians(np.linspace(0, 90, 9))] + [ztop]), reverse=True)
    brings = []
    for z in bz:
        q, s_ = corner(z); u = min(1.0, max(0.0, (z - zc) / Rb)); w_ = th + bw0 + Rb * (1 - math.sqrt(max(0.0, 1 - u * u)))
        brings.append([W(q, dx, dy, z) for dx, dy in [(s_, 0.0), (s_ + tb, 0.0), (s_ + tb, w_), (s_, w_)]])
    out.append(('front_band_' + nm,) + prism(brings))
    return out


def cg_back_legs(P):
    """Back legs: L sections (the corner outward and back), tapering from blw0 at the top to blw1 at the
    foot. Returns [(verts (12,3), faces)]. v12: with legs_to_arms the near leg's top is a thin post centred
    on the band above it (it ends inside the band); drop_far_rear_leg leaves the far leg out (it showed
    only as a knob under the seat front, the shipped art shows none)."""
    if P.get('legs_as_posts', 0):
        return [(d['verts'], d['faces']) for d in cg_legs(P) if d['kind'] == 'back']
    t = CG_LEG_PLATE; out = []
    for sy in (-1, 1):
        if sy > 0 and P.get('drop_far_rear_leg', 0):
            continue
        sx = 1 if (sy < 0 and P.get('rear_corner_front', 0)) else -1   # v19: corner at the front (its shade face shows)
        foot = np.array([P['bfx'], sy * P['bfy'], 0.0])
        w0 = P['blw0']
        if P.get('legs_to_arms', 0) and sy < 0:
            U, Q = cg_u_path(P); zb_, zt_, _ = cg_heights(P, Q, U)
            if P.get('leg_top_q'):                    # v14: up into the near arm's underside, as shipped
                cand = np.where(cg_sides(U) < 0)[0]; j = int(cand[np.argmin(np.abs(Q[cand] - P['leg_top_q']))])
            else:
                j = int(np.argmin(np.hypot(U[:, 0] - P['btx'], U[:, 1] - sy * P['bty'])))
            w0 = P.get('blw_top', 0.03) if not (P.get('leg_boss', 0) or P.get('leg_top_q')) else min(P['blw0'], (P['leg_boss'] * 0.8) if P.get('leg_boss', 0) else 0.11)
            # the L's corner so that its footprint's centre sits on the band's centre line
            wx_c = (P.get('rear_wx') or w0) if sx > 0 else w0
            top = np.array([U[j][0] - sx * wx_c / 2, U[j][1] + w0 / 2 * sy, zb_[j] + 0.03])   # v17: centred on the band
            top = cg_lean(top, P)                     # the band above is reclined with the back: follow it
        else:
            top = np.array([P['btx'], sy * P['bty'], P['seat_z'] - 0.04])
        tt = min(t, w0)
        wx = P.get('rear_wx', None) if sx > 0 else None   # v20: the lit flange (along X) short: a slim channel, as shipped
        def ell(w, th, wx_=None):
            wx_ = w if wx_ is None else wx_
            L = [(0, 0), (0, -sy * w), (-sx * th, -sy * w), (-sx * th, -sy * th), (-sx * wx_, -sy * th), (-sx * wx_, 0)]
            return L[::-1] if sx * sy < 0 else L
        A = [top + np.array([dx, dy, 0.0]) for dx, dy in ell(w0, tt, wx)]
        wx_f = P.get('rear_wx_foot', wx) if wx is not None else None      # v22: the lit flange closes at the foot (review v21b)
        Bf = [foot + np.array([dx, dy, 0.0]) for dx, dy in ell(P['blw1'], t, wx_f)]
        rings = [A]
        for f, w_, wxm in (P.get('blw_mid', []) if sy < 0 else []):
            # v22: rings between: v20b's width down to the knee, the taper only beside the bottle's cap (review v21b)
            c = foot + (top - foot) * f; th_ = t + (tt - t) * f
            rings.append([c + np.array([dx, dy, 0.0]) for dx, dy in ell(w_, th_, wxm if wx is not None else None)])
        rings.append(Bf)
        n = 6; nr = len(rings)
        faces = [tuple(range(n)), tuple((nr - 1) * n + k for k in range(n))]
        for r in range(nr - 1):
            faces += [(r * n + k, r * n + (k + 1) % n, (r + 1) * n + (k + 1) % n, (r + 1) * n + k) for k in range(n)]
        out.append((np.array([v for ring in rings for v in ring]), faces))
    return out


def cg_foot_pads(P):
    """v12: the near rear foot's hook (as shipped: a small tab curled up beside the leg's outer foot), as
    a bent strip: [(sy, points (n,3) of its centre line, width, thickness)]."""
    if not P.get('pad_r', 0):
        return []
    r = P['pad_r']; wx = P.get('rear_wx') or P['blw1']; out = []
    if P.get('legs_as_posts', 0):                     # v23: every leg's foot (the legs are one shape)
        feet = [(d['sy'], d['verts'][-6]) for d in cg_legs(P)]
    else:
        feet = [(-1, np.array([P['bfx'], -P['bfy'], 0.0]))]
    for sy, corner in feet:
        base = corner + np.array([-wx * 0.5, -sy * 0.004, 0.0])
        pts = []
        for k in range(9):
            a = math.pi * k / 8 * 0.6                  # v21: a small tuck, not a cane handle (review v20b)
            pts.append(base + np.array([0.0, sy * r * math.sin(a), r * (1 - math.cos(a)) + 0.012]))
        out.append((sy, np.array(pts), 0.05, 0.024))
    return out


def cg_fins(P):
    """Front-leg fins: a plate along each front leg's outer edge, running back from the leg plate's
    back face (the legs' L section). Returns [(sy, verts (8,3), faces)]."""
    out = []
    if P.get('legs_as_posts', 0):                     # v23: the front legs are the shared L posts, no fins
        return out
    R = P['bend']
    for sy in (-1, 1):
        foot = np.array([P['fx'], sy * P['fy'], 0.0])
        Rs = P.get('bendL', R) if sy < 0 else R
        top = np.array([(P.get('xfL', P['xf']) if sy < 0 else P['xf']) + Rs, sy * P['wyf'], cg_zfront(P, sy) - Rs])
        z1 = P['seat_z'] - P['seat_t'] - 0.01; fw, ft = P['fin_w'], CG_LEG_PLATE
        corners = []
        for z in (0.0, z1):
            c = foot + (top - foot) * (z / top[2])
            xo = c[0] - P['leg_t'] / 2; yo = c[1] + sy * P['leg_w'] / 2; xf_ = c[0] + P['leg_t'] / 2 - 0.002
            corners.append([(xf_, yo, z), (xo - fw, yo, z), (xo - fw, yo - sy * ft, z), (xf_, yo - sy * ft, z)])
        vs = np.array(corners[0] + corners[1])
        fs = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
        out.append((sy, vs, fs))
    return out
