# Empire View — Implementation Plan

> A full-screen, navy node-graph alternative to the relief map. Press **Tab** to enter,
> **Tab** again to leave. Your buildings render as metallic node-panels connected by
> supply lines, over an animated amber concentric-hex screensaver background.

This plan is grounded in the existing codebase (Godot 4.6, GL Compatibility renderer).
Every API named below was verified to exist. File paths are relative to the repo root.

---

## 1. Goal & scope

When the player presses Tab, replace the map render with a navy "command screen" that shows
their empire as a network:

- **Nodes** = the player's own production / power / battery buildings. Each node is a small
  fixed-size **panel** with: building icon, building name, the building's primary **output good
  (icon + qty pill)**, and **6 RAG indicators**.
- **Edges** = lines connecting buildings that take inputs from each other (a supply graph).
- **Ports** = gold hexagons with the building icon embossed in navy (the only NPC objects shown).
- **Hidden**: all other NPC buildings, all infrastructure (roads/cables/pipes/rails).
- **Background**: navy, with thin metallic-amber concentric hex rings from several origins that
  interfere/pulse like a screensaver.
- **Node sizing**: Level 1 = base; Level 2 = +50% (×1.5); Level 3 = +50% again (×2.25) **and** a
  gold metallic rim. Panels are **zoom-invariant** — they keep constant screen size; only node
  positions and connector lines scale with zoom.
- **Layout**: by proximity (seeded from real world positions), *not* a hex grid; nodes push apart
  to keep a **≥30 px gap**.
- **Click a panel** → opens the existing building detail panel for that building.
- Panels carry a **metallic effect** like the research-panel unlock cards.
- The view **stretches full-screen** like the map.

### Design decisions to confirm (see §11)
1. **Replace vs. overlay the map.** Recommended: *replace* — hide the world/terrain/overlay
   Node2Ds and show the navy backdrop on top. Cleaner contrast, matches "instead of the map."
2. **30 px gap holds at the default (design) zoom.** Because panels are fixed-pixel and positions
   scale with zoom, the gap is exact at zoom = 1; zoom-out is handled by clustering/culling (§7.3).
3. **Edges are a static capability graph** (producer-good ∩ consumer-good), because the sim pools
   goods per tile and does not record building→building routing (see §4.3).

---

## 2. Architecture overview

The codebase already has the three patterns we need; we compose them:

| Need | Existing precedent to reuse |
|---|---|
| Full-screen toggleable overlay under the HUD | `ResearchPanel` / `VictoryPanel` (Control children of `UILayer/HUD/HUDContent`, `visible=false`, `PanelStack.push/remove`) |
| World→screen projection for zoom-invariant items | `sale_effects.gd:48` `get_viewport().get_canvas_transform() * world` |
| Counter-scaling by zoom | `infra_mapmode_markers.gd:95`, `logistics_overlay.gd:165` via `get_canvas_transform().get_scale().x` |
| Metallic panels / gold hexes / embossed text | `research_panel.gd` `_make_stylebox`, `_hex_points`, `_rounded_hex_points`, `_hex_gradient_colors`, `_draw_machined_bevel` |
| Animated GPU background | `assets/shaders/ui_blur.gdshader` is the proven `shader_type canvas_item` precedent |
| Custom 2D line/poly drawing | `hex_grid_overlay.gd`, `infra_mapmode_markers.gd`, `logistics_overlay.gd` |
| Determinism (no `randf`) | `RoadHash.pick()` (`road_hash.gd`) — already used by `building_visuals.gd` |

### Honor the project rules (CLAUDE.md)
- **Sim lives outside the scene tree** → layout/graph math goes in a plain `RefCounted`/autoload
  (`EmpireLayout`), not a Node-per-building.
- **No economic logic in frame callbacks** → `_process` only does presentation (projecting panel
  positions, `queue_redraw`).
- **No global `randi()/randf()`** → any jitter/tie-break uses `RoadHash.pick(...)`.
- **UI is read-only** → the Empire view never mutates game state; it only reads and routes clicks.

