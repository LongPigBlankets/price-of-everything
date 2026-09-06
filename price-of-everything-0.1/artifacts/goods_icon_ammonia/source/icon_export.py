"""Goods-icon export: raw 1024 render (+ its shading mask) -> alpha crop -> synthesised outer
contour -> 800px canvas -> halftone on the SHADED faces only.

Style numbers (measured on the shipped goods icons, see goods_icon_kit.py):
  outer contour  1.4% of the long side  (11 px at 800)
  ink            sRGB (20, 30, 60)
  canvas         icon fills ~92% of the square; 4% margin each side
  halftone       navy dots, spacing ~1.25% of width, three density bands by how far a face
                 turns from the light (from the mask pass, NOT from luma - a luma key dots
                 every mid-tone body and gives the all-over halftone the owner rejected).

    python3 icon_export.py <raw.png> <out.png> [--size 800] [--contour 0.014]
The mask is looked up at <raw minus .png>_mask.png; without it the icon exports unstippled.
"""
import argparse, os
import numpy as np
from PIL import Image, ImageFilter

INK = (20, 30, 60)


def dilate(mask: np.ndarray, r: int) -> np.ndarray:
    im = Image.fromarray((mask * 255).astype(np.uint8))
    return np.array(im.filter(ImageFilter.MaxFilter(2 * r + 1))) > 127


def erode(mask: np.ndarray, r: int) -> np.ndarray:
    im = Image.fromarray((mask * 255).astype(np.uint8))
    return np.array(im.filter(ImageFilter.MinFilter(2 * r + 1))) > 127


def _crop_pad(a: np.ndarray, x0, x1, y0, y1, pad):
    out = np.zeros((y1 - y0 + 2 * pad, x1 - x0 + 2 * pad) + a.shape[2:], a.dtype)
    out[pad:pad + (y1 - y0), pad:pad + (x1 - x0)] = a[y0:y1, x0:x1]
    return out


