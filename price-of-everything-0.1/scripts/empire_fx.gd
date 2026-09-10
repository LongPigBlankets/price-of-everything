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
			"fires": [{"x": 435, "y": 337, "rx": 46, "ry": 18}, {"x": 569, "y": 337, "rx": 46, "ry": 18},
				{"x": 309, "y": 610, "rx": 24, "ry": 28}, {"x": 558, "y": 571, "rx": 15, "ry": 13}, {"x": 485, "y": 613, "rx": 15, "ry": 13}]},
		2: {"stacks": [{"x": 415, "y": 150, "r": 36, "kind": "auto"}, {"x": 560, "y": 140, "r": 36, "kind": "auto"}],
			"fires": [{"x": 549, "y": 345, "rx": 46, "ry": 18}, {"x": 415, "y": 345, "rx": 38, "ry": 15},
				{"x": 289, "y": 617, "rx": 24, "ry": 28}, {"x": 538, "y": 578, "rx": 15, "ry": 13}, {"x": 464, "y": 620, "rx": 15, "ry": 13}]},
		3: {"stacks": [{"x": 455, "y": 80, "r": 40, "kind": "auto"}],
			"fires": [{"x": 527, "y": 414, "rx": 46, "ry": 18}, {"x": 395, "y": 415, "rx": 38, "ry": 15},
				{"x": 524, "y": 683, "rx": 38, "ry": 58}, {"x": 266, "y": 686, "rx": 24, "ry": 28}, {"x": 442, "y": 690, "rx": 15, "ry": 13}]},
	},
	"eaf": {
		1: {"stacks": [{"x": 480, "y": 76, "r": 18, "kind": "auto"}, {"x": 550, "y": 96, "r": 18, "kind": "auto"}],
			"fires": [{"x": 305, "y": 550, "rx": 66, "ry": 34, "mode": "arc"}, {"x": 304, "y": 604, "rx": 36, "ry": 10}]},
		2: {"stacks": [{"x": 555, "y": 45, "r": 18, "kind": "auto"}, {"x": 600, "y": 55, "r": 18, "kind": "auto"}],
			"fires": [{"x": 382, "y": 523, "rx": 66, "ry": 34, "mode": "arc"}, {"x": 374, "y": 626, "rx": 30, "ry": 18}]},
		3: {"stacks": [{"x": 540, "y": 45, "r": 18, "kind": "auto"}, {"x": 590, "y": 50, "r": 18, "kind": "auto"}],
			"fires": [{"x": 339, "y": 523, "rx": 66, "ry": 34, "mode": "arc"}, {"x": 331, "y": 626, "rx": 30, "ry": 18}]},
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
	var by_level: Dictionary = ANCHORS.get(internal_name, {})
	var lv := level
	while lv >= 1:
		if by_level.has(lv):
			return by_level[lv]
		lv -= 1
	return {}


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

## Fire: an additive warm glow on a lit opening. `mode` (owner 2026-09-10):
##   "breathe" (default) — the furnace's windows, doorways and hot bands GROW and RECEDE on
##       two slow sines: no flicker, no flame (owner: "the furnace doesn't need flames").
##   "arc"  — the EAF crucible: a glow that SHIFTS about inside the crucible (the arc wanders
##       between the electrodes) with the fast irregular flicker of an arc.
##   licks — a fire with `lick` also draws a textured flame (refinery heaters only).
const FIRE_CORE := Color(1.0, 0.72, 0.30)
const FIRE_HALO := Color(1.0, 0.42, 0.10)

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
var _fires: Array = []       # [{pos, rx, ry, seed}]
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
	for f_value in spec.get("fires", []):
		var f: Dictionary = f_value
		_fires.append({
			"pos": Vector2(float(f["x"]), float(f["y"])) * k,
			"rx": float(f["rx"]) * k, "ry": float(f["ry"]) * k,
			"lick": float(f.get("lick", 0.0)) * k,
			"lean": deg_to_rad(float(f.get("lean", 0.0))),
			"mode": str(f.get("mode", "breathe")),
			"seed": float((hash(seed_text + "|f%d" % i) % 1000)) / 1000.0,
		})
		i += 1
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
	set_process(not _stacks.is_empty() or not _fires.is_empty() or not _cables.is_empty())


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
		var h: float = f["lick"]
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
	if _disc_tris.is_empty():
		var disc := PackedVector2Array()
		for i in 24:
			var a := TAU * float(i) / 24.0
			disc.append(Vector2(cos(a), sin(a)))
		_disc_tris = CanvasBatch.polygon_soup(disc)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for f_value in _fires:
		var f: Dictionary = f_value
		var s: float = f["seed"]
		var t := _clock * 1.0 + s * 37.0
		var pos: Vector2 = f["pos"]
		var rx: float = f["rx"]; var ry: float = f["ry"]
		var mode: String = f["mode"]
		var flick := 1.0     # brightness
		var grow := 1.0      # size
		var hot := pos       # where the brightest spot sits
		if mode == "arc" or float(f["lick"]) > 0.0:
			# Irregular flicker: two incommensurate rates plus a slow breath.
			flick = clampf(0.55 + 0.25 * sin(t * 11.3) * sin(t * 7.1 + 1.3) + 0.20 * sin(t * 2.3), 0.15, 1.0)
			if mode == "arc":
				# The arc wanders about the crucible on two slow, unrelated orbits.
				hot = pos + Vector2(rx * 0.38 * sin(t * 1.9) * cos(t * 0.7 + 0.4), ry * 0.30 * sin(t * 2.6 + 1.1))
				grow = 0.9 + 0.2 * sin(t * 3.7)
		else:
			# Grow and recede: a slow swell with a slower one under it, never off.
			var swell := 0.6 * (0.5 + 0.5 * sin(t * 1.7)) + 0.4 * (0.5 + 0.5 * sin(t * 0.61 + 2.0))
			flick = 0.35 + 0.65 * swell
			grow = 0.82 + 0.5 * swell
		var hx := rx * grow; var hy := ry * grow
		_ellipse(pts, cols, pos, hx * 1.45, hy * 1.45, Color(FIRE_HALO.r, FIRE_HALO.g, FIRE_HALO.b, 0.22 * flick))
		_ellipse(pts, cols, pos, hx, hy, Color(FIRE_CORE.r, FIRE_CORE.g, FIRE_CORE.b, 0.34 * flick))
		_ellipse(pts, cols, hot, hx * 0.5, hy * 0.55, Color(1.0, 0.92, 0.70, 0.32 * flick))
		if mode == "arc":
			# A second, harder spot: the arc itself, tighter and brighter, on its own orbit.
			var arc := pos + Vector2(rx * 0.45 * sin(t * 2.3 + 0.9), ry * 0.35 * cos(t * 1.4))
			_ellipse(pts, cols, arc, hx * 0.22, hy * 0.28, Color(1.0, 0.97, 0.85, 0.45 * flick))
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
