"""Wellington geometry in numpy, shared by the region fit (fit/boot_fit2.py) and the kit (rubber_kit.rb_boot).

A boot, in its own frame (x toward the toe, y to its left, z up; the shaft's axis at x = y = 0):
- the upper: horizontal sections lofted from the sole's top (h_sole) to the cuff's foot (top_z - band_h).
  Above the ankle (z_ank) a section is the shaft's superellipse (A, B: front/back and side semi-axes,
  tapering from the ankle to the top). Below it the section grows into the foot: its front reaches out to
  L_toe along the instep profile f(t) = (1 - t^m)^(1/n) (t = 0 at the sole's top, 1 at the ankle: m > 1
  keeps the toe's front upright, n < 1 bends the instep smoothly into the shin); its back grows by heel;
  its sides to W_foot. The section is an egg: separate front and back semi-axes.
- the seam: the line where the foot's panel meets the shaft, z_s(theta) = seam_mid + seam_amp cos(2 theta)
  + seam_fb cos(theta) round the section (theta = 0 at the toe).
- the cuff: a band band_h tall round the top, band_out proud of the shaft; its top face a ring ring_w wide
  round the dark opening.
- the sole: a midsole (h_mid tall, welt proud of the upper's foot) on an outsole (h_out tall, out_in in
  from the midsole) with the arch cut out of the outsole between local x = arch0 and arch1.
"""
import math
import numpy as np

BOOT_G = dict(top_z=0.80, band_h=0.05, band_out=0.006, ring_w=0.018,
              A_t=0.170, B_t=0.108, A_a=0.150, B_a=0.095, p_sh=2.0,
              z_ank=0.30, L_toe=0.42, heel=0.02, W_foot=0.105, wk=0.10, m=2.5, n=0.6, p_ft=2.3,
              seam_mid=0.23, seam_amp=0.05, seam_fb=0.02,
              h_out=0.022, h_mid=0.048, welt=0.010, out_in=0.004, arch0=-0.02, arch1=0.10,
              yaw=12.0)


def bg_frame(G, cx, cy):
    yw = math.radians(G['yaw']); u = np.array([math.cos(yw), math.sin(yw)]); v = np.array([-math.sin(yw), math.cos(yw)])
    def world(x, y, z):
        x = np.asarray(x, float); y = np.asarray(y, float)
        return np.stack([cx + x * u[0] + y * v[0], cy + x * u[1] + y * v[1], np.broadcast_to(np.asarray(z, float), x.shape)], -1)
    return world


def bg_h_sole(G):
    return G['h_out'] + G['h_mid']


def bg_axes(G, z):
    """The upper's section at height z: (front, back, side) semi-axes, the exponent, the foot factor f."""
    hs = bg_h_sole(G); zt = G['top_z'] - G['band_h']
    if z >= G['z_ank']:
        s = min(1.0, (z - G['z_ank']) / max(zt - G['z_ank'], 1e-6))
        A = G['A_a'] + (G['A_t'] - G['A_a']) * s; B = G['B_a'] + (G['B_t'] - G['B_a']) * s
        return A, A, B, G['p_sh'], 0.0
    t = min(1.0, max(0.0, (z - hs) / max(G['z_ank'] - hs, 1e-6)))
    f = max(0.0, 1.0 - t ** G['m']) ** (1.0 / G['n'])
    F = G['A_a'] + (G['L_toe'] - G['A_a']) * f; K = G['A_a'] + G['heel'] * f
    W = G['B_a'] + (G['W_foot'] - G['B_a']) * f; p = G['p_sh'] + (G['p_ft'] - G['p_sh']) * f
    return F, K, W, p, f


def bg_section(G, z, cols=64, grow=0.0):
    """Local (x, y) points of the upper's section at z (theta = 2 pi k / cols from the toe), grown outward by grow."""
    F, K, W, p, f = bg_axes(G, z)
    th = 2 * np.pi * np.arange(cols) / cols; c, s = np.cos(th), np.sin(th)
    ex = np.sign(c) * np.abs(c) ** (2 / p); ey = np.sign(s) * np.abs(s) ** (2 / p)
    x = np.where(c > 0, F + grow, K + grow) * ex
    wid = (W + grow) * (1 + G['wk'] * f * np.clip(x / max(F, 1e-6), -1, 1))
    return x, wid * ey, th


