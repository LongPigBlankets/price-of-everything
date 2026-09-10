extends Control
## Animated effects laid over a building SPRITE in the empire (supply-chain) view: chimney
## smoke / steam plumes and a furnace fire flicker. Owner spec 2026-09-10 — the plumes are
## continuous, the plume asset is tied to a chimney ANCHOR and sized by that chimney's radius
## so it can be reused on any building, and there are two colourways: STEAM (light grey with
## white tinges) and SMOKE (medium grey with darker patches).
##
## Purely visual. No sim state is touched; the only sim READ is at setup (does this
## building's recipe burn something the levy bites — same rule as the map's smoke layer,
## `building_visuals._recipe_emits_carbon`), so the map and the empire view cannot disagree
## about which chimneys are dirty.
##
## Animation runs on the wall clock in `_process` (visual only — architecture rule 2 bans sim
## logic there, not animation) and stands down while hidden.
##
## ANCHORS are in the 800x800 SPRITE's pixel space (the PNGs in assets/icons/buildings/sprites)
## and are scaled to whatever box this Control is given (the empire view draws sprites at
## 400 px). Read off `tools/…sprites_grid` sheets; refine per level as the sprites change.

const CanvasBatch := preload("res://scripts/canvas_batch.gd")
const SmokeVisuals := preload("res://scripts/smoke_visuals.gd")

const SPRITE_PX := 800.0

