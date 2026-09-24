# Rotary knob asset

`assets/ui/knob/knob_0.png` … `knob_6.png` are 512×512 transparent frames of a worn plastic selector knob, one per position. The plastic is slightly yellowed and matte, with grime where the grip meets the dish and around the dish edge, plus fine scuffs. The dish and grip sit recessed inside a raised dark grey metal ring. The key light comes from the upper left, so shadows fall to the lower right. The drop shadow is baked into the alpha channel, so the frames sit on light or dark panels. They import with mipmaps because they are drawn well below 512 px.

| Frame | Pointer |
| --- | --- |
| `knob_0` | 9 o'clock |
| `knob_1` | 10 o'clock |
| `knob_2` | 11 o'clock |
| `knob_3` | 12 o'clock |
| `knob_4` | 1 o'clock |
| `knob_5` | 2 o'clock |
| `knob_6` | 3 o'clock |

Every frame uses the same camera and the ring never moves, so swapping frames turns the knob in place. In every frame the knob's centre is at (256, 243) and the ring radius is 166 px.

## In the game

`scripts/rotary_selector.gd` is the control that uses these frames. It draws the knob with the numbers 1–7 on an arc above it and emits `value_changed(value: int)`. The player can click a number, drag the knob, scroll, or use the arrow keys. Set `knob_size` to change the drawn size.

The Settings panel's Gameplay tab uses it for the dummy "Test setting" (`SettingsPanel.test_setting`, 1–7). Like the other tabs, it only commits on Apply. The value lasts for the session and is not saved.

## Regenerating

The source is the three.js scene in `tools/knob_render/index.html`. Opening it on its own shows an interactive knob. To re-render the frames, run this from the Godot project root:

```sh
python3 tools/knob_render/export.py
```

Then open `http://127.0.0.1:8765/index.html?export` in a browser. Add `&variant=clean` to render the glossy white knob with a bright chrome ring into `assets/ui/knob_clean/` instead. The game doesn't use that variant. The page renders the seven frames and posts them to the server, which writes them into `assets/ui/knob/`. The tab title changes to "export done" when it has finished. Afterwards, reimport with `Godot --headless --path . --import`. The existing `.import` files keep the mipmap setting.