def bg_levels(G, rows=40):
    hs = bg_h_sole(G); zt = G['top_z'] - G['band_h']; za = min(max(G['z_ank'], hs + 0.02), zt - 0.02)
    lo = hs + (za - hs) * (1 - np.cos(np.linspace(0, np.pi / 2, rows // 2 + 1)))       # dense near the sole
    hi = np.linspace(za, zt, rows // 2 + 1)[1:]
    return np.concatenate([lo, hi])


def bg_seam_z(G, th):
    if 'seam_sh' in G:
        # v11 (review v10: the risers leaned ~12 px with hard top corners; the shipped ones stand near vertical
        # under a ~15 px shoulder): level across the instep, a rounded shoulder (seam_sh degrees, seam_hs deep),
        # a steep riser (seam_rw degrees), a small rounding (seam_bw degrees, seam_hb) into the side's level
        a = np.abs(np.degrees(np.angle(np.exp(1j * np.asarray(th, float)))))
        hi, lo = G['seam_hi'], G['seam_lo']; a1 = G['seam_tc'] - G['seam_sh'] - G['seam_rw'] / 2
        a2 = a1 + G['seam_sh']; a3 = a2 + G['seam_rw']; a4 = a3 + G['seam_bw']
        hs, hb = G['seam_hs'], G['seam_hb']
        u = np.clip((a - a1) / G['seam_sh'], 0, 1); z_sh = hi - hs * (1 - np.sqrt(np.clip(1 - u * u, 0, 1)))
        v = np.clip((a - a2) / G['seam_rw'], 0, 1); z_r = (hi - hs) + ((lo + hb) - (hi - hs)) * v
        w = np.clip((a4 - a) / G['seam_bw'], 0, 1); z_b = lo + hb * (1 - np.sqrt(np.clip(1 - w * w, 0, 1)))
        return np.where(a <= a2, z_sh, np.where(a <= a3, z_r, z_b))
    if 'seam_hi' in G:
        # v10: the shipped seam read off the ink (fit/seam_theta_z_*.npy): level across the instep (seam_hi),
        # a steep drop seam_tc degrees round from the toe (seam_w wide), level along the sides (seam_lo)
        a = np.abs(np.degrees(np.angle(np.exp(1j * np.asarray(th, float)))))
        u = np.clip((G['seam_tc'] + G['seam_w'] / 2 - a) / G['seam_w'], 0, 1); u = u * u * (3 - 2 * u)
        return G['seam_lo'] + (G['seam_hi'] - G['seam_lo']) * u
    return G['seam_mid'] + G['seam_amp'] * np.cos(2 * th) + G['seam_fb'] * np.cos(th)


def bg_sole_outline(G, cols=64, grow=0.0):
    x, y, th = bg_section(G, bg_h_sole(G), cols, grow=G['welt'] + grow)
    return x, y, th


def bg_parts(G, cx, cy, rows=40, cols=64):
    """Quads as (label, 4x3 world points) for the region fit's painter: 'upper' quads carry 'shaft'/'foot' by the
    seam; 'band', 'midsole', 'outsole' (side walls), 'welt' (the midsole's top ledge), and the top: 'ring', 'opening'."""
    W = bg_frame(G, cx, cy); out = []
    zs = bg_levels(G, rows)
    secs = [bg_section(G, z, cols) for z in zs]
    for j in range(len(zs) - 1):
        (x0, y0, th), (x1, y1, _) = secs[j], secs[j + 1]
        p0 = W(x0, y0, zs[j]); p1 = W(x1, y1, zs[j + 1]); zm = (zs[j] + zs[j + 1]) / 2
        for k in range(cols):
            k2 = (k + 1) % cols; thm = (th[k] + (th[k2] if k2 else 2 * np.pi)) / 2
            lab = 'shaft' if zm > bg_seam_z(G, thm) else 'foot'
            out.append((lab, np.array([p0[k], p0[k2], p1[k2], p1[k]])))
    # the cuff band
    zt = G['top_z']; zb = zt - G['band_h']
    xb, yb, _ = bg_section(G, zb, cols, grow=G['band_out']); pb0 = W(xb, yb, zb); pb1 = W(xb, yb, zt)
    for k in range(cols):
        k2 = (k + 1) % cols; out.append(('band', np.array([pb0[k], pb0[k2], pb1[k2], pb1[k]])))
    # the sole: midsole walls, the welt ledge, the outsole walls (arch cut)
    hs = bg_h_sole(G); ho = G['h_out']
    xs, ys, ths = bg_sole_outline(G, cols); m0 = W(xs, ys, ho); m1 = W(xs, ys, hs)
    xu, yu, _ = secs[0]; u0 = W(xu, yu, hs)
    for k in range(cols):
        k2 = (k + 1) % cols
        out.append(('midsole', np.array([m0[k], m0[k2], m1[k2], m1[k]])))
        out.append(('welt', np.array([m1[k], m1[k2], u0[k2], u0[k]])))
    xo, yo, _ = bg_sole_outline(G, cols, grow=-G['out_in'])
    for k in range(cols):
        k2 = (k + 1) % cols; xm = (xo[k] + xo[k2]) / 2
        if G['arch0'] < xm < G['arch1']:
            continue
        a0 = W(xo[[k, k2]], yo[[k, k2]], 0.0); a1 = W(xo[[k, k2]], yo[[k, k2]], ho)
        out.append(('outsole', np.array([a0[0], a0[1], a1[1], a1[0]])))
    top = []
    xr, yr, _ = bg_section(G, zb, cols, grow=G['band_out']); top.append(('ring', W(xr, yr, zt)))
    xi, yi, _ = bg_section(G, zb, cols, grow=G['band_out'] - G['ring_w']); top.append(('opening', W(xi, yi, zt)))
    return out, top