## kind: "auto" = smoke when the recipe emits carbon, else steam. "smoke"/"steam" force it.
## r is the chimney's radius in sprite px — it sizes the puffs, so a fat cooling tower breathes
## a big cloud and a thin flue a thin one.
## Keyed by internal name, then by LEVEL (the L1/L2/L3 sprites move their chimneys: the
## factory has no chimney at L1, the furnace merges its two stacks into one at L3). A level
## without its own entry falls back to the nearest lower one.
const ANCHORS := {
	"furnace": {
		1: {"stacks": [{"x": 450, "y": 175, "r": 30, "kind": "auto"}, {"x": 560, "y": 165, "r": 30, "kind": "auto"}],
			"fires": [{"x": 286, "y": 583, "w": 48, "h": 56, "mode": "breathe"}, {"x": 470, "y": 600, "w": 32, "h": 29, "mode": "window"},
				{"x": 543, "y": 558, "w": 32, "h": 28, "mode": "window"},
				{"x": 344, "y": 542, "w": 47, "h": 54, "mode": "pane"}, {"x": 424, "y": 534, "w": 54, "h": 58, "mode": "pane"}, {"x": 451, "y": 437, "w": 54, "h": 36, "mode": "pane"}, {"x": 497, "y": 492, "w": 54, "h": 57, "mode": "pane"}, {"x": 570, "y": 450, "w": 55, "h": 57, "mode": "pane"}]},
		2: {"stacks": [{"x": 415, "y": 150, "r": 36, "kind": "auto"}, {"x": 560, "y": 140, "r": 36, "kind": "auto"}],
			"fires": [{"x": 266, "y": 590, "w": 48, "h": 56, "mode": "breathe"}, {"x": 450, "y": 607, "w": 31, "h": 29, "mode": "window"},
				{"x": 523, "y": 565, "w": 31, "h": 28, "mode": "window"},
				{"x": 323, "y": 550, "w": 48, "h": 52, "mode": "pane"}, {"x": 404, "y": 541, "w": 54, "h": 58, "mode": "pane"}, {"x": 421, "y": 438, "w": 67, "h": 46, "mode": "pane"}, {"x": 477, "y": 499, "w": 54, "h": 58, "mode": "pane"}, {"x": 550, "y": 457, "w": 55, "h": 57, "mode": "pane"}]},
		3: {"stacks": [{"x": 455, "y": 80, "r": 40, "kind": "auto"}],
			"fires": [{"x": 243, "y": 660, "w": 48, "h": 55, "mode": "breathe"}, {"x": 427, "y": 677, "w": 32, "h": 28, "mode": "window"},
				{"x": 487, "y": 626, "w": 77, "h": 115, "mode": "breathe"},
				{"x": 301, "y": 619, "w": 47, "h": 53, "mode": "pane"}, {"x": 314, "y": 458, "w": 59, "h": 39, "mode": "pane"}, {"x": 381, "y": 611, "w": 54, "h": 57, "mode": "pane"}, {"x": 399, "y": 508, "w": 65, "h": 42, "mode": "pane"}]},
	},
	"eaf": {
		1: {"stacks": [{"x": 480, "y": 76, "r": 18, "kind": "auto"}, {"x": 550, "y": 96, "r": 18, "kind": "auto"}],
			"fires": [{"x": 238, "y": 510, "w": 137, "h": 74, "mode": "arc"}]},
		2: {"stacks": [{"x": 555, "y": 45, "r": 18, "kind": "auto"}, {"x": 600, "y": 55, "r": 18, "kind": "auto"}],
			"fires": [{"x": 315, "y": 483, "w": 137, "h": 74, "mode": "arc"}]},
		3: {"stacks": [{"x": 540, "y": 45, "r": 18, "kind": "auto"}, {"x": 590, "y": 50, "r": 18, "kind": "auto"}],
			"fires": [{"x": 272, "y": 483, "w": 137, "h": 74, "mode": "arc"}]},
	},
	"industrial_factory": {
		2: {"stacks": [{"x": 700, "y": 110, "r": 26, "kind": "auto"}], "fires": []},
		3: {"stacks": [{"x": 655, "y": 90, "r": 26, "kind": "auto"}], "fires": []},
	},
	"power_plant": {
		1: {"stacks": [{"x": 400, "y": 55, "r": 30, "kind": "auto"}], "fires": [],
			"cables": [[[625, 558], [592, 571], [560, 582]]]},
		2: {"stacks": [{"x": 395, "y": 40, "r": 30, "kind": "auto"}, {"x": 545, "y": 135, "r": 95, "kind": "steam"}], "fires": [],
			# pylon arm insulators -> the switchyard gantry, with the catenary sag the art draws
			"cables": [[[627, 507], [583, 536], [532, 555]], [[635, 542], [586, 574], [520, 598]]]},
		3: {"stacks": [{"x": 395, "y": 45, "r": 30, "kind": "auto"}, {"x": 545, "y": 120, "r": 95, "kind": "steam"}], "fires": [],
			"cables": [[[652, 447], [596, 490], [535, 515]], [[665, 490], [603, 538], [522, 567]], [[677, 537], [612, 585], [540, 610]]]},
	},
	"electrolyser": {
		2: {"stacks": [], "fires": [],
			"cables": [[[330, 147], [303, 245], [262, 340]], [[322, 182], [296, 288], [258, 380]]]},
	},
	"petro_refinery": {
		1: {"stacks": [],
			"fires": [{"x": 608, "y": 220, "rx": 16, "ry": 14, "lick": 72, "lean": 10}]},
		2: {"stacks": [],
			"fires": [{"x": 605, "y": 265, "rx": 16, "ry": 14, "lick": 72, "lean": 10}, {"x": 658, "y": 243, "rx": 16, "ry": 14, "lick": 72, "lean": 10}]},
		3: {"stacks": [],
			"fires": [{"x": 633, "y": 254, "rx": 16, "ry": 14, "lick": 72, "lean": 10}, {"x": 692, "y": 235, "rx": 16, "ry": 14, "lick": 72, "lean": 10},
				{"x": 758, "y": 192, "rx": 16, "ry": 14, "lick": 72, "lean": 10}]},
	},
	"poly_plant": {
		1: {"stacks": [{"x": 570, "y": 206, "r": 12, "kind": "steam"}], "fires": []},
		2: {"stacks": [{"x": 630, "y": 120, "r": 16, "kind": "steam"}, {"x": 700, "y": 135, "r": 16, "kind": "steam"}], "fires": []},
		3: {"stacks": [{"x": 550, "y": 160, "r": 16, "kind": "steam"}, {"x": 630, "y": 200, "r": 16, "kind": "steam"}], "fires": []},
	},
	"chem_plant": {
		1: {"stacks": [{"x": 310, "y": 296, "r": 16, "kind": "steam"}], "fires": []},
		2: {"stacks": [{"x": 480, "y": 300, "r": 16, "kind": "steam"}, {"x": 385, "y": 480, "r": 14, "kind": "steam"}], "fires": []},
		3: {"stacks": [{"x": 310, "y": 46, "r": 16, "kind": "steam"}, {"x": 480, "y": 380, "r": 16, "kind": "steam"}], "fires": []},
	},
	"assembly_plant": {
		2: {"stacks": [{"x": 200, "y": 110, "r": 22, "kind": "steam"}], "fires": []},
		3: {"stacks": [{"x": 210, "y": 126, "r": 20, "kind": "steam"}], "fires": []},
	},
}


