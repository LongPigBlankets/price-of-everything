# EV car (g_057) Blender icon

Builder for the approved EV car alternate icon,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_057_ev_car.png` (internal name `ev_car`). It shows a
blue electric SUV at a green charging post, its cable plugged into a port on the front wing, drawn with the fixed
orthographic goods camera, the set's light, a 12 px outer line, 4 px interior lines and dots on the shaded sides.
The installed render is v6 (its build record still names the builder revision `ev_car_study_v4`; the charger came in v5
and v6, see `artifacts/goods_ev_car/README.md`).

## Source model

The car started from a model the owner downloaded as "a rough approximation"
(`~/Downloads/asfcsadfvasew.blend`, 46 MB, not in the repository). It is one mesh with Turkish material names and looks
like a TOGG T10X. Its source and licence are not recorded. `prep/ev_prep.py` turns it into `ev_prepped.blend`, which is
the file the builder loads:

```sh
Blender --background --factory-startup --disable-autoexec <download>.blend --python prep/ev_prep.py -- ev_prepped.blend
```

What the prep does:
- **Front:** the grille's chrome slats and the brand mark go. The grille opening is covered by a smooth body-colour
  panel fitted to the old backing. The old lamps are covered by panels fitted to the nose.
- **Lamps:** new slim lamps are laid on the nose, their inner ends a steep diagonal.
- **Roof and cabin:** the model has no roof or glass, so a solid roof is added between the headers. The windows stay
  open onto the cabin.
- **Wheels:** five-spoke wheels replace the model's turbine rims.
- **Lower body:** the black cladding and chrome strips become the shipped art's tan cladding. The sills are one clean
  edge, tan below and body colour above.
- **Paint:** the panels are smoothed a little.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --disable-autoexec --python-exit-code 1 \
  --python tools/goods_icons/ev_car/render.py -- <out_dir> ev_car
python3 tools/goods_icons/ev_car/icon_export.py <out_dir>/ev_car_raw.png <out_dir>/ev_car_800.png --vib 1.0
python3 tools/goods_icons/ev_car/ev_proof.py <out_dir>
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --disable-autoexec --python-exit-code 1 \
  --python tools/goods_icons/ev_car/ev_verify.py -- <out_dir>
```

`ev_proof.py` writes the 450, 256 and 60 px tiers, the comparison sheet, the 3x crops and the DS2 well sheet.
`ev_verify.py` checks the camera, that nothing is below ground, that the charger clears the car, and that the intended
contacts touch: port and body, pistol and port, cable and pistol, cable and holster, holster and post, post and plinth.

Re-rendered from this copy at install, the 800 px master was pixel-identical to the approved render, and the check
reported no failures.

## Files

- `ev_kit.py`: `build_ev_car()`.
  - It splits the prepared model by material into labelled parts in the shipped art's colours (`EV_PARTS`, `EV_TONES`).
  - The body's ink comes from its creases and contours (`pl_mesh_lines`).
  - The interior is one flat colour, undotted, with thin 2 px lines at its main creases only.
  - `charger()` builds the post with its plinth, screen, bolt and holster, the port housing on the wing, the flat
    pistol, and the cable.
- `ev_prepped.blend`: the prepared model, saved compressed.
- `prep/ev_prep.py`: the prep script above.
- `render.py`: loads the frozen kit files plus `plastics_kit.py`, whose toon, sweep and mesh-ink helpers `ev_kit.py`
  reuses, then builds the icon.
