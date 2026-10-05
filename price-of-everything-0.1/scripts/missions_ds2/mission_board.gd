extends Control
## The missions panel's mimic board: one board's stations painted on dark slate enamel like a signal box's
## track diagram (res://assets/ui/bdp_v3/mission_board.png, cropped to the board). Each station is a pilot
## lamp with its name painted beside it, the stations running top to bottom: green when done, amber while
## open, off while locked. The track between stations is lit to the stations done, amber down to the open
## ones, painted on to the locked ones and all but gone on a branch the player did not take. A choice carries
## the points lever at its junction, centred until it is thrown, then towards the branch taken. The board is
## as tall as its stations need; the panel scrolls it.
## Draws only: the board's stations come from MiniQuest.mission_boards(); a click selects a station.

signal station_selected(node_id: String)

const Lamp := preload("res://scripts/bdp_v3_lamp.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const Light := preload("res://scripts/bdp_v3_light.gd")
const BOARD: Texture2D = preload("res://assets/ui/bdp_v3/mission_board.png")
const LEVER := {
	"mid": preload("res://assets/ui/bdp_v3/points_lever_mid.png"),
	"up": preload("res://assets/ui/bdp_v3/points_lever_up.png"),
	"down": preload("res://assets/ui/bdp_v3/points_lever_down.png"),
}
const TEXELS_PER_PIXEL := 2.0

## The board's grid, in logical px: a row's height, a lane's width and the margins round the stations.
const ROW_H := 74.0
const LANE_W := 280.0
const MARGIN := Vector2(48.0, 40.0)
## How far below a station the track runs before it turns towards another lane.
const JUNCTION := 30.0
const LAMP_SCALE := 0.62
const NAME_W := 230.0
const NAME_GAP := 16.0
const NAME_PX := 13
const HIT_RADIUS := 26.0

const LIT := Color(1.0, 0.93, 0.78)
const SET := Color(1.0, 0.66, 0.2)
const PAINTED := Color(0.84, 0.87, 0.83, 0.36)
const CLOSED := Color(0.6, 0.62, 0.6, 0.12)

var board: Dictionary = {}
var selected := ""
var _lamps: Dictionary = {}
var _names: Dictionary = {}


func _init() -> void:
	name = "MissionBoard"
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_filter = Control.MOUSE_FILTER_STOP


## Shows `b` (one of MiniQuest.mission_boards()), at least `min_width` wide.
func set_board(b: Dictionary, min_width: float) -> void:
	board = b
	for child in get_children():
		child.queue_free()
	_lamps = {}
	_names = {}
	var rows := 1
	for node: Variant in board.get("nodes", []) as Array:
		rows = maxi(rows, int((node as Dictionary).get("col", 0)) + 1)
	custom_minimum_size = Vector2(min_width, MARGIN.y * 2.0 + float(rows - 1) * ROW_H)
	for node: Variant in board.get("nodes", []) as Array:
		var n := node as Dictionary
		var id := str(n.get("id", ""))
		var lamp: Control = Lamp.new()
		lamp.lamp_scale = LAMP_SCALE
		lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lamp.call("set_tone", _tone(str(n.get("state", "locked"))))
		add_child(lamp)
		_lamps[id] = lamp
		var label := Label.new()
		label.text = str(n.get("title", ""))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.custom_minimum_size = Vector2(NAME_W, 0.0)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_override("font", Plate.FONT_BOLD)
		label.add_theme_font_size_override("font_size", NAME_PX)
		var state := str(n.get("state", "locked"))
		label.add_theme_color_override("font_color", DS.PALETTE.TEXT if state != "closed" else Color(DS.PALETTE.TEXT, 0.35))
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		add_child(label)
		_names[id] = label
	_place_children()
	queue_redraw()


## The centre of a station on the board: its row down from the top, its lane across, the lanes in use centred
## with room for the names to their right.
func station_point(node: Dictionary) -> Vector2:
	var lo := 0
	var hi := 0
	for n: Variant in board.get("nodes", []) as Array:
		lo = mini(lo, int((n as Dictionary).get("lane", 0)))
		hi = maxi(hi, int((n as Dictionary).get("lane", 0)))
	var span := float(hi - lo) * LANE_W + NAME_GAP + NAME_W
	var left := maxf(MARGIN.x, (size.x - span) * 0.5)
	return Vector2(left + float(int(node.get("lane", 0)) - lo) * LANE_W, MARGIN.y + float(int(node.get("col", 0))) * ROW_H)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_place_children()


func _place_children() -> void:
	for node: Variant in board.get("nodes", []) as Array:
		var n := node as Dictionary
		var id := str(n.get("id", ""))
		var p := station_point(n)
		var lamp: Control = _lamps.get(id)
		if lamp != null:
			var ls := lamp.get_combined_minimum_size()
			lamp.size = ls
			lamp.position = (p - ls * 0.5).round()
		var label: Label = _names.get(id)
		if label != null:
			var h := label.get_combined_minimum_size().y
			label.size = Vector2(NAME_W, h)
			label.position = Vector2(p.x + NAME_GAP, p.y - h * 0.5).round()


static func _tone(state: String) -> String:
	match state:
		"complete": return "ok"
		"active", "choice": return "warn"
	return "off"


func _node(id: String) -> Dictionary:
	for node: Variant in board.get("nodes", []) as Array:
		if str((node as Dictionary).get("id", "")) == id:
			return node as Dictionary
	return {}


func _draw() -> void:
	# The plate, cropped from the middle of its render so its wear keeps its size.
	var src_size := size * TEXELS_PER_PIXEL
	var tex_size := BOARD.get_size()
	var src := Rect2((tex_size - src_size) * 0.5, src_size)
	draw_texture_rect_region(BOARD, Rect2(Vector2.ZERO, size), src.intersection(Rect2(Vector2.ZERO, tex_size)))
	# The track, under the lamps: each station back to each of its parents.
	for node: Variant in board.get("nodes", []) as Array:
		var n := node as Dictionary
		for parent: Variant in n.get("parents", []) as Array:
			var p := _node(str(parent))
			if not p.is_empty():
				_draw_track(station_point(p), station_point(n), _track_colour(str(p.get("state", "")), str(n.get("state", ""))))
	# The points levers, above the track at each junction a choice leaves from.
	var junctions := {}
	for node: Variant in board.get("nodes", []) as Array:
		var n := node as Dictionary
		var group := str(n.get("choice", ""))
		if group == "" or (n.get("parents", []) as Array).is_empty():
			continue
		var p := _node(str((n.parents as Array)[0]))
		if p.is_empty():
			continue
		var j: Dictionary = junctions.get(group, {"at": station_point(p) + Vector2(0.0, JUNCTION), "lane": int(p.get("lane", 0)), "dir": "mid"})
		if str(n.get("state", "")) != "closed" and str(n.get("state", "")) != "choice" and str(n.get("state", "")) != "locked":
			j.dir = "up" if int(n.get("lane", 0)) < int(j.lane) else "down"
		junctions[group] = j
	for group: Variant in junctions:
		var j: Dictionary = junctions[group]
		var tex: Texture2D = LEVER[str(j.dir)]
		var ts := tex.get_size() / TEXELS_PER_PIXEL
		draw_texture_rect(tex, Rect2((j.at as Vector2) + Vector2(-ts.x - 8.0, -ts.y * 0.5), ts), false)
	# The selected station: a warm glow round its lamp.
	var sel := _node(selected)
	if not sel.is_empty():
		draw_texture_rect(_glow(), Rect2(station_point(sel) - Vector2.ONE * SELECT_GLOW, Vector2.ONE * SELECT_GLOW * 2.0), false)


## The selected station's glow: its reach from the lamp's centre, and the light, brass at the lamp fading out.
const SELECT_GLOW := 34.0
static var _glow_tex: Texture2D


static func _glow() -> Texture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		g.colors = PackedColorArray([Color(DS.PALETTE.BRASS, 0.85), Color(DS.PALETTE.BRASS, 0.45), Color(DS.PALETTE.BRASS, 0.0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_glow_tex = t
	return _glow_tex


func _track_colour(parent_state: String, child_state: String) -> Color:
	if child_state == "closed":
		return CLOSED
	if child_state == "complete":
		return LIT
	if parent_state == "complete" and (child_state == "active" or child_state == "choice"):
		return SET
	return PAINTED


## Track from `a` down to `b`: straight down a lane, or down `a`'s lane to the junction, across on the
## diagonal and on down `b`'s.
func _draw_track(a: Vector2, b: Vector2, colour: Color) -> void:
	var pts := PackedVector2Array([a])
	if absf(a.x - b.x) > 0.5:
		var turn := a.y + JUNCTION
		var across := minf(absf(b.x - a.x) * 0.35, b.y - turn)
		pts.append(Vector2(a.x, turn))
		pts.append(Vector2(b.x, turn + across))
	pts.append(b)
	if colour == LIT or colour == SET:
		draw_polyline(pts, Color(colour, 0.18), 11.0, true)
	draw_polyline(pts, colour, 4.0 if colour != CLOSED else 3.0, true)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	for node: Variant in board.get("nodes", []) as Array:
		var n := node as Dictionary
		if station_point(n).distance_to(mb.position) <= HIT_RADIUS or _name_rect(n).has_point(mb.position):
			accept_event()
			selected = str(n.get("id", ""))
			queue_redraw()
			station_selected.emit(selected)
			return


func _name_rect(n: Dictionary) -> Rect2:
	var label: Label = _names.get(str(n.get("id", "")))
	return label.get_rect() if label != null else Rect2()
