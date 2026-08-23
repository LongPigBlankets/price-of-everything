#!/usr/bin/env python3
"""Bake one building's level set end to end: render -> export -> print pass -> install.

    python bake_sprite.py <building> [--out DIR] [--install] [--no-verify]
    python bake_sprite.py --list

Run with a normal python (it shells out to Blender itself; it is not a Blender script).

Every building the sprite set ships is in BUILDINGS below, keyed by the game's internal_name
so the output filenames are right by construction — `building_sprites.gd` finds sprites as
`<internal_name>_lvl<n>.png` and nothing else needs changing to add one.

VERIFY BEFORE OVERWRITE. Re-baking an already-shipped sprite re-renders it from the builder
as it stands TODAY, which is not automatically what shipped: a builder may have drifted, and
one building (the mine) has no builder in this checkout at all. So unless --no-verify, each
level is compared against the installed PNG by alpha IoU and a coarse tone correlation, and
anything that has moved is reported and NOT installed. The contour change alone lands around
0.97 IoU; a real geometry change drops it far below that.
"""
import argparse
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BLENDER = os.environ.get(
    "BLENDER_EXE", r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe")
GAME = os.environ.get(
    "POE_DIR", r"C:\Users\urigi\price-of-everything\price-of-everything-0.1")
SPRITES = os.path.join(GAME, "assets", "icons", "buildings", "sprites")

# internal_name -> how to build it.
#   levels : what to pass the build function. () means it takes no level argument at all.
#   out    : which <name>_lvl<n>.png files the result is written to.
# The two are separate because they genuinely differ: the docks build ONE scene and the game
# ships it under all three level names (verified — port_lvl1/2/3 are byte-identical), and the
# construction site builds one scene and ships only an L1.
def _B(f, fn, col, levels=(1, 2, 3), out=(1, 2, 3)):
    return dict(file=f, fn=fn, col=col, levels=levels, out=out)


BUILDINGS = {
    "industrial_factory": _B("factory_builder.py", "build_factory", "BLDG_factory"),
    "furnace":            _B("furnace_builder.py", "build_furnace", "BLDG_furnace"),
    "power_plant":        _B("power_plant_builder.py", "build_power_plant",
                             "BLDG_powerplant"),
    "petro_refinery":     _B("petro_refinery_builder.py", "build_petro_refinery",
                             "BLDG_petro"),
    "poly_plant":         _B("poly_plant_builder.py", "build_poly_plant", "BLDG_poly"),
    "port":               _B("docks_builder.py", "build_docks", "BLDG_docks",
                             levels=(), out=(1, 2, 3)),
    "construction_site":  _B("construction_site_builder.py", "build_construction_site",
                             "BLDG_construction", levels=(), out=(1,)),
    "eaf":                _B("eaf_builder.py", "build_eaf", "BLDG_eaf"),
    "electrolyser":       _B("electrolyser_builder.py", "build_electrolyser",
                             "BLDG_electrolyser"),
    # Two buildings, ONE builder file — they share the turbine, the blade loft and the rotor
    # yaw, and differ only in what they stand in and whether they carry a yard.
    "solar_farm":         _B("solar_farm_builder.py", "build_solar_farm", "BLDG_solar"),
    "assembly_plant":     _B("assembly_plant_builder.py", "build_assembly_plant",
                             "BLDG_assembly"),
    "chem_plant":         _B("chem_plant_builder.py", "build_chem_plant", "BLDG_chem"),
    "high_tech_manufactory": _B("high_tech_builder.py", "build_high_tech", "BLDG_hightech"),
    "onshore_wind_farm":  _B("wind_farm_builder.py", "build_wind_farm", "BLDG_wind"),
    "offshore_wind_farm": _B("wind_farm_builder.py", "build_offshore_wind_farm",
                             "BLDG_offshore_wind"),
    # NOTE: `mine` ships three distinct sprites but has NO mine_builder.py in this checkout,
    # so it cannot be re-baked. SKILL.md documents the builder; the file is missing.
}

STYLIZE = dict(lit=0.86, dark=0.56, strength=0.22)


def render(name, out_dir, levels):
    b = BUILDINGS[name]
    for L in levels:
        dst = os.path.join(out_dir, "%s_L%d.png" % (name, L))
        # A builder with no level parameter is invoked with level 0, which render_sprite.py
        # reads as "call it with no arguments".
        arg = str(L) if b["levels"] else "0"
        r = subprocess.run(
            [BLENDER, "--background", "--factory-startup", "--python",
             os.path.join(HERE, "render_sprite.py"), "--",
             b["file"], b["fn"], arg, dst, b["col"]],
            capture_output=True, text=True)
        if "MASK_OK" not in r.stdout:
            sys.exit("render failed for %s L%d:\n%s" % (name, L, r.stdout[-2500:]))
        print("  rendered L%d" % L)


def compare(a_path, b_path):
    """Alpha IoU, and interior tone correlation with the print pass blurred out.

    Both halves need care, because the pipeline changed ON PURPOSE and a naive diff just
    measures the change we wanted:
      * the SILHOUETTE grew a synthesized contour band instead of Freestyle's, so raw IoU
        runs about 0.977 on an unchanged building — the band is a few percent of area. IoU is
        still the right geometry gate; the threshold just has to allow for it.
      * per-pixel TONE now differs everywhere the stipple moved, which is everywhere. Compared
        raw it scores about 0.80 on a building that has not moved at all. So the comparison
        erodes both alphas well inside the contour and BLURS both images enough to average the
        dot pattern away, leaving material tone and geometry — which is what drift would move.
    """
    import numpy as np
    from PIL import Image, ImageFilter
    ia = Image.open(a_path).convert("RGBA")
    ib = Image.open(b_path).convert("RGBA")
    if ia.size != ib.size:
        return 0.0, 0.0
    a = np.asarray(ia).astype(np.float32) / 255.0
    b = np.asarray(ib).astype(np.float32) / 255.0
    aa, ba = a[..., 3] > 0.5, b[..., 3] > 0.5
    iou = float((aa & ba).sum()) / max(1, float((aa | ba).sum()))

    core = Image.fromarray(((aa & ba) * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(17))
    core = np.asarray(core) > 128
    if core.sum() < 500:
        return iou, 0.0
    fa = np.asarray(ia.convert("RGB").filter(ImageFilter.GaussianBlur(6))).astype(np.float32)
    fb = np.asarray(ib.convert("RGB").filter(ImageFilter.GaussianBlur(6))).astype(np.float32)
    la = (fa @ [0.2126, 0.7152, 0.0722])[core]
    lb = (fb @ [0.2126, 0.7152, 0.0722])[core]
    if la.std() < 1e-6 or lb.std() < 1e-6:
        return iou, 0.0
    return iou, float(np.corrcoef(la, lb)[0, 1])


def bake(name, out_dir, levels=None, install=False, verify=True):
    from stylize_shade import stylize
    from sprite_export import export

    print("== %s ==" % name)
    # Absolute, always: render_sprite.py runs inside Blender, whose working directory is not
    # this shell's, so a relative --out silently writes the renders somewhere else and export
    # then fails looking for files that were made.
    out_dir = os.path.abspath(out_dir)
    os.makedirs(out_dir, exist_ok=True)
    b = BUILDINGS[name]
    # A level-less builder renders once, as level 1, and that one image is exported alone —
    # so it fills the canvas to the pad on its own rather than being scaled against siblings
    # that do not exist.
    levels = levels or (b["levels"] or (1,))
    render(name, out_dir, levels)
    export(out_dir, name, levels=levels)
    for L in levels:
        base = os.path.join(out_dir, "%s_lvl%d" % (name, L))
        stylize(base + ".png", base + "_mask.png", base + ".png", **STYLIZE)

    ok = True
    if verify:
        for i, L in enumerate(levels):
            shipped = os.path.join(SPRITES, "%s_lvl%d.png" % (name, b["out"][min(i, len(b["out"]) - 1)]))
            if not os.path.exists(shipped):
                print("  L%d: no shipped sprite to compare (new building)" % L)
                continue
            mine_p = os.path.join(out_dir, "%s_lvl%d.png" % (name, L))
            iou, corr = compare(mine_p, shipped)
            from PIL import Image as _I
            nb = _I.open(mine_p).convert("RGBA").split()[3].getbbox()
            sb = _I.open(shipped).convert("RGBA").split()[3].getbbox()
            dw, dh = (nb[2] - nb[0]) - (sb[2] - sb[0]), (nb[3] - nb[1]) - (sb[3] - sb[1])
            dim_ok = abs(dw) <= max(8, 0.02 * (sb[2] - sb[0])) and                      abs(dh) <= max(8, 0.02 * (sb[3] - sb[1]))
            # GEOMETRY is the gate; tone is advisory. Verified on the furnace: content
            # dimensions matched the shipped sprite to within 3 px on all three levels while
            # blurred tone correlation ran 0.91-0.96, because the stipple moved everywhere on
            # purpose. Silhouette size is what a builder drifting would actually move.
            flag = "OK" if (iou > 0.93 and dim_ok) else "** DRIFT **"
            if flag != "OK":
                ok = False
            print("  L%d vs shipped: %dx%d (%+d,%+d px)  IoU %.3f  tone %.3f  %s"
                  % (L, nb[2] - nb[0], nb[3] - nb[1], dw, dh, iou, corr, flag))

    if install and (ok or not verify):
        import shutil
        for i, L in enumerate(b["out"]):
            src = os.path.join(out_dir, "%s_lvl%d.png"
                               % (name, levels[min(i, len(levels) - 1)]))
            shutil.copyfile(src, os.path.join(SPRITES, "%s_lvl%d.png" % (name, L)))
        print("  installed %d file(s) -> %s" % (len(b["out"]), SPRITES))
    elif install:
        print("  NOT installed: a level drifted from the shipped sprite. Inspect first.")
    return ok


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("building", nargs="?")
    ap.add_argument("--out", default=os.path.join(HERE, "exports"))
    ap.add_argument("--levels", default="")
    ap.add_argument("--install", action="store_true")
    ap.add_argument("--no-verify", action="store_true")
    ap.add_argument("--list", action="store_true")
    k = ap.parse_args()
    if k.list or not k.building:
        print("\n".join(sorted(BUILDINGS)))
        sys.exit(0)
    sys.path.insert(0, HERE)
    names = sorted(BUILDINGS) if k.building == "all" else [k.building]
    for n in names:
        bake(n, k.out, tuple(int(v) for v in k.levels.split(",")) if k.levels else None,
             install=k.install, verify=not k.no_verify)
