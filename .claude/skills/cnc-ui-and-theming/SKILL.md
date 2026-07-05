---
name: cnc-ui-and-theming
description: Load this before building or modifying ANY panel, dialog, overlay, tooltip, or HUD element in price-of-everything, or when a panel is slow, stale, mis-styled, or leaks clicks. Covers the DS theme system, the mandatory coalesced-refresh doctrine, the dialog and clickable-card patterns of record, PanelStack/Escape, and map-layer rendering rules.
---

# UI and theming — house rules for panels and map visuals

## Theme: DS is mandatory, and it is not a .tres

`scripts/ds.gd` (autoload `DS`) **builds the Theme programmatically at startup** and
assigns it to the root viewport — every Control inherits it. Never invent per-panel
styling; use:
- **Type variations**: `Title`, `Section`, `BuildingName`, `Body`, `Caption`,
  `Numeric`, `Primary` (buttons), `Card`, `Outlined`, `Inset`, `Build`, …
- **Tokens**: `DS.PALETTE` (colors incl. `BG_CARD`, `BORDER_SOFT`, `TEXT_MUTED`,
  `WARN`, `DANGER`, `OK`), `DS.SP` (spacing), `DS.FS` (font sizes).
- **Visual reference standard**: the Research panel (`scripts/research_panel.gd`,
  embedded in `scenes/main.tscn`) — bevels, lighting, metallic look. Match it.
- Aesthetic direction: functional WPA / mid-century cartographic (Booth poverty maps,
  Sanborn sheets). Navy cards, cream outlines, off-white plates.

## THE refresh doctrine (non-negotiable since 2026-07)

**Never rebuild UI per sim-signal emission.** `money_changed` and `stockpile_changed`
fire per transaction — dozens to hundreds of times inside one PROCESS. Panels that
rebuilt on each emission once cost hundreds of full teardown/instantiate cycles per
turn (the audit's single worst UI multiplier).

Pattern of record — **notification-bell coalescing** (`scripts/notification_bell.gd`):
```gdscript
var _refresh_queued := false
var _dirty := false            # hidden-panel variant

func _queue_refresh(_a: Variant = null) -> void:
    _dirty = true
    if _refresh_queued: return
    _refresh_queued = true
    call_deferred("_apply_refresh")

func _apply_refresh() -> void:
    _refresh_queued = false
    if not _dirty or not visible: return   # hidden: stay dirty, catch up on show
    _dirty = false
    _rebuild()                             # ONE rebuild per frame, max

func _on_visibility_changed() -> void:
    if visible and _dirty: _queue_refresh()
```
Bonus property: the deferred apply can never free a row button mid-`pressed` dispatch.
Already applied to: money_panel, tile_info_panel_v2, market_panel + market_row (rows
mark `_stale` off-screen and catch up on `visibility_changed`), stockpile_view,
building_detail_panel, notification_bell, advisor/labour tabs. Keep it that way.

## Patterns of record (copy these, don't reinvent)

| Need | Pattern | Where |
|---|---|---|
| Confirm dialog | full-rect scrim (click = cancel) + centred default `PanelContainer` card + Title/Body + optional "don't ask again" + Cancel/`Primary` confirm; `confirmed(dont_ask)`/`cancelled` signals; mounted lazily on a `CanvasLayer` (layer 130) | `scripts/buy_building_dialog.gd`, `scripts/sell_surplus_dialog.gd` |
| Clickable card with rich content | `_ClickCard` (a `PanelContainer` subclass emitting `pressed`, hover stylebox swap, `disabled`) — **never** a Button holding a container (Buttons don't size to children) | `scripts/advisor_council_tab.gd` |
| Good icon | `UIHelpers.make_framed_good_icon(good_id, internal, size)` — framed plate + hover tooltip that shows the good's NAME then any ancestor tooltip (`good_icon_hover.gd`); for bare TextureRect icons use `UIHelpers.attach_good_name_tooltip` | `scripts/ui_helpers.gd` |
| Settings row + tickbox | `UIHelpers.make_setting_row(label, UIHelpers.make_custom_checkbox())` | `scripts/ui_helpers.gd` |
| Quantity input | `SpinBox` with `update_on_text_changed = true` (house rule) | TVP stockpile |
| Toast | `MatchState.request_toast(text, "success"/"warning"/"info"/"caution")` | `toast_manager.gd` |

## Panel lifecycle and Escape

- Panels register with `PanelStack` (autoload): `push(self)` on show, `remove(self)`
  on hide (via `NOTIFICATION_VISIBILITY_CHANGED` or `visibility_changed`). Esc closes
  the top; the stack self-heals freed panels; the pause menu opens only when the stack
  is empty (`world_map._unhandled_input`).
- The HUD panel set lives in `scenes/main.tscn` under `UILayer/HUD/HUDContent`;
  bottom_menu owns open/close routing and hides siblings (`_hide_all_panels`).
- **Click-through contract**: map tile-clicks fire on mouse RELEASE and only when the
  press also reached the map (`hex_map._click_armed`) — UI consumes presses but often
  leaks releases. If clicks through your panel select tiles, your panel let the PRESS
  through: check `mouse_filter` on the panel root (STOP), not just children.

## Sim boundary

UI reads sim state + listens to signals; ALL mutations go through the sim API
(`MatchState.*`, `Construction.*`, `SpecialOrderState.*` setters). If you need a new
mutation, add the API method in the sim autoload — never poke fields from a panel.

## Map-layer visuals (world side)

- Custom `_draw()` layers, event-gated redraws, no `_process` unless animating
  (exemplar: `scripts/survey_overlay.gd`; counter-example fixed in 2026-07:
  logistics overlay used to deep-copy all shipments per frame).
- Children of the `TileMapLayer` need explicit `z_index` to beat later sibling layers
  (port dockhouses use 60 — `scripts/port_visuals.gd`).
- Per-entity nodes are banned at map scale (`cnc-architecture-contract` rule 1).
- UI-driven focus pans the camera via `camera.pan_to_world/pan_to_tile` (0.3s ease);
  direct map clicks never pan (deliberate). Manual pan/drag kills the tween.

## Verification

Every UI change ships a windowed screenshot (tool inventory + authoring skeleton:
`cnc-validation-and-qa` Leg 3). Layout numbers (colors, sizes) are checked in the
image; behavior via the panel's own test hooks where present (`_tree_has_label_text`
pattern in test_runner).

## When NOT to use this skill
- Godot API traps (sizing, headless, class_name) → `cnc-godot-discipline`
- What data to display / formulas → `cnc-economy-reference`
- Panel slow ONLY during turn resolution → check refresh doctrine here, then `cnc-performance-playbook`

## Provenance and maintenance
Compiled 2026-07-05. Re-verify:
- DS variations/tokens: read `scripts/ds.gd` PALETTE/SP/FS + theme setup.
- Coalescing still in place: `grep -ln "_refresh_queued" price-of-everything-0.1/scripts/*.gd`
- Dialog pattern: `ls price-of-everything-0.1/scripts/*dialog*.gd`
- Click-arm contract: `grep -n "_click_armed" price-of-everything-0.1/scripts/hex_map.gd`
