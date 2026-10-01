"""Shared bits for the rubber silhouette fits: camera, ink model, reference masks at half resolution."""
import math
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import binary_fill_holes, distance_transform_edt, binary_dilation
SQ2, SQ3 = math.sqrt(2), math.sqrt(3)
VIEW = np.array([1, -1, 1]) / SQ3
RIGHT = np.array([1, 1, 0]) / SQ2
UP = np.cross(VIEW, RIGHT); UP /= np.linalg.norm(UP)
PX800 = 736.0 / 1651.0 * 2.0            # px at 800 per half-res reference px (the shipped inked box is 1651 tall)
R_OUT, R_HOLE = 6.0 / PX800, 3.0 / PX800

def half(m):
    H, W = m.shape
    return m[:H // 2 * 2, :W // 2 * 2].reshape(H // 2, 2, W // 2, 2).mean(axis=(1, 3)) >= 0.5

STACK = half(np.load('ref_stack_full.npy')); BOOTS = half(np.load('ref_boots_full.npy')); DUCK = half(np.load('ref_duck_full.npy'))
SHAPE = STACK.shape

def project(p, C):
    p = np.asarray(p)
    return np.stack([p @ RIGHT * C['S'] + C['TX'], -(p @ UP) * C['S'] + C['TY']], -1)

def poly(d, pts):
    d.polygon([(float(x), float(y)) for x, y in pts], fill=255)

def inked(M):
    filled = binary_fill_holes(M); vis = distance_transform_edt(~filled) <= R_OUT
    holes = filled & ~M
    if holes.any():
        vis &= ~(distance_transform_edt(holes) > R_HOLE)
    return vis

def iou(M, R, care):
    return (M & R & care).sum() / max(((M | R) & care).sum(), 1)