## The anchor set for a building at a level: its own, else the nearest LOWER level's, else
## empty (a factory at L1 has no chimney and gets nothing).
static func anchors_for(internal_name: String, level: int) -> Dictionary:
	var lv := anchor_level(internal_name, level)
	return ANCHORS[internal_name][lv] if lv > 0 else {}


## The level whose anchor set (and light mask) a building at `level` uses; 0 = none.
static func anchor_level(internal_name: String, level: int) -> int:
	var by_level: Dictionary = ANCHORS.get(internal_name, {})
	var lv := level
	while lv >= 1:
		if by_level.has(lv):
			return lv
		lv -= 1
	return 0


static func light_mask_for(internal_name: String, level: int) -> Texture2D:
	var key := "%s_lvl%d" % [internal_name, level]
	if not _light_masks.has(key):
		var path := LIGHT_MASK_DIR + key + ".png"
		_light_masks[key] = load(path) if ResourceLoader.exists(path) else null
	return _light_masks[key]


## Plume model (the map's `smoke_visuals` numbers, in chimney radii). PUFFS overlapping
## puffs per stack, each living PERIOD seconds, staggered evenly — so a new puff is always
## rising while the last is fading and the plume never breaks (owner: continuous).
const PERIOD := 2.6
const PUFFS := 3
const START_SCALE := 1.3
const END_SCALE := 3.6
## Drift in chimney radii over a puff's life, and its direction in SPRITE space: up, leaning
## north-east the way the map's smoke does (the sprites share the map's isometric).
const DRIFT_R := 5.5
const DRIFT_DIR := Vector2(0.28, -1.0)
const SPIN := PI * 0.4

## Two colourways (owner spec). Each puff is a base disc plus two smaller PATCHES offset
## inside it: darker for smoke, white-tinged for steam.
const SMOKE_BASE := Color(0.46, 0.45, 0.44)
const SMOKE_PATCH := Color(0.30, 0.29, 0.29)
const STEAM_BASE := Color(0.84, 0.86, 0.87)
const STEAM_PATCH := Color(0.97, 0.98, 0.98)
const PEAK_ALPHA := 0.92

## Fire. Two kinds of entry:
##   MASKED (`x,y,w,h` = a box in sprite px, `mode`): the light source is the sprite's own lit
##   pixels inside that box, read from a LIGHT MASK cut from the sprite (assets/fx/light/
##   <building>_lvl<N>.png, white with the orange pixels' alpha — `tools/…` recipe in memory).
##   So a doorway lights exactly its doorway shape, a window its pane, and the EAF crucible its
##   molten surface with the three electrodes cut out (owner 2026-09-10: "the glow shows
##   through the walls"; "light from the molten liquid only, partially blocked by the rods").
##     "breathe" — a doorway: brightness GROWS and RECEDES on two slow sines, never off.
##     "window"  — a small lit window: a FAINT flickering light.
##     "pane"    — a thick navy glazed window: some of the yellow light inside shows through,
##                 reduced (the mask holds these at half alpha) and slowly varying.
##     "arc"     — the crucible: a hot spot that SHIFTS about the surface (its own canvas item
##                 with a small additive shader) under an arc's irregular flicker.
##   Chimney rings are lit in the art but are NOT light sources (owner) — not listed.
##   ELLIPSE (`x,y,rx,ry`): a soft additive glow, used only under the refinery flame licks.
const FIRE_CORE := Color(1.0, 0.72, 0.30)
const FIRE_HALO := Color(1.0, 0.42, 0.10)
const LIGHT_MASK_DIR := "res://assets/fx/light/"
const ARC_SHADER := """
shader_type canvas_item;
render_mode blend_add;
uniform vec2 hot = vec2(0.5, 0.5);
uniform float hot_r = 0.05;
uniform float base = 0.4;
uniform float peak = 0.8;
uniform vec4 tint : source_color = vec4(1.0, 0.72, 0.30, 1.0);
void fragment() {
	vec4 m = texture(TEXTURE, UV);
	float d = distance(UV, hot) / hot_r;
	float g = base + peak * exp(-d * d);
	COLOR = vec4(tint.rgb * g, m.a * tint.a);
}
"""
static var _arc_shader: Shader = null
static var _light_masks: Dictionary = {}

