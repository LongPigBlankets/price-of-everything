#!/usr/bin/env python3
"""Make the game's title logo from a three-hex nameplate render (owner: the new logo on the
main menu in place of the old emblem).

    python3 tools/steam_capsule/game_logo.py tools/steam_capsule/renders/nameplate_trio_v21.png \
        price-of-everything-0.1/assets/ui/title_logo_trio.png

The render is nameplate.py's transparent frame (--plate trio). It is trimmed to the logo with
PAD of its height left round it, and scaled to HEIGHT pixels tall: the main menu shows it
313 px tall (main_menu.gd LOGO_H), so this keeps it sharp at twice that and more. Its
background stays transparent and no shadow is added, as the old emblem had none; the menu
lays it on its own navy.
"""
import sys

from PIL import Image

HEIGHT = 1000
PAD = 0.01


def main(src, out):
    im = Image.open(src).convert("RGBA")
    x0, y0, x1, y1 = im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    p = round(PAD * (y1 - y0))
    im = im.crop((max(0, x0 - p), max(0, y0 - p), min(im.width, x1 + p), min(im.height, y1 + p)))
    w = round(im.width * HEIGHT / im.height)
    im = im.resize((w, HEIGHT), Image.LANCZOS)
    im.save(out, optimize=True)
    print("wrote %s, %dx%d" % (out, w, HEIGHT))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
