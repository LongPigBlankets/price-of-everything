"""Paper WPA Catalog: the final paper effect for the supply chain view's catalogue plates.

Takes a building rendered on a transparent background (tools/supply_chain_3d/catalog_plate.tscn)
and prints it onto an aged catalogue sheet:

  * ink and paper instead of black and white: the darkest tones land on a blue-black ink
    (#1f2b36), the lightest on cream stock (#ece0c6); mid tones keep their hue, near-neutrals
    soften toward print while strong accents keep (and gain) their colour;
  * paper: large soft mottling, horizontal fibres, a fine tooth, worn edges;
  * ink grain where coverage is thin (mid tones), none on solid ink or bare paper;
  * the dark key layer printed two pixels off register;
  * a soft shadow cast up the sheet at 11 o'clock (the sun stands south-east);
  * a ruled border and spaced lettering: plate number, title, subtitle, imprint.

Offline only for now: the game does not draw this effect yet.

  python3 tools/supply_chain_3d/paper_wpa_catalog.py <render.png> <plate.png> \\
      --title "INDUSTRIAL GOODS FACTORY" --subtitle "LEVEL III  ·  SAWTOOTH HALLS" --number 14

Needs numpy, scipy and Pillow. Fonts: Futura and Gill Sans from macOS's supplemental set.
"""
import argparse

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi

INK_RGB = np.array([0x1f, 0x2b, 0x36]) / 255
PAPER_RGB = np.array([0xec, 0xe0, 0xc6]) / 255
ACCENT_RGB = (0xa4, 0x43, 0x2f)
FUTURA = "/System/Library/Fonts/Supplemental/Futura.ttc"
GILL_SANS = "/System/Library/Fonts/Supplemental/GillSans.ttc"
# Texture strengths. Grain (tooth, fibres, ink grain) was cut 35% from the first plates.
MOTTLE, FIBRE, TOOTH = 0.022, 0.0039, 0.0065
INK_FIBRE, INK_GRAIN = 0.0078, 0.0195
SHEET = (1400, 1800)
BUILDING_WIDTH = 1000


def _linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def to_oklab(rgb):
    m1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929], [0.2119034982, 0.6806995451, 0.1073969566],
                   [0.0883024619, 0.2817188376, 0.6299787005]])
    m2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468], [1.9779984951, -2.4285922050, 0.4505937099],
                   [0.0259040371, 0.7827717662, -0.8086757660]])
    return np.cbrt(np.maximum(_linear(rgb) @ m1.T, 0)) @ m2.T


def from_oklab(lab):
    m2i = np.array([[1, 0.3963377774, 0.2158037573], [1, -0.1055613458, -0.0638541728],
                    [1, -0.0894841775, -1.2914855480]])
    m1i = np.array([[4.0767416621, -3.3077115913, 0.2309699292], [-1.2684380046, 2.6097574011, -0.3413193965],
                    [-0.0041960863, -0.7034186147, 1.7076147010]])
    return _srgb(((lab @ m2i.T) ** 3) @ m1i.T)


INK, PAPER = to_oklab(INK_RGB), to_oklab(PAPER_RGB)


def printed(rgb):
    """Map rendered colour onto ink and paper: the tone range runs ink -> paper, near-neutral
    mid tones soften, strong accents keep their colour, a faint warm cast of aged stock."""
    lab = to_oklab(rgb)
    lightness, a, b = lab[..., 0], lab[..., 1], lab[..., 2]
    l2 = INK[0] + (PAPER[0] - INK[0]) * np.clip((lightness - 0.24) / (0.84 - 0.24), 0, 1)
    t = np.clip((l2 - INK[0]) / (PAPER[0] - INK[0]), 0, 1)
    toward_paper = np.clip((t - 0.74) / 0.26, 0, 1) ** 1.5
    toward_ink = np.clip((0.22 - t) / 0.22, 0, 1)
    accent = np.clip((np.hypot(a, b) - 0.035) / 0.05, 0, 1)
    keep = (0.92 + 0.43 * accent) * (1 - toward_paper) * (1 - toward_ink)
    a2 = a * keep + PAPER[1] * toward_paper + INK[1] * toward_ink
    b2 = b * keep + PAPER[2] * toward_paper + INK[2] * toward_ink + 0.008
    return np.clip(from_oklab(np.stack([l2, a2, b2], -1)), 0, 1)