### Proposed scene subtree (added under `UILayer/HUD/HUDContent` in `scenes/main.tscn`)
```
EmpireView                (Control, full-rect, visible=false, mouse_filter=PASS→STOP on open)
├── HexFieldBg            (ColorRect, full-rect, ShaderMaterial, mouse_filter=IGNORE)   ← back-most
├── GraphWorld            (Node2D)   ← draws connector lines + node base shapes (scales w/ zoom)
│   └── EmpireCamera      (Camera2D) ← own pan/zoom; make_current() on open
└── PanelLayer            (CanvasLayer) ← ~N building panels, pixel-locked, positioned per-frame
```
> `GraphWorld`'s `_draw` renders the connectors and the per-node base shape (incl. L3 gold rim and
> port hexagons). The legible **panel chrome** (icon, name, RAG, pill) lives in `PanelLayer` so it
> never resamples/blurs with zoom. Panels are positioned each frame by projecting the node's world
> position through the canvas transform.

---

## 3. Toggle, input & lifecycle

### 3.1 Input action
Add to `project.godot` `[input]`:
```ini
toggle_empire_view={
"deadzone": 0.2,
"events": [ <InputEventKey physical_keycode=KEY_TAB> ]
}
```

### 3.2 Handling (mirror the existing `KEY_X` search-overlay branch in `world_map.gd:_unhandled_input`)
```gdscript
if event.is_action_pressed("toggle_empire_view"):
    %EmpireView.toggle()
    get_viewport().set_input_as_handled()
```
`EmpireView.toggle()`:
- **Open**: `_hide_all_panels()` (reuse `bottom_menu.gd`), hide world/terrain/overlay Node2Ds,
  build graph if signature changed, `visible=true`, `mouse_filter=STOP`, `PanelStack.push(self)`,
  `EmpireCamera.make_current()`, enable subtree processing.
- **Close**: `visible=false`, `mouse_filter=PASS`, `PanelStack.remove(self)`, restore world
  visibility, `map_camera.make_current()`, disable subtree processing.
- **Esc** while open: handled for free by `PanelStack.close_top()` (it's on the stack).

> Gate the map's `camera_controller` while EmpireView owns the screen (pause its `_process` or use
> `make_current()`) so the two cameras don't both pan.

---

## 4. Data layer (read-only)

A small `EmpireGraph` builder (RefCounted) produces the node + edge lists consumed by layout/render.

### 4.1 Enumerate nodes
```gdscript
for b in MatchState.buildings.values():
    if not MatchState.is_player_owned(b): continue          # exclude NPC (ports handled separately)
    var cat := str(Catalog.get_building(b.building_id).get("category",""))
    if cat == "infrastructure": continue                    # hide roads/cables/pipes/rails
    # node: production / power / battery
```
Per node, collect:
- `instance_id`, `building_id`, `level = int(b.get("level",1))`
- name/icon: `var bd = Catalog.get_building(b.building_id)`;
  `name = bd.display_name`; `icon = BuildingIcon.clean_texture(b.building_id, bd.internal_name)`
- output good + qty:
  ```gdscript
  var r := Catalog.get_recipe(b.recipe_id)
  var out := r.outputs[0] if r.outputs.size() > 0 else {}
  var good_id := str(out.get("good_id",""))
  var qty := int(round(float(out.get("qty",0)) * BuildingLevels.mult("output", level)))
  ```
- seed position: `BuildingVisuals.footprint_center_for(instance_id, coord)` (fallback: tile centre)

### 4.2 Ports (gold hexagons)
Source from `Catalog.all_ports()` (and/or `MatchState.buildings` entries with `building_id=="b_004"`).
Seed each at its tile centre. Render as a gold hexagon with the port building icon embossed navy
(see §6.3). Ports are **render-only** nodes — they can still be edge endpoints for bought inputs if
you later choose to model market sourcing (out of scope v1; see §11).

### 4.3 Edges (supply graph) — important caveat
The sim **pools goods per tile** (`Stockpile._by_tile[tile][good]`); it does **not** record which
building supplied which. So edges are an inferred **capability graph**, exactly like
`build_goods_flow.py` does for the static goods chart:

```gdscript
# producers[good_id] = [instance_id, ...]; consumers[good_id] = [instance_id, ...]
for node in nodes:
    var r := Catalog.get_recipe(node.recipe_id)
    for o in r.outputs: producers[o.good_id].append(node.iid)
    for i in r.inputs:  consumers[i.good_id].append(node.iid)
# edge (A -> B) when A produces good g and B consumes good g
for g in producers:
    for a in producers[g]:
        for b in consumers.get(g, []):
            if a != b: edges.append({from=a, to=b, good=g})
```
- Power is special-cased (never in Stockpile) — do **not** draw power as a goods edge; optionally
  draw power links separately later.
