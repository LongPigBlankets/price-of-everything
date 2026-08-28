extends Node2D
## Tower cranes on construction sites: the jib swings 90 degrees over 2 s, then back over
## another 2 s, forever.
##
## Same split as the chimney smoke, and for the same reason: `BuildingVisuals` repaints only
## when the view settles, so anything that moves every frame has to live on its own canvas or
## it drags several hundred buildings into a per-frame repaint. The SITE — bare beige ground
## in the shape of the building to come — is static and stays with the building; only the
## crane is here.
##
## Sits above the road layers in `main.tscn`: a tower crane is the tallest thing on the map.

const PlayerColours := preload("res://scripts/player_colours.gd")

## 2 s out, 2 s back (owner spec). The full cycle is therefore 4 s.
const SWING := 2.0
const CYCLE := SWING * 2.0
const SWEEP := PI * 0.5   # 90 degrees

## Sites on the SAME tile start a second apart (owner spec), so a tile with three sites reads
## as three independent machines instead of one clockwork. Wraps around the 4 s cycle.
const TILE_PHASE_STEP := 1.0

## Jib proportions, as fractions of the site's reach.
const BACK_JIB := 0.38
## Wide enough that the LIVERY shows. At the first pass (0.10 / 1.7 min) a jib on a typical
## 23 u site came out 2.3 u across with a 1 u ink outline down each side, so the outline ate
## most of the bar and every crane on the map read as a dark stick whatever colour the player
## had chosen. The fill has to out-measure its own keyline.
const JIB_WIDTH := 0.17
const JIB_WIDTH_MIN := 2.8
const JIB_WIDTH_MAX := 5.2
## The mast, seen from above: the disc the jib turns on.
const MAST_R := 2.6

const INK := Color("40382f")
const SHADOW := Color(0.29, 0.25, 0.21, 0.55)
const SHADOW_OFFSET := Vector2(2.2, 2.8)

## Below this many pixels of reach the jib is a scratch, and every site still costs its draw
## calls — so the layer stands down when zoomed out.
const MIN_REACH_PX := 4.0
const CULL_MARGIN := 160.0

var _visuals: Node = null
var _sites: Array = []
var _dirty := true
var _known_version := -1
var _clock := 0.0


func _ready() -> void:
	# The site list changes on events that move NO footprint (a build completing turns a site
	# into a building), so polling `footprint_version` alone would leave a finished crane
	# turning forever. The lifecycle signals are the truth; the version is the backstop for
	# a new site arriving.
	for signal_name in ["construction_started", "construction_completed", "construction_cancelled"]:
		if Construction.has_signal(signal_name):
			Construction.connect(signal_name, func(_i: String, _t: String) -> void: _dirty = true)
	set_process(true)


func _process(delta: float) -> void:
	_clock += delta
	if _clock > 86400.0:
		_clock = 0.0
	_refresh_sites()
	if not _sites.is_empty():
		queue_redraw()


func _refresh_sites() -> void:
	if _visuals == null or not is_instance_valid(_visuals):
		_visuals = get_tree().get_first_node_in_group("building_footprints")
		if _visuals == null:
			return
		_dirty = true
		_known_version = -1
	var version := int(_visuals.get("footprint_version"))
	if version != _known_version:
		_known_version = version
		_dirty = true
	if not _dirty:
		return
	_dirty = false
	var had := not _sites.is_empty()
	_sites = _visuals.call("construction_sites") if _visuals.has_method("construction_sites") else []
	if had and _sites.is_empty():
		queue_redraw()   # the last crane came down; clear the canvas


func _draw() -> void:
	if _sites.is_empty():
		return
	var ppu := _pixels_per_unit()
	if ppu <= 0.0:
		return
	var view := _visible_world_rect()
	var livery := PlayerColours.active_color()
	for site_value in _sites:
		var site: Dictionary = site_value
		var reach: float = site["reach"]
		if reach * ppu < MIN_REACH_PX:
			continue
		var at: Vector2 = site["pos"]
		if not view.has_point(at):
			continue
		_draw_crane(at, reach, float(site["base_angle"]), int(site["index"]), livery)


## Jib angle for this site right now. Out over SWING, back over SWING — a triangle wave, not
## a sine: the spec is a crane slewing between two bearings and pausing at each, which is what
## the flat turn at the ends of a triangle reads as.
func _angle_at(index: int) -> float:
	var t := fposmod(_clock + float(index) * TILE_PHASE_STEP, CYCLE)
	var u := t / SWING if t < SWING else 1.0 - (t - SWING) / SWING
	return SWEEP * u


func _draw_crane(at: Vector2, reach: float, base_angle: float, index: int, livery: Color) -> void:
	var angle := base_angle + _angle_at(index)
	var dir := Vector2.RIGHT.rotated(angle)
	var side := Vector2(-dir.y, dir.x)
	var half_w := clampf(reach * JIB_WIDTH, JIB_WIDTH_MIN, JIB_WIDTH_MAX) * 0.5
	# One bar through the mast: the long working jib one way, the short counter-jib the
	# other. Drawn as a single quad because that is what it is from directly above.
	var tip := at + dir * reach
	var tail := at - dir * reach * BACK_JIB
	var quad := PackedVector2Array([
		tail + side * half_w, tip + side * half_w,
		tip - side * half_w, tail - side * half_w,
	])
	var shadow := PackedVector2Array()
	for p in quad:
		shadow.append(p + SHADOW_OFFSET)
	draw_colored_polygon(shadow, SHADOW)
	draw_colored_polygon(quad, livery)
	var ring := quad.duplicate()
	ring.append(quad[0])
	draw_polyline(ring, INK, 1.0, true)
	# The mast last, so it caps the jib rather than being crossed by it.
	draw_circle(at + SHADOW_OFFSET, MAST_R, SHADOW)
	draw_circle(at, MAST_R, livery.darkened(0.35))
	draw_arc(at, MAST_R, 0.0, TAU, 14, INK, 1.0, true)


func _pixels_per_unit() -> float:
	var vp := get_viewport()
	if vp == null:
		return 0.0
	return vp.get_canvas_transform().get_scale().x


func _visible_world_rect() -> Rect2:
	var vp := get_viewport()
	if vp == null:
		return Rect2()
	var size := vp.get_visible_rect().size
	if size.x <= 0.0:
		return Rect2()
	return (vp.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, size)).grow(CULL_MARGIN)
