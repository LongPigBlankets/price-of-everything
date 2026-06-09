extends Node2D
## On-map animation played whenever a tile finishes being surveyed (in any view).
##
## - A thick off-white hex outline at the tile edge "shoots" a hexagon outline that
##   collapses into the centre; this pulse runs over 0.3s and repeats twice (0.6s).
## - For each non-water deposit revealed, the resource's icon rises from the tile
##   over 1s (side by side if several), each haloed by a white glow that radiates
##   ~100px but is capped so it never runs over a neighbouring icon.

const GoodIcons := preload("res://scripts/good_icons.gd")

const OFF_WHITE := Color(0.98, 0.97, 0.92)
# Flat-top hex corners relative to the tile centre (tile_set 540x480).
const CORNERS: Array[Vector2] = [
	Vector2(-135.0, -240.0), Vector2(135.0, -240.0), Vector2(270.0, 0.0),
	Vector2(135.0, 240.0), Vector2(-135.0, 240.0), Vector2(-270.0, 0.0),
]
const HEX_W := 25.0          # thick outline width
const HEX_PULSE := 0.5       # one collapse
const HEX_PULSES := 2        # repeats twice -> 1.0s total
const ICON_DUR := 1.0        # icons rise over 1s
const ICON_RISE := 200.0
const ICON_SIZE := 80.0
const ICON_SPACING := 210.0
const GLOW_R := 100.0
const GLOW_RINGS := 9

var terrain_layer: Node = null
var _fx: Array = []  # [{centre, t, icons:[{tex, x}]}]

func _ready() -> void:
	z_index = 80  # above the world overlays
	set_process(false)
	MatchState.tile_survey_completed.connect(_on_tile_surveyed)

func _on_tile_surveyed(tile_id: String, deposit_goods: Array) -> void:
	if terrain_layer == null or not terrain_layer.has_method("id_to_coord"):
		return
	var coord: Vector2i = terrain_layer.id_to_coord(tile_id)
	if coord == Vector2i(-1, -1):
		return
	var centre: Vector2 = terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(coord))
	# Resolve icons; lay them out side by side, centred on the tile.
	var icons: Array = []
	for d in deposit_goods:
		var tex: Texture2D = GoodIcons.texture_for(str(d.get("good_id", "")), str(d.get("internal_name", "")))
		if tex != null:
			icons.append({"tex": tex})
	var n := icons.size()
	for i in n:
		icons[i]["x"] = (float(i) - float(n - 1) * 0.5) * ICON_SPACING
	_fx.append({"centre": centre, "t": 0.0, "icons": icons})
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	var alive: Array = []
	for f in _fx:
		f.t += delta
		if f.t <= ICON_DUR:
			alive.append(f)
	_fx = alive
	queue_redraw()
	if _fx.is_empty():
		set_process(false)

func _draw() -> void:
	for f in _fx:
		_draw_collapse(f.centre, f.t)
		_draw_icons(f.centre, f.t, f.icons)

func _draw_collapse(centre: Vector2, t: float) -> void:
	var total := HEX_PULSE * float(HEX_PULSES)
	if t > total:
		return
	# Persistent thick boundary outline, fading over the whole sequence.
	var fade := 1.0 - t / total
	draw_polyline(_hex(centre, 1.0), Color(OFF_WHITE.r, OFF_WHITE.g, OFF_WHITE.b, fade * 0.85), HEX_W, true)
	# The collapsing hexagon for the current pulse: full size -> centre.
	var p: float = fmod(t, HEX_PULSE) / HEX_PULSE
	var s := 1.0 - p
	draw_polyline(_hex(centre, s), Color(OFF_WHITE.r, OFF_WHITE.g, OFF_WHITE.b, 1.0 - p * 0.2),
		maxf(2.0, HEX_W * s), true)

func _hex(centre: Vector2, s: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for c in CORNERS:
		pts.append(centre + c * s)
	pts.append(centre + CORNERS[0] * s)
	return pts

func _draw_icons(centre: Vector2, t: float, icons: Array) -> void:
	if icons.is_empty() or t > ICON_DUR:
		return
	var prog := t / ICON_DUR
	var y := centre.y - ICON_RISE * prog
	var alpha := 1.0
	if t < 0.15:
		alpha = t / 0.15
	elif t > 0.7:
		alpha = maxf(0.0, 1.0 - (t - 0.7) / 0.3)
	var scale := minf(1.0, 0.5 + prog * 2.5)  # pop to full size in the first ~0.2s
	var glow_r: float = minf(GLOW_R, ICON_SPACING * 0.5) * scale
	# Glows first, then icons on top — so a glow never obscures a neighbouring icon.
	for ic in icons:
		_draw_glow(Vector2(centre.x + float(ic.x), y), glow_r, alpha)
	var sz := ICON_SIZE * scale
	for ic in icons:
		var pos := Vector2(centre.x + float(ic.x), y)
		draw_texture_rect(ic.tex, Rect2(pos - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false,
			Color(1.0, 1.0, 1.0, alpha))

func _draw_glow(pos: Vector2, r: float, a: float) -> void:
	if r <= 1.0:
		return
	for i in range(GLOW_RINGS, 0, -1):
		draw_circle(pos, r * float(i) / float(GLOW_RINGS), Color(1.0, 1.0, 1.0, a * 0.13))