## FLAME LICKS (owner 2026-09-10: "actual fire in the style we've been using"). A fire anchor
## with `lick: h` also draws a Blender-authored flame — a cluster of inked tongues
## (`blender-assets/goods_icon_batch4_flames.py`, four seeds, 256 px) — h SPRITE px tall,
## rooted just below the glow's centre (`ry` * 0.7 down: the door sill, the heater tip). The
## variant hops FLAME_FPS times a second on a golden-ratio walk so consecutive frames never
## repeat and no cycle shows; height and width breathe on two sines; the whole thing leans
## `lean` degrees (screen-right positive, the refinery's wind) plus a small sway, and now and
## then it is mirrored. The additive glow stays underneath: it is what lights the sprite.
## Only the refinery's fired heaters have licks (owner: no fires at furnace doorways).
const FLAME_TEX: Array = [
	preload("res://assets/fx/flames/flame_0.png"), preload("res://assets/fx/flames/flame_1.png"),
	preload("res://assets/fx/flames/flame_2.png"), preload("res://assets/fx/flames/flame_3.png"),
]
const FLAME_TEX_BASE := 245.0 / 256.0   # the flame's root sits this far down its canvas
const FLAME_FPS := 9.0

## ELECTRICITY PULSES along the traced cables (owner, 2026-09-10): short bright charges
## sliding along each catenary at a constant speed, sag and all — the polyline IS the cable
## the art draws, so a pulse follows its exact shape. Sizes are in SPRITE px and scale with
## the box like everything else here.
const PULSE_SPEED := 130.0        # sprite px per second
const PULSE_SPACING := 70.0       # between pulses along one cable
const PULSE_LEN := 22.0
const PULSE_TINT := Color(1.0, 0.92, 0.55)

## Blender-authored puff sprites (owner 2026-09-10: the LOOK comes from Blender, the motion
## stays here). Five seeds per colourway, house ink + halftone baked in, 256 px, mipmapped.
## `blender-assets/goods_icon_batch3_fx.py` makes them.
const PUFF_SMOKE_TEX: Array = [
	preload("res://assets/fx/puffs/puff_smoke_0.png"), preload("res://assets/fx/puffs/puff_smoke_1.png"),
	preload("res://assets/fx/puffs/puff_smoke_2.png"), preload("res://assets/fx/puffs/puff_smoke_3.png"),
	preload("res://assets/fx/puffs/puff_smoke_4.png"),
]
const PUFF_STEAM_TEX: Array = [
	preload("res://assets/fx/puffs/puff_steam_0.png"), preload("res://assets/fx/puffs/puff_steam_1.png"),
	preload("res://assets/fx/puffs/puff_steam_2.png"), preload("res://assets/fx/puffs/puff_steam_3.png"),
	preload("res://assets/fx/puffs/puff_steam_4.png"),
]
## The cloud fills ~92% of its 256 canvas; a puff of "radius" r is drawn as a square of side
## 2 r * this, so the visible cloud spans about 2 r like the polygon puff did.
const PUFF_TEX_SPAN := 1.12

static var _disc_tris := PackedVector2Array()

var _stacks: Array = []      # [{pos: Vector2 (local px), r: float, smoke: bool, seed: float}]
var _fires: Array = []       # ellipse: {pos, rx, ry, lick, lean, seed}; masked: {rect, region, mode, seed}
var _arcs: Array = []        # [{item: Control, mat: ShaderMaterial, region: Rect2, seed}]
var _light_mask: Texture2D = null
var _cables: Array = []      # [PackedVector2Array] local px, the traced catenaries
var _clock := 0.0
var _fire_layer: Control = null


## Same rule as the map's smoke layer: the recipe burns something the carbon levy bites.
static func recipe_emits_carbon(instance_id: String) -> bool:
	var inst: Dictionary = MatchState.get_building(instance_id)
	if inst.is_empty():
		return false
	var recipe: Dictionary = Catalog.get_recipe(str(inst.get("recipe_id", "")))
	for input_value in recipe.get("inputs", []):
		var gid := str((input_value as Dictionary).get("good_id", ""))
		if gid != "" and float(Catalog.get_good(gid).get("co2_tax_multiplier", 0.0)) > 0.0:
			return true
	return false