def plate(render_path, title, subtitle, number, imprint="CARBON AND CAPITAL  ·  INDUSTRIAL CATALOGUE", seed=11):
    rng = np.random.default_rng(seed)
    building = Image.open(render_path).convert("RGBA")
    building = building.crop(building.getbbox())
    scale = BUILDING_WIDTH / building.width
    building = building.resize((int(building.width * scale), int(building.height * scale)), Image.LANCZOS)
    rgba = np.asarray(building).astype(float) / 255
    width, height = SHEET
    x0, y0 = (width - building.width) // 2, 260
    h, w = rgba.shape[:2]
    alpha = np.zeros((height, width))
    alpha[y0:y0 + h, x0:x0 + w] = rgba[..., 3]

    def noise(sigma):
        n = ndi.gaussian_filter(rng.standard_normal((height, width)), sigma)
        return n / n.std()
    mottle, fibre, tooth, grain = noise(90), noise((0.8, 3.5)), noise(1.2), noise(0.7)
    yy, xx = np.mgrid[0:height, 0:width]
    edge = np.minimum(np.minimum(xx, width - 1 - xx) / width, np.minimum(yy, height - 1 - yy) / height)
    sheet = PAPER_RGB * (1 + MOTTLE * mottle[..., None] + FIBRE * fibre[..., None] + TOOTH * tooth[..., None])
    sheet *= (0.94 + 0.06 * np.clip(edge / 0.05, 0, 1))[..., None]
    # The sun stands south-east: the shadow falls up the sheet and a little left (11 o'clock).
    shadow = np.roll(np.roll(ndi.gaussian_filter(alpha, 22), -55, 0), -18, 1) * (1 - alpha)
    sheet *= (1 - 0.13 * shadow)[..., None]

    ink = np.zeros((height, width, 3))
    ink[y0:y0 + h, x0:x0 + w] = printed(rgba[..., :3])
    luma = ink @ [0.2126, 0.7152, 0.0722]
    ink = ink * (1 + INK_FIBRE * fibre[..., None]) + (INK_GRAIN * grain * 4 * luma * (1 - luma))[..., None]
    ink *= 0.965 + 0.035 * sheet / PAPER_RGB
    sheet = sheet * (1 - alpha[..., None]) + ink * alpha[..., None]
    # The dark key layer, two pixels off register.
    key = np.roll(np.roll(np.clip((0.33 - luma) / 0.15, 0, 1) * alpha, -2, 0), -2, 1)
    sheet = sheet * (1 - 0.25 * key[..., None]) + INK_RGB * 0.25 * key[..., None]

    image = Image.fromarray((np.clip(sheet, 0, 1) * 255).astype("uint8"))
    draw = ImageDraw.Draw(image)
    ink_colour = tuple(int(c * 255) for c in INK_RGB)
    draw.rectangle((48, 48, width - 48, height - 48), outline=ink_colour, width=3)
    draw.rectangle((60, 60, width - 60, height - 60), outline=ink_colour, width=1)

    def spaced(y, text, font, fill, track):
        total = sum(draw.textlength(ch, font=font) + track for ch in text) - track
        x = (width - total) / 2
        for ch in text:
            draw.text((x, y), ch, font=font, fill=fill)
            x += draw.textlength(ch, font=font) + track
    spaced(110, "PLATE " + str(number), ImageFont.truetype(GILL_SANS, 26), ink_colour, 10)
    y = y0 + h + 80
    draw.line((width / 2 - 260, y, width / 2 + 260, y), fill=ink_colour, width=2)
    spaced(y + 34, title, ImageFont.truetype(FUTURA, 70), ink_colour, 6)
    spaced(y + 130, subtitle, ImageFont.truetype(GILL_SANS, 30), ACCENT_RGB, 8)
    draw.line((width / 2 - 160, y + 190, width / 2 + 160, y + 190), fill=ink_colour, width=1)
    spaced(y + 215, imprint, ImageFont.truetype(GILL_SANS, 22), ink_colour, 6)
    return image


def main():
    parser = argparse.ArgumentParser(description="Print a catalogue-plate render in the Paper WPA Catalog style.")
    parser.add_argument("render")
    parser.add_argument("output")
    parser.add_argument("--title", required=True)
    parser.add_argument("--subtitle", default="")
    parser.add_argument("--number", default="1")
    args = parser.parse_args()
    plate(args.render, args.title, args.subtitle, args.number).save(args.output)


if __name__ == "__main__":
    main()