- Recipe swaps / level changes change edges → rebuild on the relevant signals (§4.4).

### 4.4 Rebuild triggers
Cache the graph keyed by a **signature** = sorted `instance_id`s + their levels + recipe ids.
Invalidate on `MatchState.building_added` / `building_removed` and the level-up signal. Rebuild lazily
on `open()` only if the signature changed (cheap for ~50 buildings).

---

## 5. Node layout / packing (`EmpireLayout`, RefCounted)

Two-stage, **deterministic**, computed on open / on building change (never per-frame):

1. **Seed** each node from its world position mapped into a canonical "design-zoom **layout space**"
   by a single `LAYOUT_SCALE`, chosen so average seed spacing exceeds the largest node footprint +
   gap. This is the "by proximity, not a hex grid" step.
2. **Collision-separation relaxation** (AABB push-apart, *not* springy force-directed) with a weak
   anchor pull back to the seed so geography stays recognizable.

Footprints are in **pixels at design zoom**: `half = base_half * LEVEL_SCALE[level]`, where
`LEVEL_SCALE = {1:1.0, 2:1.5, 3:2.25}`; ports use their hex AABB. The 30 px gap is folded in as an
inflated half (`half + 15`) so two just-touching inflated boxes leave 30 px between the real ones.

```gdscript
const LEVEL_SCALE := {1:1.0, 2:1.5, 3:2.25}
const PAD := 15.0          # half of the 30px gap
const MAX_ITERS := 80
const ANCHOR_PULL := 0.02

func build_layout(nodes: Array) -> void:
    nodes.sort_custom(func(a,b): return a.iid < b.iid)        # determinism
    for n in nodes:
        n.pos = n.seed
        n.inflated = n.half + Vector2(PAD, PAD)
    for _it in MAX_ITERS:
        var moved := false
        var grid := _spatial_hash(nodes)                      # cell ~= 2*max_inflated → O(n)
        for n in nodes:
            for m in grid.neighbours(n):
                if m.iid <= n.iid: continue                   # each pair once
                var d := m.pos - n.pos
                var ox := n.inflated.x + m.inflated.x - absf(d.x)
                var oy := n.inflated.y + m.inflated.y - absf(d.y)
                if ox <= 0.0 or oy <= 0.0: continue           # no overlap
                moved = true
                # push apart along least-penetration axis, split 50/50
                if ox <= oy:
                    var s := 0.5 * ox * (1.0 if d.x >= 0.0 else -1.0)
                    if absf(d.x) < 0.001: s = _det_jitter(n.iid).x  # coincident seeds
                    n.pos.x -= s; m.pos.x += s
                else:
                    var s2 := 0.5 * oy * (1.0 if d.y >= 0.0 else -1.0)
                    if absf(d.y) < 0.001: s2 = _det_jitter(n.iid).y
                    n.pos.y -= s2; m.pos.y += s2
        for n in nodes: n.pos += (n.seed - n.pos) * ANCHOR_PULL  # weak pull home
        if not moved: break                                    # early-out, layout is clean

func _det_jitter(iid: String) -> Vector2:
    var a := deg_to_rad(float(RoadHash.pick("layout|" + iid, 360)))
    return Vector2(cos(a), sin(a)) * 0.5
```
- ~50 nodes converge in well under 60 passes, sub-millisecond. Run synchronously.
- **Incremental add**: re-seed only the new node and run ~20 warm-start passes; fall back to a full
  resolve if residual overlap remains.
- The module owns **layout-space positions + half-extents only**; screen projection is the camera's job.