static func has_effects(internal_name: String, level: int) -> bool:
	return not anchors_for(internal_name, level).is_empty()


## `box_px` is the size this Control draws the 800px sprite at (the empire view: 400).
func setup(internal_name: String, level: int, carbon: bool, seed_text: String, box_px: float) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var spec: Dictionary = anchors_for(internal_name, level)
	var k := box_px / SPRITE_PX
	var i := 0
	for st_value in spec.get("stacks", []):
		var st: Dictionary = st_value
		var kind := str(st.get("kind", "auto"))
		var smoke := carbon if kind == "auto" else kind == "smoke"
		_stacks.append({
			"pos": Vector2(float(st["x"]), float(st["y"])) * k,
			"r": float(st["r"]) * k,
			"smoke": smoke,
			"seed": float((hash(seed_text + "|s%d" % i) % 1000)) / 1000.0,
		})
		i += 1
	_light_mask = light_mask_for(internal_name, anchor_level(internal_name, level))
	for f_value in spec.get("fires", []):
		var f: Dictionary = f_value
		var seed_val := float((hash(seed_text + "|f%d" % i) % 1000)) / 1000.0
		i += 1
		if f.has("w"):
			if _light_mask == null:
				continue
			var region := Rect2(float(f["x"]), float(f["y"]), float(f["w"]), float(f["h"]))
			_fires.append({
				"rect": Rect2(region.position * k, region.size * k),
				"region": region,
				"mode": str(f.get("mode", "breathe")),
				"seed": seed_val,
			})
			continue
		_fires.append({
			"pos": Vector2(float(f["x"]), float(f["y"])) * k,
			"rx": float(f["rx"]) * k, "ry": float(f["ry"]) * k,
			"lick": float(f.get("lick", 0.0)) * k,
			"lean": deg_to_rad(float(f.get("lean", 0.0))),
			"seed": seed_val,
		})
	for c_value in spec.get("cables", []):
		var pts := PackedVector2Array()
		for xy in c_value:
			pts.append(Vector2(float(xy[0]), float(xy[1])) * k)
		if pts.size() >= 2:
			_cables.append(pts)
	if not _fires.is_empty() or not _cables.is_empty():
		# Fire and the electricity pulses are ADDITIVE (they light the sprite around them);
		# smoke is not. Separate canvas item.
		_fire_layer = Control.new()
		_fire_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fire_layer.position = Vector2.ZERO
		_fire_layer.size = size
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_fire_layer.material = mat
		_fire_layer.draw.connect(_draw_fires)
		add_child(_fire_layer)
	for f_value in _fires:
		var f: Dictionary = f_value
		if f.has("region") and f["mode"] == "arc":
			_add_arc(f)
	set_process(not _stacks.is_empty() or not _fires.is_empty() or not _cables.is_empty())


## The crucible's shifting light: its own canvas item, because the hot spot is a shader
## uniform (a gaussian in the mask's UV) and a material is per item.
func _add_arc(f: Dictionary) -> void:
	if _arc_shader == null:
		_arc_shader = Shader.new()
		_arc_shader.code = ARC_SHADER
	var item := Control.new()
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.position = Vector2.ZERO
	item.size = size
	var mat := ShaderMaterial.new()
	mat.shader = _arc_shader
	mat.set_shader_parameter("tint", Color(FIRE_CORE.r, FIRE_CORE.g, FIRE_CORE.b, 1.0))
	item.material = mat
	var rect: Rect2 = f["rect"]
	var region: Rect2 = f["region"]
	item.draw.connect(func() -> void: item.draw_texture_rect_region(_light_mask, rect, region))
	add_child(item)
	_arcs.append({"item": item, "mat": mat, "region": region, "seed": f["seed"]})


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		set_process(is_visible_in_tree() and (not _stacks.is_empty() or not _fires.is_empty() or not _cables.is_empty()))


