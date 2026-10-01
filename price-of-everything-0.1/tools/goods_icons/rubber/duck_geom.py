"""Rubber duck geometry in numpy, shared by the region fit (fit/duck_fit2.py) and the kit (rubber_kit.rb_duck).

The duck's frame: x toward the beak, y to its left, z up, the base on the ground; every size is scaled by s
and turned yaw degrees about z at (x, y).
- body: a sphere with separate front and back radii (rxf, rxb), ry, rz; behind the middle it lifts into the
  tail (tail, sharpened by tp, pinched by tw); flattened underneath at fb * rz (it stands on that).
- head: a sphere (hr, squashed to hsz in z) at (hx, 0, hz).
- bill: a flattened ellipsoid (krx, kry, krz) at (kx, 0, kz), wider toward its tip (kw) and upturned (kup);
  a lower mandible under it (the mouth line between the two).
- eyes: dark ellipses on the head at azimuth +-eye_az from the beak and elevation eye_el.
"""
import math
import numpy as np

DUCK_G = dict(x=1.311, y=-0.017, yaw=42.0, s=0.916,
              rxf=0.26, rxb=0.26, ry=0.22, rz=0.18, tail=0.27, tp=2.0, tw=0.35, fb=0.8,
              hx=0.09, hz=0.42, hr=0.141, hsz=1.0,
              kx=0.24, kz=0.37, krx=0.12, kry=0.075, krz=0.03, kup=0.02, kw=0.3,
              eye_az=38.0, eye_el=18.0, eye_r=0.03)


def dg_grid(nu=48, nv=24):
    u = np.linspace(0, 2 * np.pi, nu, endpoint=False); v = np.linspace(-np.pi / 2, np.pi / 2, nv)
    U, V = np.meshgrid(u, v)
    return np.cos(V) * np.cos(U), np.cos(V) * np.sin(U), np.sin(V)


def dg_place(D):
    c, s = math.cos(math.radians(D['yaw'])), math.sin(math.radians(D['yaw'])); O = np.array([D['x'], D['y'], 0.0]); k = D['s']
    def place(X, Y, Z):
        return np.stack([X * c - Y * s, X * s + Y * c, Z], -1) * k + O
    return place


def dg_body_local(D, GX, GY, GZ):
    X = GX * np.where(GX > 0, D['rxf'], D['rxb']); Y = GY * D['ry']; Z = GZ * D['rz']
    tx0 = D.get('tx0', 0.0)                       # v13: where the tail's lift starts (behind it the back rises into the tail)
    f = np.where(X < tx0, (np.clip((tx0 - X) / (D['rxb'] + tx0), 0, 1)) ** D['tp'], 0.0)
    Z = Z + D['tail'] * f * (0.5 + 0.5 * np.maximum(0, GZ)); Y = Y * (1 - D['tw'] * f)
    if D.get('dip', 0):                          # v11: the back dips behind the head (review v10: level hump)
        Z = Z - D['dip'] * np.exp(-((X - D['dip_x']) / D['dip_w']) ** 2) * np.maximum(0, GZ) ** 0.7
    if D.get('chest', 0):                        # v11: the chest rises under the head (hides the head's shaded underside)
        Z = Z + D['chest'] * np.exp(-((X - D['chest_x']) / D['chest_w']) ** 2) * np.maximum(0, GZ) ** 0.7
    Z = np.maximum(Z, -D['rz'] * D['fb']) + D['rz'] * D['fb']
    return X, Y, Z


def dg_head_local(D, GX, GY, GZ):
    return D['hx'] + GX * D['hr'] * D.get('hsx', 1.0), GY * D['hr'], D['hz'] + GZ * D['hr'] * D['hsz']


def dg_bill_centre(D):
    """The bill's centre: kd head radii forward of the head's centre and kzr head radii above it (it moves with
    the head), or the absolute (kx, kz) of older fits."""
    if 'kd' in D:
        return D['hx'] + D['kd'] * D['hr'] * D.get('hsx', 1.0), D['hz'] + D['kzr'] * D['hr']
    return D['kx'], D['kz']


def dg_bill_local(D, GX, GY, GZ, lower=False):
    kx, kz = dg_bill_centre(D); D = dict(D, kx=kx, kz=kz)
    if lower:                                    # the lower mandible: shorter, narrower, under the upper
        t = np.clip(GX, -1, 1)
        X = D['kx'] - 0.12 * D['krx'] + GX * D['krx'] * D.get('klow_len', 0.82)
        Y = GY * D['kry'] * 0.86 * (1 + D['kw'] * 0.8 * t)
        Z = D['kz'] - D['krz'] * 1.05 + GZ * D['krz'] * D.get('klow_h', 0.75)
        X, Z = dg_pitch(dict(D, kp=D.get('kp', 0.0) * D.get('klow_pitch', 1.0)), X, Z)   # v12: the lower lip stays flat
        return X, Y, Z
    t = np.clip(GX, -1, 1)
    X = D['kx'] + GX * D['krx']; Y = GY * D['kry'] * (1 + D['kw'] * t)
    taper = 1 - D.get('ktaper', 0.0) * np.maximum(0, t) ** 1.5       # v12: the upper mandible tapers to its tip,
    taper = np.where(GZ > 0, taper, 1.0)                              # its top coming down, its underside (the mouth) straight
    Z = D['kz'] + GZ * D['krz'] * taper + D['kup'] * np.maximum(0, t) ** 2
    X, Z = dg_pitch(D, X, Z)
    return X, Y, Z


def dg_pitch(D, X, Z):
    """The bill tipped up kp degrees about its base (the back of the upper mandible)."""
    kp = math.radians(D.get('kp', 0.0)); bx = D['kx'] - D['krx']
    c, s = math.cos(kp), math.sin(kp); dx, dz = X - bx, Z - D['kz']
    return bx + dx * c - dz * s, D['kz'] + dx * s + dz * c


def dg_parts(D, nu=48, nv=24):
    """[(name, grid (nv, nu, 3) world, centre world)] for the body, head, bill and lower mandible."""
    GX, GY, GZ = dg_grid(nu, nv); place = dg_place(D); out = []
    X, Y, Z = dg_body_local(D, GX, GY, GZ); out.append(('body', place(X, Y, Z), place(0.0, 0.0, D['rz'] * D['fb'])))
    X, Y, Z = dg_head_local(D, GX, GY, GZ); out.append(('head', place(X, Y, Z), place(D['hx'], 0.0, D['hz'])))
    kx, kz = dg_bill_centre(D)
    X, Y, Z = dg_bill_local(D, GX, GY, GZ); out.append(('bill', place(X, Y, Z), place(kx, 0.0, kz)))
    X, Y, Z = dg_bill_local(D, GX, GY, GZ, True); out.append(('lower', place(X, Y, Z), place(kx, 0.0, kz - D['krz'])))
    return out


def dg_eye_dirs(D):
    """Local unit directions of the near (-y, the viewer's side) and far eyes on the head."""
    a, e = math.radians(D['eye_az']), math.radians(D['eye_el'])
    return [np.array([math.cos(e) * math.cos(a), -math.cos(e) * math.sin(a), math.sin(e)]),
            np.array([math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e)])]