> Rejected: hex/grid bin-packing (kills proximity), spiral placement (ignores geography), full
> force-directed/edge-spring (non-deterministic, destroys relative position), packing in raw world
> space (gap can't hold across zooms because panels are fixed-pixel).

---

## 6. Rendering

### 6.1 Background — `empire_hex_field.gdshader` (GPU, `shader_type canvas_item`)
A single full-screen `ColorRect` with a `ShaderMaterial`. Concentric hex rings = a procedural
distance-field; interference = additive sum of several origins; pulse = `TIME`. No per-frame CPU.

Core math (pointy-top hex distance → integer rings → crisp `smoothstep` band from `fwidth`):
```glsl
shader_type canvas_item;
uniform vec4  navy_color  : source_color = vec4(0.0156, 0.0588, 0.1058, 1.0);   // DS BG_PANEL
uniform vec4  amber_color : source_color = vec4(0.9952, 0.9308, 0.7633, 1.0);   // DS ACCENT
uniform vec2  resolution = vec2(1920.0, 1080.0);
uniform float ring_spacing = 0.045;
uniform float pulse_speed  = 0.20;
uniform float line_width   = 1.4;
uniform float global_pulse = 0.4;
const int ORIGINS = 4;
uniform vec2  origins[ORIGINS];
uniform float origin_phase[ORIGINS];

float hex_dist(vec2 p){
    float q = 0.57735027*p.x - 0.33333333*p.y;
    float r = 0.66666667*p.y;
    float x=q, z=r, y=-x-z;
    float rx=floor(x+0.5), ry=floor(y+0.5), rz=floor(z+0.5);
    float dx=abs(rx-x), dy=abs(ry-y), dz=abs(rz-z);
    if (dx>dy && dx>dz) rx=-ry-rz; else if (dy>dz) ry=-rx-rz; else rz=-rx-ry;
    return (abs(rx)+abs(ry)+abs(rz))*0.5;
}
void fragment(){
    float aspect = resolution.x/resolution.y;
    vec2 p = vec2(UV.x*aspect, UV.y);
    float field = 0.0;
    for (int i=0;i<ORIGINS;i++){
        vec2 o = vec2(origins[i].x*aspect, origins[i].y);
        float d = hex_dist((p-o)/ring_spacing);
        float ring = d - (TIME*pulse_speed + origin_phase[i]);
        float w = fwidth(ring)*line_width;
        float line = smoothstep(0.5, 0.5-w, abs(fract(ring)-0.5));
        line *= exp(-d*0.06);                     // distance falloff → depth, anti-moire
        field += line;                            // additive interference
    }
    field = clamp(field, 0.0, 1.0);
    vec2 g = vec2(dFdx(field), dFdy(field));
    float sheen = pow(max(dot(normalize(g+1e-5), vec2(0.6,-0.8)), 0.0), 6.0); // metallic glint
    float breathe = 0.85 + 0.15*sin(TIME*global_pulse);
    vec3 ink = mix(amber_color.rgb, vec3(1.0), sheen*0.5);
    COLOR = vec4(mix(navy_color.rgb, ink, field*breathe), 1.0);
}
```
- `mouse_filter = IGNORE`, back-most child so it never eats clicks and panels render on top.
- Set `resolution` from GDScript on the Control's `resized` signal (aspect-correct hexes under the
  1920×1080 `canvas_items`/`expand` stretch).
- Initialize **all** `origins[4]` / `origin_phase[4]` on open (GL Compatibility array uniforms must
  be fully set; unset → origin at (0,0)). Keep intensity modest so foreground panels stay legible.
- Fallback: if web/mobile `fwidth` precision is poor, derive width from `ring_spacing` constant.

### 6.2 Node base shape — `GraphWorld._draw()` (scales with zoom)
For each node draw, at the **projected** position, the base plate behind the panel:
- L1/L2/L3 plate sized by `LEVEL_SCALE`. L3 adds a **gold metallic rim** using
  `_draw_machined_bevel` + a gold border (reuse `research_panel.gd` helpers).
- Connector lines (§6.4) drawn first (under nodes).

### 6.3 Ports — gold hexagon with embossed navy icon
Reuse the research panel's hex toolkit:
```gdscript
var pts := _hex_points(rect)                                  # or _rounded_hex_points(rect, r)
var cols := _hex_gradient_colors(pts, GOLD.lightened(0.2), GOLD.darkened(0.2))
draw_polygon(pts, cols)                                       # metallic gold fill
_draw_machined_bevel(rect, 0.0)                              # bevel/sheen
# building icon, navy-tinted, embossed (shadow + highlight + main), centered in the hex
```
Embossing = three draw passes (dark offset, light offset, main), per `research_panel.gd:1540`.

### 6.4 Connector lines
In `GraphWorld._draw()`, between projected node positions:
```gdscript
draw_polyline(PackedVector2Array([a, b]), edge_color, width, true)
```
- Color the line by the carried good (tie to `MapMode` palette) or a uniform amber; optionally a
  subtle gradient (`draw_polyline_colors`).