func _process(delta: float) -> void:
	_clock += delta
	if _clock > 86400.0:
		_clock = 0.0
	queue_redraw()
	if _fire_layer != null:
		_fire_layer.queue_redraw()
	for a_value in _arcs:
		var a: Dictionary = a_value
		var t := _clock + float(a["seed"]) * 37.0
		var flick := clampf(0.55 + 0.25 * sin(t * 11.3) * sin(t * 7.1 + 1.3) + 0.20 * sin(t * 2.3), 0.15, 1.0)
		var region: Rect2 = a["region"]
		# The arc wanders about the molten surface on two slow, unrelated orbits.
		var hot := region.get_center() + Vector2(region.size.x * 0.34 * sin(t * 1.9) * cos(t * 0.7 + 0.4),
			region.size.y * 0.26 * sin(t * 2.6 + 1.1))
		var mat: ShaderMaterial = a["mat"]
		mat.set_shader_parameter("hot", hot / SPRITE_PX)
		mat.set_shader_parameter("hot_r", region.size.x * 0.24 / SPRITE_PX)
		mat.set_shader_parameter("base", 0.10 + 0.12 * flick)
		mat.set_shader_parameter("peak", 0.45 + 0.35 * flick)


func _draw() -> void:
	_draw_licks()
	for st_value in _stacks:
		var st: Dictionary = st_value
		var seed_val: float = st["seed"]
		var spin_dir := 1.0 if seed_val < 0.5 else -1.0
		for j in PUFFS:
			# Evenly staggered ages: one puff is always young while another is old.
			var p := fposmod(_clock / PERIOD + seed_val + float(j) / float(PUFFS), 1.0)
			_draw_puff(st["pos"], st["r"], p, bool(st["smoke"]), spin_dir, int(seed_val * 97.0) + j)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## One textured flame per lick anchor, rooted at the anchor and re-rolled FLAME_FPS times a
## second. Drawn on THIS (normal-blend) item so the ink outline stays ink; the glow layer
## above adds the light.
func _draw_licks() -> void:
	for f_value in _fires:
		var f: Dictionary = f_value
		var h: float = float(f.get("lick", 0.0))
		if h <= 0.0:
			continue
		var s: float = f["seed"]
		var t := _clock + s * 53.0
		var frame := int(floor(t * FLAME_FPS))
		# Golden-ratio walk through the four seeds: never the same frame twice running.
		var variant := int(fmod(float(frame) * 2.618034 + s * 4.0, 4.0))
		var flip := -1.0 if (frame * 7 + int(s * 11.0)) % 5 == 0 else 1.0
		var breathe := 0.88 + 0.24 * (0.5 + 0.5 * sin(t * 9.7) * sin(t * 6.1 + 0.7))
		var widen := 0.94 + 0.12 * (0.5 + 0.5 * sin(t * 7.9 + 2.0))
		var rot: float = f["lean"] + 0.07 * sin(t * 8.3) * sin(t * 3.1)
		var tall := h * breathe
		var wide := h * widen
		var root: Vector2 = f["pos"] + Vector2(0.0, float(f["ry"]) * 0.7)
		draw_set_transform(root, rot, Vector2(flip, 1.0))
		draw_texture_rect(FLAME_TEX[variant], Rect2(-wide * 0.5, -tall * FLAME_TEX_BASE, wide, tall),
			false, Color(1.0, 1.0, 1.0, 0.97))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_puff(origin: Vector2, base_r: float, p: float, smoke: bool, spin_dir: float, variant: int) -> void:
	var travelled := 1.0 - pow(1.0 - p, 1.7)
	var centre := origin + DRIFT_DIR.normalized() * (DRIFT_R * base_r) * travelled
	var radius := base_r * lerpf(START_SCALE, END_SCALE, pow(p, 0.75))
	var alpha := PEAK_ALPHA * pow(1.0 - p, 1.15)
	if alpha <= 0.004:
		return
	var spin := p * SPIN * spin_dir
	var texs: Array = PUFF_SMOKE_TEX if smoke else PUFF_STEAM_TEX
	var tex: Texture2D = texs[variant % texs.size()]
	var half := radius * PUFF_TEX_SPAN
	draw_set_transform(centre, spin, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-half, -half, 2.0 * half, 2.0 * half), false, Color(1, 1, 1, alpha))


