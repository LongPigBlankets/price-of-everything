"""Build the loading screen's intro plates from the film's first frame.

    python tools/make_intro_plates.py [path/to/film.ogv]

Writes assets/loading/intro/01_sky.png .. 05_full.png — the film's opening composition
assembling itself, one depth band at a time, so the loading screen has something designed to
show during the seconds when the main thread is not free enough to play video.

WHY IT IS BUILT THIS WAY. You cannot un-composite a frame: delete the trees and you are left
with a hole, not the building behind them. So the plates are ADDITIVE. Every plate is the
final frame masked to the bands revealed so far, over a sky extended downward — pixels are
only ever added, never removed, and whatever occludes what in the film still occludes it here.
The last plate is the untouched frame, so the film starts from exactly the picture the
sequence ended on.

THE BANDS ARE DEPTH. The film is a one-point-perspective dolly down a street, so distance from
the horizon IS distance from the camera: the world assembles from the vanishing point outward,
which is what the shot is about.

This is the stand-in. The real split is available: loading_scene.py keeps the film's geometry
in four collections — LOAD_sky, LOAD_city, LOAD_street, LOAD_props_veh — and _show_only_load()
already isolates them per object, so rendering frame 0 four times with progressively more of
them camera-visible gives true semantic layers. That costs a ~16 min scene build plus three
passes a plate; this costs six seconds. Same filenames either way.
"""

import os
import subprocess
import sys

from PIL import Image, ImageFilter

OUT_DIR = os.path.join("assets", "loading", "intro")
FILM = sys.argv[1] if len(sys.argv) > 1 else os.path.join("assets", "loading", "film.ogv")

# Fractions of the frame height, measured from the top, at which each band ENDS. The first is
# the sky; the rest walk down and outward from the horizon. Tuned against the 2400x1080 frame.
BANDS = [
    ("01_sky", 0.00),      # sky alone, extended over everything below
    ("02_skyline", 0.62),  # the far city and the tops that break the horizon
    ("03_street", 0.78),   # the buildings either side, down to the pavement
    ("04_ground", 0.90),   # road, verges and the near lawn
    ("05_full", 1.00),     # everything, untouched — the film's first frame
]
FEATHER = 26   # px of soft edge on the reveal, so a band arrives rather than snaps


def _first_frame(path):
    tmp = os.path.join(OUT_DIR, "_frame0.png")
    os.makedirs(OUT_DIR, exist_ok=True)
    rc = subprocess.call(["ffmpeg", "-y", "-loglevel", "error", "-i", path,
                          "-vf", "select=eq(n\\,0)", "-vframes", "1", tmp])
    if rc != 0:
        raise SystemExit("could not read the first frame of %s" % path)
    img = Image.open(tmp).convert("RGB")
    os.remove(tmp)
    return img


def _sky_plate(frame):
    """The sky, continued downward — and NOTHING else.

    Per row, the sky's colour is the row's MODE, not its average: the sky is by far the most
    common colour in any row it dominates, so the mode picks it exactly while a mean would drag
    it toward whatever crane or chimney crosses that row. (Blurring the real frame was tried
    first and leaves ghosts of the buildings in what is supposed to be an empty sky.)

    Rows are read down to where the skyline starts eating them; below that the last clean row
    is held, so the plate keeps the sky's vertical fall-off and ends flat at the horizon
    colour, which is what an empty scene would actually look like.
    """
    w, h = frame.size
    small = frame.resize((max(1, w // 8), h), Image.BILINEAR)   # 8x fewer pixels to count
    rows = []
    for y in range(h):
        strip = small.crop((0, y, small.size[0], y + 1))
        colours = strip.getcolors(maxcolors=1 << 20) or []
        if not colours:
            rows.append(rows[-1] if rows else (0, 0, 0))
            continue
        count, colour = max(colours, key=lambda c: c[0])
        # A row the skyline has taken over no longer has a dominant sky colour; hold the last
        # clean one. Detecting a horizon and filling bare ground below it was tried and is
        # worse: this sky is a HORIZONTAL gradient, so no single colour holds a row and the
        # detector fires on the first row the crane crosses, painting the whole plate ground.
        if count < strip.size[0] * 0.22 and rows:
            rows.append(rows[-1])
        else:
            rows.append(colour)
    plate = Image.new("RGB", (1, h))
    plate.putdata(rows)
    return plate.resize((w, h), Image.BILINEAR)


def _band_mask(size, y_end, feather):
    """White above y_end, black below, with a soft edge — the reveal so far."""
    w, h = size
    mask = Image.new("L", (w, h), 0)
    cut = int(h * y_end)
    if cut > 0:
        mask.paste(255, (0, 0, w, min(h, cut + feather)))
    if feather > 0:
        mask = mask.filter(ImageFilter.GaussianBlur(feather * 0.5))
    return mask


def main():
    frame = _first_frame(FILM)
    os.makedirs(OUT_DIR, exist_ok=True)
    sky = _sky_plate(frame)
    for name, y_end in BANDS:
        if y_end <= 0.0:
            plate = sky
        elif y_end >= 1.0:
            plate = frame
        else:
            plate = Image.composite(frame, sky, _band_mask(frame.size, y_end, FEATHER))
        path = os.path.join(OUT_DIR, name + ".png")
        plate.save(path)
        print("wrote %s (%dx%d)" % (path, plate.size[0], plate.size[1]))
    print("%d plates in %s" % (len(BANDS), OUT_DIR))


if __name__ == "__main__":
    main()