- Keep thickness readable: either let it scale with the graph, or `width = base_px / zoom` for
  constant screen thickness (see `infra_mapmode_markers.gd` width handling).
- Spread parallel edges with a perpendicular offset (precedent: `logistics_overlay.gd` `PARALLEL_GAP`).
- For ~50 nodes, batch where possible; `queue_redraw()` only when the camera moves or data changes.

### 6.5 Node panel chrome — `PanelLayer` Controls (pixel-locked, built once)
One `Control` per building, sized by `LEVEL_SCALE[level]` (constant in pixels — *not* zoomed):
```
NodePanel (PanelContainer, metallic stylebox via research-panel technique)
└── VBox
    ├── HBox: [building icon]  [building name label]
    ├── RAG strip: 6 indicators
    └── output: [good icon] + qty pill (overlapped badge)
```
- **Metallic look**: build the stylebox with `research_panel.gd:_make_stylebox(BG_INSET, BORDER, r, 2)`
  and, for richer chrome, a `_draw`-override that calls `_draw_machined_bevel`. Use `DS.PALETTE`
  colors only (no hardcoded hex): `BG_PANEL #040F1B`, `ACCENT/BORDER` gold, RAG `OK/WARN/DANGER`.
- **Building icon**: `BuildingIcon.clean_texture(building_id, internal_name)` (cached).
- **Output pill**: `GoodIcons.texture_for(good_id, internal_name)` + reuse
  `BuildingRow._make_qty_badge(qty, slot_size)` for the qty pill.
- **6 RAG indicators**: reuse the **building_detail_panel** set (it renders 6; the
  `tile_info_panel_v2._make_building_rag_strip` renders only 5). The six are: Power, Inputs,
  Transport duration, Transport cost, Cost-to-produce (£ dot), Net production modifier (Δ %). Pull
  colors from `BuildingStatus.power_status_color / input_status_color / cost_rag_color` (+ the
  modifier %). Set each `ColorRect.mouse_filter = IGNORE` so clicks fall through to the panel.
  *(Recommended refactor: extract the detail panel's 6-indicator builder into a shared helper so
  both panels stay in sync.)*
- Built **once** on open; only `position` is mutated per-frame and RAG colors refreshed on
  data-change signals — never rebuild children per frame, never re-bake icons per frame.

---

## 7. Zoom-invariant projection & camera

### 7.1 Per-frame projection (presentation only)
```gdscript
func _process(_dt):
    if not visible: return
    var xform := get_viewport().get_canvas_transform()       # incl. stretch scale
    for p in _panels:
        p.ctrl.position = xform * p.world_pos - p.ctrl.size * 0.5   # center; NEVER set scale
    queue_redraw()                                            # GraphWorld redraws lines/nodes
```
Panels live in a `CanvasLayer`, so camera zoom does not scale them — only their `position` moves.
This keeps fonts/icons/RAG crisp (avoids the fractional-scale blur the research panel works around).

### 7.2 Camera
Use a **dedicated** `EmpireCamera` (Camera2D), not the map's `camera_controller` (which hard-binds
to the `hex_map` group and map bounds). Reuse the *input pattern* only: WASD pan + wheel/magnify zoom.
`make_current()` on open; restore the map camera on close. Default zoom = "design zoom" so the 30 px
gaps are exact on entry; fit-to-content on open is a nice touch.

### 7.3 Anti-overlap on zoom-out (optional polish)
Because positions scale but panels don't, zooming out brings panels together. Mitigate with
**hysteresis-based** culling/clustering:
- Below a screen-gap threshold, collapse a cluster into one "N buildings" chip or fade member panels
  to dots; expand again above a higher threshold (separate collapse/expand thresholds → no flicker).
- Recompute cluster membership only when zoom crosses a threshold, not every frame.

---

## 8. Click → building detail panel
Each `NodePanel` is a real Control, so use native input — no transform inversion needed:
```gdscript
func _on_panel_gui_input(event, instance_id):
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        var b := MatchState.get_building(instance_id)
        if not b.is_empty():
            building_panel.move_to_front()
            building_panel.show_building(b)          # building_detail_panel.gd:219 (handles PanelStack)
        get_viewport().set_input_as_handled()
```
Equivalently, emit `MatchState.focus_building_requested.emit(instance_id)` to reuse the existing
deep-link path (`world_map._on_focus_building_requested`). Either works; direct `show_building` is
fewer hops. Clicks on empty graph/lines go to `GraphWorld._unhandled_input` (pan / line hit-test via
`xform.affine_inverse() * event.position`).

