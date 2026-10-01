# Circuit board (g_043) Blender icon

Builder for the approved circuit board alternate icon,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_043_circuit_board.png` (internal name `circuit_board`).

It shows a bare green board with a pale bevel along its top edges, lying flat on the set's grid. An edge-connector tab
carries gold fingers split by a key notch. The board's copper keeps the shipped art's layout but is made electrically
plausible: there are no dead ends, every finger has a trace, and the empty middle is a printed socket footprint for the
CPU and its socket, which is a separate good (`g_041`). It uses the fixed orthographic goods camera, the set's light,
12/4 px ink and dots on the shaded sides; the copper and silkscreen are printed, so they are undotted. The installed
revision is `circuit_board_v6`.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/circuit_board/render.py -- <out_dir> circuit_board
python3 tools/goods_icons/circuit_board/icon_export.py <out_dir>/circuit_board_raw.png <out_dir>/circuit_board_800.png --vib 1.0
python3 tools/goods_icons/circuit_board/cb_proof.py <out_dir>
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/circuit_board/cb_verify.py -- <out_dir>
```

Re-rendered from this copy at install, the 800 px master was pixel-identical to the approved one, and the check reported
no failures.

## Files

- `circuit_kit.py`: `build_circuit_board()`.
  - **The board** is the outline (`cb_outline`: a rounded rectangle with the tab and its notch) extruded 0.10 thick,
    its top edges bevelled.
  - **Copper** is laid flat on the board from `copper2.json`: traces as quads with round joins, via rings, the
    socket's land pads and the fingers.
  - **Socket marking:** the silkscreen outline and pin-1 triangle, inside the land pads.
  - **Via holes** are dark discs. The **pads** are raised prisms with gold tops and dark sides.
  - The tab's roots sit a hair below the board edge, so that collinear points do not make zero-area cap triangles.
  - Ink comes from the board's own convex creases and contours. `plastics_kit.py` here is the shared helper with one
    change, in `pl_mesh_lines`: concave edges are never inked, and the bevel's seams at the four inner corners are cut
    from the chains in the kit.
- `copper2.json`: the copper as installed. `fit/` holds how it was made:
  - `warp.py` unwarps the shipped top face into board coordinates;
  - `extract.py` reads the traces (thinned), vias, pads and fingers. `copper_v1.json` is the first reading;
    `copper.json` is the second, with the gaps where the art fades closed;
  - `route.py` makes the copper plausible: it rejoins fragments, runs traces to the socket's edge and its land pads,
    gives the connector pads short traces to it, drops loose dashes, ends other free ends in small vias, and gives
    every finger a trace.
- `cb_verify.py` checks the camera, closed hosts, nothing below ground, and the pads on the board.
- `cb_proof.py` writes the tiers and proof sheets.