func _draw_fires() -> void:
	if _fire_layer == null:
		return
	_draw_pulses()
	if _fires.is_empty():
		return
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for f_value in _fires:
		var f: Dictionary = f_value
		var s: float = f["seed"]
		var t := _clock * 1.0 + s * 37.0
		# Irregular flicker: two incommensurate rates plus a slow breath.
		var flick := clampf(0.55 + 0.25 * sin(t * 11.3) * sin(t * 7.1 + 1.3) + 0.20 * sin(t * 2.3), 0.15, 1.0)
		if f.has("region"):
			var mode: String = f["mode"]
			if mode == "arc":
				continue   # its own item, see _add_arc
			var a: float
			if mode == "window":
				a = 0.12 + 0.16 * flick
			elif mode == "pane":
				var glow := 0.5 + 0.5 * sin(t * 0.9) * sin(t * 0.37 + 1.0)
				a = 0.22 + 0.20 * glow + 0.06 * flick
			else:
				# Grow and recede: a slow swell with a slower one under it, never off.
				var swell := 0.6 * (0.5 + 0.5 * sin(t * 1.7)) + 0.4 * (0.5 + 0.5 * sin(t * 0.61 + 2.0))
				a = 0.15 + 0.55 * swell
			_fire_layer.draw_texture_rect_region(_light_mask, f["rect"], f["region"],
				Color(FIRE_CORE.r, FIRE_CORE.g, FIRE_CORE.b, a))
			continue
		if _disc_tris.is_empty():
			var disc := PackedVector2Array()
			for i in 24:
				var ang := TAU * float(i) / 24.0
				disc.append(Vector2(cos(ang), sin(ang)))
			_disc_tris = CanvasBatch.polygon_soup(disc)
		var pos: Vector2 = f["pos"]
		var rx: float = f["rx"]; var ry: float = f["ry"]
		_ellipse(pts, cols, pos, rx * 1.45, ry * 1.45, Color(FIRE_HALO.r, FIRE_HALO.g, FIRE_HALO.b, 0.22 * flick))
		_ellipse(pts, cols, pos, rx, ry, Color(FIRE_CORE.r, FIRE_CORE.g, FIRE_CORE.b, 0.34 * flick))
		_ellipse(pts, cols, pos, rx * 0.5, ry * 0.55, Color(1.0, 0.92, 0.70, 0.32 * flick))
	if not pts.is_empty():
		CanvasBatch.flush(_fire_layer, pts, cols)


func _draw_pulses() -> void:
	if _cables.is_empty():
		return
	var k: float = size.x / SPRITE_PX
	var spacing := PULSE_SPACING * k
	var plen := PULSE_LEN * k
	var travelled := fmod(_clock * PULSE_SPEED * k, spacing)
	for pts in _cables:
		var total := 0.0
		for i in range(1, pts.size()):
			total += pts[i - 1].distance_to(pts[i])
		if total <= 0.0:
			continue
		var head := travelled
		while head - plen < total:
			var lo_d := maxf(0.0, head - plen)
			var hi_d := minf(total, head)
			if hi_d > lo_d:
				_draw_arc_segment(pts, lo_d, hi_d, k)
			head += spacing


## Draw the part of a polyline between arc lengths `start` and `end`, as a glowing line.
func _draw_arc_segment(pts: PackedVector2Array, start: float, end: float, k: float) -> void:
	var walked := 0.0
	for i in range(1, pts.size()):
		var length := pts[i - 1].distance_to(pts[i])
		var lo := maxf(start, walked)
		var hi := minf(end, walked + length)
		if hi > lo and length > 0.0:
			var a := pts[i - 1].lerp(pts[i], (lo - walked) / length)
			var b := pts[i - 1].lerp(pts[i], (hi - walked) / length)
			for band in [[18.0, 0.12], [9.0, 0.32], [3.8, 1.0]]:
				_fire_layer.draw_line(a, b, Color(PULSE_TINT.r, PULSE_TINT.g, PULSE_TINT.b, float(band[1])), float(band[0]) * k, true)
		walked += length


func _ellipse(pts: PackedVector2Array, cols: PackedColorArray, centre: Vector2, rx: float, ry: float, col: Color) -> void:
	var base := pts.size()
	pts.resize(base + _disc_tris.size())
	cols.resize(base + _disc_tris.size())
	for i in _disc_tris.size():
		pts[base + i] = centre + Vector2(_disc_tris[i].x * rx, _disc_tris[i].y * ry)
		cols[base + i] = col
