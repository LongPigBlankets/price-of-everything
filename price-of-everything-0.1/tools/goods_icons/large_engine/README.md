# Large engine (g_052) Blender icon

Builder for the approved large engine alternate icon,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_052_large_engine.png` (internal name `large_engine`). The
approval record, renders and proof sheets are in `artifacts/goods_large_engine/`.

The installed icon is `build_le_d2`: a heavy-duty inline six with a turbocharger, a finned motor-generator on its shaft
and a lipped output flywheel, on base rails with three cross supports. It stands for lorry, locomotive and (later) ship
engines, combustion and electric at once. It uses the fixed orthographic goods camera, the set's light, 12/4 px ink and
dots on the shaded sides. The installed revision is `large_engine_v10`.

The concept studies stay in the file and still render:
- `build_le_a` / `build_le_b` / `build_le_c` and `build_le_a2` / `build_le_c2`: the locomotive power packs.
- `build_le_d1` / `build_le_d3`: the universal engine without a motor-generator, and with an output shaft.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
blender -b --factory-startup --python-exit-code 1 --python tools/goods_icons/large_engine/render.py -- <out_dir> le_d2
python3 tools/goods_icons/large_engine/icon_export.py <out_dir>/le_d2_raw.png <out_dir>/large_engine_800.png --vib 1.0
```

Re-rendered from this folder at install, the 800 px master was pixel-identical to the approved one.

## `le_kit.py` (the installed path)

- **`le_inline2()`:** the inline six, its heads, rocker covers and doors. It also builds:
  - the cold path: compressor, charge air, intake rail and runners;
  - the hot path: runners, manifold, turbine and open stack;
  - the flywheel housing.
- **`le_motor_gen2()`:** the motor-generator drum, its fins, and the terminal box on the near flank. Three phase cables
  drop through black sleeves into the junction box on its plate. `JBOX` places the junction box.
- **`le_flywheel2()`:** the shipped icon's flywheel layout: disc, raised lip, dark recess, hub plate with ten holes, and
  a boss.
- **`le_mounts5()`:** the base rails and the rail-to-rail trapezoidal cross supports, with bolted feet.
- **`build_le_d2()`:** places the parts and sets the outline and stipple contract.

It reuses the shared kits copied beside it. `standard_lines.py` is the construction-equipment copy, with the
nearest-part fix for per-label outline weights.