def stipple(rgba: np.ndarray, lit: np.ndarray, spacing: float, dot_r: float, strength: float):
    """lit: 0..1 per pixel (1 = facing the light). Three bands, constant dot size, dots are
    the ink colour blended at `strength`. Ink lines and near-navy pixels are left alone."""
    h, w = lit.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    rgb = rgba[..., :3].astype(np.float32)
    luma = rgb @ np.array([0.299, 0.587, 0.114], np.float32)
    # protect the INK itself (by colour distance), not everything dark: a dark rust shadow
    # step sits under 80 luma and still wants its halftone
    dist_ink = np.sqrt(((rgb - np.array(INK, np.float32)) ** 2).sum(axis=-1))
    protect = (dist_ink < 26) | (rgba[..., 3] < 200)
    def grid(sp, ox=0.0, oy=0.0):
        gx = np.abs(((xx + ox) % sp) - sp / 2)
        gy = np.abs(((yy + oy) % sp) - sp / 2)
        return np.hypot(gx, gy) <= dot_r
    b1 = lit < 0.56                       # turned away from the light: sparse grid
    b2 = lit < 0.05                       # + the dual grid  (2x)
    b3 = lit < 0.05                       # + a half-spacing grid (4x)
    dots = (b1 & grid(spacing)) | (b2 & grid(spacing, spacing / 2, spacing / 2)) \
        | (b3 & (grid(spacing / 2, spacing / 4, 0) | grid(spacing / 2, 0, spacing / 4)))
    dots &= ~protect
    ink = np.array(INK, np.float32)
    rgb[dots] = rgb[dots] * (1 - strength) + ink * strength
    rgba = rgba.copy()
    rgba[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    return rgba


def vibrance(crop: np.ndarray, factor: float):
    """Punch up colour vibrancy: expand chroma around each pixel's luma (owner: the icons read
    too washed out). factor 1.0 = unchanged; ~1.4 = noticeably more saturated + a touch more
    contrast. Applied to opaque non-ink pixels; the navy ink is left alone."""
    if factor == 1.0:
        return crop
    rgb = crop[..., :3].astype(np.float32)
    luma = (rgb @ np.array([0.299, 0.587, 0.114], np.float32))[..., None]
    out = np.clip(luma + (rgb - luma) * factor, 0, 255)
    opaque = crop[..., 3] > 40
    ink = np.sqrt(((rgb - np.array(INK, np.float32)) ** 2).sum(-1)) < 40
    keep = opaque & ~ink
    crop = crop.copy()
    crop[..., :3][keep] = out[keep].astype(np.uint8)
    return crop


def export(raw: str, out: str, size: int = 800, contour: float = 0.014, margin: float = 0.04,
           strength: float = 0.42, vib: float = 1.0):
    im = Image.open(raw).convert("RGBA")
    a = np.array(im)
    mask_path = raw[:-4] + "_mask.png"
    lit_full = None
    if os.path.exists(mask_path):
        mk = np.array(Image.open(mask_path).convert("RGBA")).astype(np.float32)
        # the mask PNG is sRGB-encoded by the Standard view transform: undo the gamma so the
        # value is the emission (0.5 + 0.5*dot(N,L)) again, not its display encoding
        lit_full = np.power(np.clip(mk[..., 0] / 255.0, 0, 1), 2.2)
    alpha = a[..., 3] > 40
    ys, xs = np.where(alpha)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    pad = int(max(x1 - x0, y1 - y0) * contour * 2) + 4
    crop = _crop_pad(a, x0, x1, y0, y1, pad)
    m = crop[..., 3] > 40
    long_side = max(m.shape)
    r = max(2, int(round(long_side * contour)))
    closed = erode(dilate(m, r), r)             # bridge slots narrower than the line
    ring = dilate(closed, r) & ~m
    crop[..., :3][ring] = INK
    crop[..., 3][ring] = 255
    # the render's anti-aliased edge (alpha 40..250) is pale fill over transparency; against
    # the new navy ring it read as a bright hairline, so blend it toward ink by its missing alpha
    fr = (crop[..., 3] > 40) & (crop[..., 3] < 250)
    t = (255 - crop[..., 3][fr].astype(np.float32)) / 255.0
    crop[..., :3][fr] = (crop[..., :3][fr] * (1 - t[:, None]) + np.array(INK, np.float32) * t[:, None]).astype(np.uint8)
    crop[..., 3][fr] = 255
    # 2D outline for un-inked STRAP faces (neutral dark grey, see goods_icon_kit.ribbon):
    # a thin navy ring around every such region, at the interior-line weight
    rgb0 = crop[..., :3].astype(np.int32)
    # tight: navy ink anti-aliased against white is BLUE-biased (g-b >= 16), strap is neutral
    neutral = (np.abs(rgb0[..., 0] - rgb0[..., 1]) < 9) & (np.abs(rgb0[..., 1] - rgb0[..., 2]) < 9)
    lum0 = (rgb0[..., 0] * 299 + rgb0[..., 1] * 587 + rgb0[..., 2] * 114) // 1000
    strap = neutral & (lum0 > 48) & (lum0 < 100) & (crop[..., 3] > 200) & ~ring
    strap = erode(dilate(dilate(erode(strap, 2), 2), 3), 3)   # drop slivers, then close notches
    if False and strap.sum() > 400:  # ammonia has no straps; dark body tones must stay unoutlined
        ri = max(2, int(round(long_side * 0.0045)))
        sring = dilate(strap, ri) & ~strap & m
        crop[..., :3][sring] = INK
    # inter-part SEPARATION line: where two nuggets meet, the object-ID pass changes colour;
    # ink a bold line there so each rock reads as a separate rock (Freestyle can't draw it -
    # the meshes interpenetrate). Reference: every rock is fully outlined, overlaps included.
    id_path = raw[:-4] + "_id.png"
    if os.path.exists(id_path):
        idimg = np.array(Image.open(id_path).convert("RGBA"))
        idc = _crop_pad(idimg, x0, x1, y0, y1, pad)
        ida = idc[..., 3] > 120
        lab = np.argmax(idc[..., :3].astype(np.int32), axis=-1) + 1     # 1..3 by dominant channel
        lab[~ida] = 0
        seam = np.zeros_like(ida)
        for ax, sh in ((0, 1), (0, -1), (1, 1), (1, -1)):
            rolled = np.roll(lab, sh, axis=ax)
            seam |= (lab > 0) & (rolled > 0) & (lab != rolled)
        rs = max(2, int(round(long_side * contour * 0.62)))            # a touch under the outer contour
        seam = dilate(seam, rs) & m
        crop[..., :3][seam] = INK
        crop[..., 3][seam] = 255
        ring = ring | seam                                             # protect it from stipple
    if lit_full is not None:
        lit = _crop_pad(lit_full, x0, x1, y0, y1, pad)
        lit[ring] = 1.0
        crop = stipple(crop, lit, spacing=long_side * 0.015, dot_r=long_side * 0.0036,
                       strength=strength)
    crop = vibrance(crop, vib)
    img = Image.fromarray(crop)
    img = img.crop(img.getbbox())
    target = int(size * (1 - 2 * margin))
    scale = target / max(img.size)
    img = img.resize((max(1, round(img.size[0] * scale)), max(1, round(img.size[1] * scale))), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(img, ((size - img.size[0]) // 2, (size - img.size[1]) // 2), img)
    canvas.save(out)
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("raw")
    ap.add_argument("out")
    ap.add_argument("--size", type=int, default=800)
    ap.add_argument("--contour", type=float, default=0.014)
    ap.add_argument("--strength", type=float, default=0.42)
    ap.add_argument("--vib", type=float, default=1.0, help="colour vibrance boost, e.g. 1.4")
    args = ap.parse_args()
    print("exported", export(args.raw, args.out, args.size, args.contour, strength=args.strength, vib=args.vib))