---

## 9. Files

### New
| File | Purpose |
|---|---|
| `scripts/empire_view.gd` | Root controller: toggle/open/close, lifecycle, per-frame projection, click routing |
| `scripts/empire_graph.gd` | RefCounted: enumerate nodes, build edges, signature/caching |
| `scripts/empire_layout.gd` | RefCounted: deterministic seed + collision-separation packing |
| `scripts/empire_graph_world.gd` | Node2D `_draw`: connector lines, node base plates, L3 rim, port hexagons |
| `scripts/empire_node_panel.gd` | Per-building panel: metallic chrome, icon, name, 6 RAG, output pill |
| `assets/shaders/empire_hex_field.gdshader` | Animated amber concentric-hex background |

### Modified
| File | Change |
|---|---|
| `project.godot` | Add `toggle_empire_view` (Tab) to `[input]` |
| `scenes/main.tscn` | Add `EmpireView` subtree under `UILayer/HUD/HUDContent` |
| `scripts/world_map.gd` | Handle the Tab action in `_unhandled_input`; hold `%EmpireView` ref |
| `scripts/camera_controller.gd` | Gate map camera while EmpireView is current (or pause its `_process`) |
| `scripts/building_detail_panel.gd` | (Optional) extract the 6-indicator RAG builder into a shared helper for reuse |

---

## 10. Milestones (incremental, each independently verifiable)
1. **Shell**: Tab toggles a full-screen navy `ColorRect` over the map; Esc/Tab closes; PanelStack +
   camera handoff correct. *(Verify: enter/leave cleanly, no input bleed.)*
2. **Data + static layout**: build node list, run packing, draw simple placeholder boxes at projected
   positions (no zoom yet). *(Verify: one box per player building, 30 px gaps, geography recognizable.)*
3. **Pan/zoom + zoom-invariant panels**: EmpireCamera; panels keep size, positions/lines scale.
4. **Node panel chrome**: real metallic panels with icon, name, 6 RAG, output pill; L2/L3 sizing; L3 rim.
5. **Edges**: connector lines from the capability graph; parallel-edge spreading.
6. **Ports**: gold embossed hexagons from `Catalog.all_ports()`.
7. **Background shader**: amber concentric-hex interference, tuned for legibility.
8. **Click-through**: panel click opens `show_building`.
9. **Polish**: zoom-out clustering/culling (§7.3); rebuild-on-change signals; fit-to-content on open.

---

## 11. Risks & open decisions
- **Replace vs overlay the map** (§1.1) — recommend replace.
- **Edges are inferred, not real routing** (§4.3). Pooled supply means lines show *capability*, not
  measured flow. If you want true per-turn volumes later, derive from `Production.produced_by_building`
  + stockpile deltas (a turn-replay feature, out of scope v1).
- **Should ports be edge endpoints** for bought (market) inputs? v1: render-only. Later: model
  market-sourced inputs as port→building edges.
- **30 px gap is a default-zoom guarantee** (§1.2). If you want it preserved at *all* zooms, that
  requires re-layout per zoom level — heavier; clustering (§7.3) is the lighter answer.
- **Two cameras**: must ensure only one is `current` (§7.2) or both pan handlers fire.
- **GL Compatibility**: array uniforms need constant size + full init; `fwidth` precision varies on
  web/mobile (have the constant-width fallback ready).
- **Legibility**: a busy amber field can wash out panels — keep field intensity modest and panels on
  opaque navy styleboxes.
- **Determinism**: any `Dictionary`-iteration order or `randf` leaks into layout jitter; key
  everything off sorted `instance_id`s and `RoadHash`.

---

## 12. Verification
- **Unit-ish (headless)**: test `empire_graph` (node filtering: NPC excluded, infra excluded, ports
  separated; edge inference) and `empire_layout` (determinism: same input → identical positions;
  ≥30 px gap satisfied; convergence within `MAX_ITERS`) via the existing `python3 tools/run_tests.py`
  harness.
- **Visual**: use the self-serve windowed screenshot path (`tools/farm_shot.tscn` pattern) to render
  the Empire view and eyeball spacing, panel sizing per level, port hexagons, and background.
- **Manual**: Tab in/out, pan/zoom keeps panels crisp and sized, click opens the right building.
