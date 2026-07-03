extends Node2D
## On-map animation played whenever a tile finishes being surveyed (in any view).
##
## - A thick off-white hex outline at the tile edge "shoots" a hexagon outline that
##   collapses into the centre; each pulse runs 0.5s and repeats four times (2.0s).
## - For each non-water deposit revealed, the resource's icon rises from the tile
##   over 2s, holds 0.5s, then fades over 0.5s (side by side if several). Infinite
##   deposits' icons hold a further 1s before fading. Finite deposits glow white
##   (~icon-sized); an infinite deposit glows yellow-gold and radiates roughly
##   twice as far — only that deposit's icon is gold.

const GoodIcons := preload("res://scripts/good_icons.gd")

const OFF_WHITE := Color(0.98, 0.97, 0.92)
const GOLD := Color(1.0, 0.82, 0.27)  # infinite-deposit glow
# Flat-top hex corners relative to the tile centre (tile_set 540x480).
const CORNERS: Array[Vector2] = [
	Vector2(-135.0, -240.0), Vector2(135.0, -240.0), Vector2(270.0, 0.0),
	Vector2(135.0, 240.0), Vector2(-135.0, 240.0), Vector2(-270.0, 0.0),
]
const HEX_W := 25.0          # thick outline width
const HEX_PULSE := 0.5       # one collapse
const HEX_PULSES := 4        # repeats four times -> 2.0s total
const RISE_DUR := 2.0        # icons rise over 2s
const HOLD := 0.5            # then sit stationary for 0.5s
const INF_EXTRA := 1.0       # infinite-deposit icons hold a further 1s before fading
const FADE := 0.5            # then fade over 0.5s
# Icons/glow + rise scale with the camera zoom (captured when the survey lands):
# small + short at max zoom-in, large + tall at max zoom-out, so they stay readable.
const ICON_SIZE_IN := 80.0     # at max zoom in
const ICON_SIZE_OUT := 320.0   # at max zoom out
const RISE_IN := 200.0
const RISE_OUT := 800.0
const GLOW_FACTOR := 1.25      # white glow radius relative to icon size
const GOLD_FACTOR := 2.5       # gold (infinite) glow radius relative to icon size (~200px in)
const SPACING_FACTOR := 2.6    # icon spacing relative to icon size
const GLOW_RINGS := 9

var terrain_layer: Node = null
var _fx: Array = []  # [{centre, t, icons:[{tex, x, infinite}]}]

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
	# Size/rise/spacing scale with how zoomed out the camera is right now.
	var zt := _zoom_t()
	var icon_size := lerpf(ICON_SIZE_IN, ICON_SIZE_OUT, zt)
	var rise := lerpf(RISE_IN, RISE_OUT, zt)
	var spacing := icon_size * SPACING_FACTOR
	# Resolve icons; lay them out side by side, centred on the tile.
	var icons: Array = []
	for d in deposit_goods:
		var tex: Texture2D = GoodIcons.texture_for_size(
			str(d.get("good_id", "")),
			str(d.get("internal_name", "")),
			icon_size
		)
		if tex != null:
			icons.append({"tex": tex, "infinite": bool(d.get("infinite", false))})
	var n := icons.size()
	var has_inf := false
	for i in n:
		icons[i]["x"] = (float(i) - float(n - 1) * 0.5) * spacing
		if bool(icons[i].get("infinite", false)):
			has_inf = true
	# Infinite-deposit icons hold an extra second, so the effect lives that bit longer.
	var lifetime := RISE_DUR + HOLD + FADE + (INF_EXTRA if has_inf else 0.0)
	_fx.append({"centre": centre, "t": 0.0, "icons": icons, "icon_size": icon_size,
		"rise": rise, "spacing": spacing, "lifetime": lifetime})
	set_process(true)
	queue_redraw()

## 0 at max zoom-in (largest zoom), 1 at max zoom-out (smallest zoom).
func _zoom_t() -> float:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return 0.0
	var zmax: Variant = cam.get("zoom_max")
	var zmin: Variant = cam.get("zoom_min")
	var hi: float = float(zmax) if zmax != null else 4.0
	var lo: float = float(zmin) if zmin != null else 1.0
	if absf(hi - lo) < 0.001:
		return 0.0
	return clampf((cam.zoom.x - hi) / (lo - hi), 0.0, 1.0)

func _process(delta: float) -> void:
	var alive: Array = []
	for f in _fx:
		f.t += delta
		if f.t <= float(f.lifetime):
			alive.append(f)
	_fx = alive
	queue_redraw()
	if _fx.is_empty():
		set_process(false)

func _draw() -> void:
	for f in _fx:
		_draw_collapse(f.centre, f.t)
		_draw_icons(f)

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

func _draw_icons(f: Dictionary) -> void:
	var icons: Array = f.icons
	var t: float = f.t
	if icons.is_empty() or t > float(f.lifetime):
		return
	var centre: Vector2 = f.centre
	var icon_size: float = f.icon_size
	# All icons rise together over RISE_DUR, then sit still. Each icon fades at its
	# own time (infinite icons hold an extra INF_EXTRA seconds first).
	var prog := minf(1.0, t / RISE_DUR)
	var y := centre.y - float(f.rise) * prog
	var scale := minf(1.0, 0.5 + t * 2.5)  # pop to full size in the first ~0.2s
	# White glow is capped so it never reaches a neighbour; the gold (infinite) glow
	# is larger and uncapped — icons draw on top, so no icon is obscured.
	var white_r: float = minf(icon_size * GLOW_FACTOR, float(f.spacing) * 0.5) * scale
	var gold_r: float = icon_size * GOLD_FACTOR * scale
	# Glows first, then icons on top.
	for ic in icons:
		var infinite: bool = bool(ic.get("infinite", false))
		_draw_glow(Vector2(centre.x + float(ic.x), y), gold_r if infinite else white_r,
			_icon_alpha(t, infinite), GOLD if infinite else OFF_WHITE)
	var sz := icon_size * scale
	for ic in icons:
		var pos := Vector2(centre.x + float(ic.x), y)
		# Fit the texture in the sz×sz box keeping its aspect ratio (so portrait
		# icons like crude oil aren't squashed square).
		draw_texture_rect(ic.tex, _fitted_rect(ic.tex, pos, sz), false,
			Color(1.0, 1.0, 1.0, _icon_alpha(t, bool(ic.get("infinite", false)))))

# Centred rect that fits a texture inside a square box, preserving aspect ratio.
func _fitted_rect(tex: Texture2D, center: Vector2, box: float) -> Rect2:
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var f := box / maxf(1.0, maxf(tw, th))
	var size := Vector2(tw * f, th * f)
	return Rect2(center - size * 0.5, size)

func _icon_alpha(t: float, infinite: bool) -> float:
	var fade_start := RISE_DUR + HOLD + (INF_EXTRA if infinite else 0.0)
	if t < 0.15:
		return t / 0.15
	if t > fade_start:
		return maxf(0.0, 1.0 - (t - fade_start) / FADE)
	return 1.0

func _draw_glow(pos: Vector2, r: float, a: float, col: Color) -> void:
	if r <= 1.0:
		return
	for i in range(GLOW_RINGS, 0, -1):
		draw_circle(pos, r * float(i) / float(GLOW_RINGS), Color(col.r, col.g, col.b, a * 0.13))
