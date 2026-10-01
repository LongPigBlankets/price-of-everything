"""The shipped board's top face unwarped into board coordinates (u along X from the left corner to the bottom corner, v
along Y from the left corner to the top corner), from its three visible corners (an affine map, so the AI art's
non-isometric projection does not matter).    python3 warp.py -> board_uv.png (u, v in [-0.25, 1.05], 1300 px)"""
import numpy as np
from PIL import Image
L, T, R = np.array([74.0, 802.0]), np.array([1022.0, 102.0]), np.array([1972.0, 787.0])
B = L + R - T
EU, EV = B - L, T - L
LO, HI, N = -0.25, 1.05, 1300
def to_screen(u, v):
    return L + np.multiply.outer(u, EU) + np.multiply.outer(v, EV)
if __name__ == '__main__':
    im = np.asarray(Image.open('../ref/cb_paper.png').convert('RGB')).astype(float)
    g = np.linspace(LO, HI, N); U, V = np.meshgrid(g, g[::-1])          # rows: v from HI (top) to LO
    S = L + U[..., None] * EU + V[..., None] * EV
    x, y = S[..., 0], S[..., 1]; x0 = np.clip(np.floor(x).astype(int), 0, im.shape[1] - 2); y0 = np.clip(np.floor(y).astype(int), 0, im.shape[0] - 2)
    fx, fy = (x - x0)[..., None], (y - y0)[..., None]
    out = im[y0, x0] * (1 - fx) * (1 - fy) + im[y0, x0 + 1] * fx * (1 - fy) + im[y0 + 1, x0] * (1 - fx) * fy + im[y0 + 1, x0 + 1] * fx * fy
    Image.fromarray(out.clip(0, 255).astype('uint8')).save('board_uv.png'); print('B =', B)
