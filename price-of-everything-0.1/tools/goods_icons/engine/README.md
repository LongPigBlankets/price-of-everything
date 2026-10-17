# Engine (g_046) Blender icon

Builder for the approved engine alternate icon,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_046_engine.png` (internal name `engine`). The approval
record, renders and proof sheets are in `artifacts/goods_engine/`.

It shows the shipped art's V8 long block, built as a real 90 degree V8:

- **Block:** the crank axis runs along Y with the timing end to the camera. Each bank's cylinder axis runs through the
  crank at 45 degrees, the shipped art's cam-cover angle.
- **Banks:** each head sits on a deck square to its bank axis, under a red cam cover. The cover is a rounded rectangle
  with a filleted top on a rounded flange, with a raised panel on top.
- **Intake:** the lower intake fills the valley. The plenum sits on it with arched runners down to the ports and the
  throttle body facing forward. A thermostat housing with its hose neck sits on the intake's nose.
- **Exhaust:** on each side, cast-iron primaries run from the head's outer face down into a log, and the outlet turns
  under the block.
- **Front:** a red-framed timing cover. The crank pulley sits on the crank axis with the water pump pulley above it.
  The alternator has a pivot bracket and a slotted adjusting strap, and one belt runs round all three.
- **+X side:** an engine mount and the oil filter.
- **Pan:** a deeper sump at the rear.

It uses the fixed orthographic goods camera, the set's light, 12/4 px ink and dots on the shaded sides. The installed
revision is `engine_v12`.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
blender -b --factory-startup --python-exit-code 1 --python tools/goods_icons/engine/render.py -- <out_dir> engine
python3 tools/goods_icons/engine/icon_export.py <out_dir>/engine_raw.png <out_dir>/engine_800.png --vib 1.0
python3 tools/goods_icons/engine/engine_proof.py <out_dir> [previous_800.png]
```

`engine_proof.py` writes `engine_sheet.png` (the shipped art, the optional previous render and this one, each also at
60 px) and `engine_regions.png` (3x crops of four regions). Re-rendered from this folder at install, the 800 px master
was pixel-identical to the approved one.

## `engine_kit.py`

- **`en_bank()` and `en_tilt()`:** place a point, or turn a part built upright, onto a bank by rotating it about the
  crank axis. Every head, cover and manifold part is built square and then turned, so they share the bank's geometry.
- **`en_rslab()`:** a rounded-rectangle slab with a filleted top edge, smooth shaded. It builds the cam covers, their
  flanges and panels.
- **`en_belt()` / `en_ring()` / `en_hull()`:** the belt, made as the band between support-function hulls of the pulley
  rims, and the red timing-cover frame.
- **`en_strip()`:** a flat bar in the front plane, used for the alternator's strap and pivot bracket.
- **`build_engine()`:** builds the parts, inks each one's creases and contours, and sets the outline and stipple
  contract. Part labels drive the component boundary lines; `id_step` is 17 so that 15 labels fit.

It reuses the shared kits copied beside it (`sprite_kit.py`, `base_kit.py`, `plastics_kit.py`'s toon, ink and mesh
helpers, `goods_icon_kit.py`'s contract and rounded boxes, `standard_lines.py`'s export).
