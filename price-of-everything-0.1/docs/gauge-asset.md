# Panel gauge asset

The panel gauge is built from stacked image layers, not baked frames, so the needle can point anywhere and the green, amber and red zones can be any size. The scale runs 300° clockwise from 7 o'clock, over the top, to 5 o'clock. The status LED sits in the gap at the bottom. The gauge shares the knob's dark grey raised ring, top-left light and slightly aged finish.

## Layers

`assets/ui/gauge/` holds 1024×1024 transparent PNGs, all in one frame centred on the needle's pivot. They import with mipmaps. Bottom to top:

| Layer | What it is |
| --- | --- |
| `gauge_base` | Ring, blank dial, LED socket, drop shadow |
| `gauge_band_green`, `_amber`, `_red` | That zone's colour across the whole scale, lit. The game trims each band to its share. |
| `gauge_scale` | The 11 ticks and the scale line along their outer tips |
| `gauge_led_glow` | White glow, drawn additively and tinted with the LED colour |
| `gauge_led_green`, `_amber`, `_red`, `_off` | The LED lens |
| `gauge_needle_shadow` | The needle's shadow, with the needle at 12 o'clock |
| `gauge_needle` | The needle, pointing at 12 o'clock |
| `gauge_glare` | White glass glare, drawn additively |

The needle's shadow sits 24.97 px right and down from the needle in this frame, because of the key light's slant. It turns about the point under the pivot shifted by that amount.

## In the game

`scripts/panel_gauge.gd` is a `Control` that stacks the layers. A small shader trims each band to its zone.

| Property | Meaning |
| --- | --- |
| `value` | Needle position on the scale, 0–1 |
| `green_percent` | Share of the scale that is green, starting at 7 o'clock |
| `amber_percent` | Share that is amber after the green, clamped to what green leaves. Red takes the rest. |
| `led_mode` | `AUTO` (the colour of the needle's zone), `GREEN`, `AMBER`, `RED` or `OFF` |
| `flash` | Blink the LED. In `AUTO` it always blinks while the needle is in the red. |
| `gauge_size` | Drawn size in pixels |
| `animate_needle` | Ease the needle to `value` with a slight overshoot. `snap_needle()` jumps it straight there. |

A needle value on a zone boundary counts as the lower zone, and a zone of 0% is skipped. The LED follows the settled value rather than the swinging needle, so it doesn't flicker while the needle overshoots.

Settings → Gameplay has a **Test gauge** with a slider or menu for each property. It is a live preview; nothing there is saved.

`tests/unit/test_ui.gd` covers the rules and the drawn layers for a table of zone splits, needle positions and LED modes. It also checks the Settings controls.

## Regenerating

The source is the three.js scene in `tools/gauge_render/index.html`. Opened on its own, it is an interactive gauge with the same settings in a panel and in the URL, for example `?needle=82&green=50&amber=25&led=red&flash=1`. To re-render the layers, run this from the Godot project root:

```sh
python3 tools/gauge_render/export.py
```

Then open `http://127.0.0.1:8765/index.html?export` in a browser. It posts every layer to the server, which writes them into `assets/ui/gauge/`. When it finishes, the tab title shows "export done" with the layer size, pixels per unit and needle shadow offset. If those change, update `LAYER_SIZE` and `NEEDLE_SHADOW_OFFSET` in `panel_gauge.gd`. Reimport afterwards with `Godot --headless --path . --import`; the existing `.import` files keep the mipmap setting.
