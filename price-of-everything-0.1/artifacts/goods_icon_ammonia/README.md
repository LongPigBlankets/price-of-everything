# Ammonia Blender icon

**Approved v4 is now installed in the game**, in the default and alternate tiers. See `installation.md` for import and runtime verification. Earlier draft notes below are historical.

## Latest revision: v4

Owner: "maybe 50% taller and a bit slimmer. The valve needs more detail. like this attached image".

Delivered in `final_v4/`: body diameter is 10% smaller; overall model height is 51.2% larger than v3. The silver valve now has a protective open guard, handwheel and spokes, spindle, mount, and recessed outlet. The white/navy label remains broad, with taller lettering to help at 60px. Black body and yellow shoulder palette are unchanged.

See `comparison_v4.png` for previous/current and actual 60px previews, `detail_crops_v4_3x.png` for magnified inspection, and `review_v4/` for the independent review. The v4 colour/mask/master PNGs were rendered twice and verified pixel-identical. The editable `final_v4/ammonia.blend` includes packed font data. The earlier `final/` and v1–v3 files are retained as history. No shipped game textures were replaced.

## Earlier v3 candidate


Owner direction: **black cylinder body, yellow shoulders, silver valve; white label with navy text**. The rounded cylinder and compact valve distinguish this good from chlorine/NaOH handled cans and the industrial-acids cluster at 60×60. The formula is real curved mesh lettering, with a reduced 3 aligned to the baseline.

## Deliverables

- `final/ammonia_800.png`: transparent master.
- `final/ammonia_60.png`: actual 60×60 check.
- `final/ammonia_450.png`, `final/ammonia_256.png`: derived tiers, staged for review.
- `final/ammonia.blend`: editable Blender scene with the font packed.
- `comparison.png`: reference family at large and actual 60px, light/dark backgrounds and grayscale.
- `detail_crops_3x.png`: four close inspections.
- `review/`: independent structural review and measurements.
- `final/verification.json`: rig, palette and deterministic pixel checks.

No game assets were replaced. These are draft artifacts for visual review, not Godot-installed textures.

## Design and checks

The cylinder preserves the chemical family's large white formula band and navy ink. It uses the fixed orthographic camera (54.736°, 0°, 45°), constant toon steps, yellow as its only warm accent, and normal-mask-driven shadow halftone. The black body intentionally has a narrower tonal range than teal goods. Front label mode is RGB 238/239/231; shoulder is 248/213/52. The formula remains readable in the actual 60px test. No claim of a player recognition study is made.

The final color, mask and 800px export are pixel-identical to the preceding v3 bake. Geometry validation passed. Outline and label were inspected at 3×. The export disables the shared neutral-dark strap detector for this strap-free object, avoiding false outlines on black tone transitions. Dependencies are isolated snapshots of the existing goods kit; unrelated workspace changes were preserved.

## Rebuild

Run from this repository's root:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python price-of-everything-0.1/artifacts/goods_icon_ammonia/source/render_ammonia.py -- /tmp/ammonia-rebuild
python3 price-of-everything-0.1/artifacts/goods_icon_ammonia/source/icon_export.py /tmp/ammonia-rebuild/ammonia_raw.png /tmp/ammonia-rebuild/ammonia_800.png --contour 0.013 --vib 1.15
```

`build_ammonia()` is at the end of `source/goods_icon_kit.py`. All dimensions use body diameter D=1. The original symbol alternatives and owner brief are recorded in its docstring. Rebuilding uses the system Arial Bold font; the delivered blend includes its packed font.
