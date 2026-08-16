extends Control
## The editor's own drawing layer: tile borders, ids, and (from P1) the authored content
## being edited. Nothing here is part of the game's look — it is the editor's scaffolding,
## drawn over the real map so the designer can see where tile boundaries fall.
##
## EDITOR-ONLY (see the header of `map_editor.gd`).
##
## Screen-space by design. The map's own layers draw in world space and are therefore
## zoom-scaled; scaffolding must stay legible at every zoom, so this Control projects world
## points through the canvas transform and strokes at constant SCREEN width. That is the
## opposite of the rule for authored ROADS, which are zoom-invariant world geometry — the
## distinction matters and is easy to get backwards.

## Borrowed from the game's own hover grid rather than copied: the hex vertex ring and the
## tile centre are the map's geometry, and a private copy here would drift the day tile size
## changes.
const HexGridOverlayRef := preload("res://scripts/hex_grid_overlay.gd")
const AuthoredRoadGeometry := preload("res://scripts/authored_road_geometry.gd")
const AuthoredRoadStyle := preload("res://scripts/authored_road_style.gd")

## Tile ids stop being readable below this zoom, and drawing ~600 of them wastes the frame.
const LABEL_MIN_ZOOM := 0.45
## Below this, per-tile borders turn into moire; the grid hides rather than lies.
const GRID_MIN_ZOOM := 0.16

const GRID_COLOR := Color(0.45, 0.85, 0.6, 0.30)
const GRID_WIDTH := 1.0
const LABEL_COLOR := Color(0.60, 0.95, 0.75, 0.55)
const LABEL_SIZE := 11

## The stroke being drawn, and the handles/points of finished ones. Editor scaffolding, so
## these are screen-constant and deliberately unlike anything in the map's own palette.
const PEN_COLOR := Color(1.0, 0.85, 0.25, 0.95)
const PEN_POINT_COLOR := Color(1.0, 0.95, 0.6, 1.0)
const HANDLE_COLOR := Color(0.55, 0.85, 1.0, 0.9)
const UNLOCKABLE_COLOR := Color(0.45, 0.8, 1.0, 0.85)
const POINT_RADIUS := 3.0

## Connect-the-dots markers. The owner asked for BIG WHITE DOTS, and big is the point: they
## are click targets before they are anything else, and a 3px dot at a working zoom is a
## test of aim rather than of judgement.
const DOT_RADIUS := 7.0
const DOT_COLOR := Color(1.0, 1.0, 1.0, 0.95)
const DOT_EDGE := Color(0.10, 0.12, 0.16, 0.9)
## The dot waiting for its partner, so a half-made link is never invisible.
const DOT_ARMED := Color(1.0, 0.72, 0.20, 1.0)
const TRACE_COLOR := Color(1.0, 0.55, 0.85, 0.95)
const MARQUEE_FILL := Color(0.45, 0.8, 1.0, 0.13)
const MARQUEE_EDGE := Color(0.55, 0.9, 1.0, 0.85)
## Selected strokes are overlined rather than recoloured, so their class is still readable
## while they are picked — you often select in order to change what they are.
const SELECTED_COLOR := Color(1.0, 0.45, 0.35, 0.95)

## Set by `map_editor.gd` after construction (an editor tool, not a shipped node, so a
## plain assignment beats a signal here). Untyped to avoid a preload cycle with the editor
## script, which preloads this one.
var editor: Node = null

var show_grid := true
var show_labels := true

var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	set_process(true)


func _process(_delta: float) -> void:
	# The overlay follows the camera, so it must repaint whenever the view moves. The world
	# layers redraw on their own signals; this one has no source of truth but the transform.
	queue_redraw()


func _draw() -> void:
	if editor == null:
		return
	var camera: Camera2D = editor.call("camera")
	if camera == null:
		return
	_draw_grid(camera)
	_draw_authored_roads(camera)
	_draw_pen(camera)
	_draw_trace(camera)
	_draw_dots(camera)
	_draw_marquee(camera)


## Authored roads, at their true world widths so what the designer sees is what the game
## will draw. Unlockable strokes carry a dashed blue overline — they are the ones whose
## visibility depends on play, and a designer needs to see at a glance which parts of a
## settlement will be missing at turn one.
func _draw_authored_roads(camera: Camera2D) -> void:
	var document: Dictionary = editor.call("document").call("data")
	var settlements_value: Variant = document.get("settlements", {})
	if typeof(settlements_value) != TYPE_DICTIONARY:
		return
	var settlements: Dictionary = settlements_value
	var selected: Dictionary = editor.call("selected_ids")
	for key in settlements.keys():
		var settlement_value: Variant = settlements[key]
		if typeof(settlement_value) != TYPE_DICTIONARY:
			continue
		for stroke_value in ((settlement_value as Dictionary).get("roads", []) as Array):
			if typeof(stroke_value) != TYPE_DICTIONARY:
				continue
			var stroke: Dictionary = stroke_value
			var world_points := AuthoredRoadGeometry.polyline(stroke)
			if world_points.size() < 2:
				continue
			var stroke_class := str(stroke.get("class", "mid"))
			var screen := _project(world_points, camera)
			# World width scaled by zoom: the stroke is zoom-invariant world geometry, so
			# its on-screen thickness must track the camera exactly as the game's will.
			draw_polyline(screen, AuthoredRoadStyle.casing_color(stroke_class),
				AuthoredRoadStyle.casing_width(stroke_class) * camera.zoom.x, true)
			draw_polyline(screen, AuthoredRoadStyle.bed_color(stroke_class),
				AuthoredRoadStyle.bed_width(stroke_class) * camera.zoom.x, true)
			if bool(stroke.get("unlockable", false)):
				draw_polyline(screen, UNLOCKABLE_COLOR, 1.6, true)
			if selected.has(str(stroke.get("id", ""))):
				draw_polyline(screen, SELECTED_COLOR, 3.0, true)


## The stroke in progress: the line so far, its points, and the handles of any curve point.
func _draw_pen(camera: Camera2D) -> void:
	if str(editor.call("current_tool")) != "road":
		return
	var tool_ref: RefCounted = editor.call("road_tool")
	if tool_ref == null or not bool(tool_ref.call("is_drawing")):
		return
	var points: Array = tool_ref.call("preview_points")
	var stroke := {"id": "__preview__", "class": str(tool_ref.call("stroke_class")), "points": points}
	var world_points := AuthoredRoadGeometry.sample(stroke)
	if world_points.size() >= 2:
		draw_polyline(_project(world_points, camera), PEN_COLOR, 2.0, true)
	for entry_value in points:
		var entry: Array = entry_value as Array
		if entry == null or entry.size() < 2:
			continue
		var anchor := Vector2(float(entry[0]), float(entry[1]))
		var screen_anchor := _to_screen(anchor, camera)
		draw_circle(screen_anchor, POINT_RADIUS, PEN_POINT_COLOR)
		if entry.size() >= 6:
			for handle in [Vector2(float(entry[2]), float(entry[3])),
					Vector2(float(entry[4]), float(entry[5]))]:
				var screen_handle := _to_screen(anchor + handle, camera)
				draw_line(screen_anchor, screen_handle, HANDLE_COLOR, 1.0, true)
				draw_circle(screen_handle, POINT_RADIUS * 0.7, HANDLE_COLOR)


## The freehand path as it is being traced. Drawn raw — the simplification happens on
## release, and showing the simplified version live would make the line jump under the hand.
func _draw_trace(camera: Camera2D) -> void:
	var tool_ref: RefCounted = editor.call("trace_tool")
	if tool_ref == null or not bool(tool_ref.call("is_tracing")):
		return
	var points: PackedVector2Array = tool_ref.call("trace_points")
	if points.size() >= 2:
		draw_polyline(_project(points, camera), TRACE_COLOR, 2.0, true)


## Free-standing dots and the armed one. Shown for every tool, not just the dot tool: a dot
## laid down earlier is a junction the designer intends to use, and hiding it while the pen
## is out would make it useless as an anchor.
func _draw_dots(camera: Camera2D) -> void:
	var tool_ref: RefCounted = editor.call("trace_tool")
	if tool_ref == null:
		return
	var dots: PackedVector2Array = tool_ref.call("dots")
	var armed := int(tool_ref.call("pending_dot"))
	for i in dots.size():
		var centre := _to_screen(dots[i], camera)
		draw_circle(centre, DOT_RADIUS + 1.5, DOT_EDGE)
		draw_circle(centre, DOT_RADIUS, DOT_ARMED if i == armed else DOT_COLOR)


## The selection box while it is being dragged.
func _draw_marquee(camera: Camera2D) -> void:
	var rect: Rect2 = editor.call("marquee_rect")
	if rect.size == Vector2.ZERO:
		return
	var screen := Rect2(_to_screen(rect.position, camera), rect.size * camera.zoom.x)
	draw_rect(screen, MARQUEE_FILL, true)
	draw_rect(screen, MARQUEE_EDGE, false, 1.5)


func _project(points: PackedVector2Array, camera: Camera2D) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in points:
		out.append(_to_screen(point, camera))
	return out


func _draw_grid(camera: Camera2D) -> void:
	if not show_grid:
		return
	var zoom := camera.zoom.x
	if zoom < GRID_MIN_ZOOM:
		return
	var terrain := _terrain_layer()
	if terrain == null:
		return
	var view := _visible_world_rect(camera)
	var label_zoom := zoom >= LABEL_MIN_ZOOM and show_labels
	var centre_offset := HexGridOverlayRef.TILE_CENTER
	for coord_value in terrain.tiles.keys():
		var coord: Vector2i = coord_value
		var centre: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
		# Cull by the tile box (540x480) before doing any per-vertex work.
		if not view.intersects(Rect2(centre - centre_offset, centre_offset * 2.0)):
			continue
		_draw_hex(centre, camera)
		if label_zoom:
			var tile: Dictionary = terrain.tiles[coord_value]
			draw_string(_font, _to_screen(centre, camera) + Vector2(-22.0, 4.0),
				str(tile.get("id", "")), HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE, LABEL_COLOR)


## Flat-top hex in the map's own vertex order, projected to screen. Uses HexMap's tile
## geometry rather than a local copy so a change to tile size cannot desynchronise the
## editor's grid from the real tiles.
func _draw_hex(centre: Vector2, camera: Camera2D) -> void:
	var points := PackedVector2Array()
	for vertex in HexGridOverlayRef.HEX_VERTS:
		# HEX_VERTS are tile-local with the origin at the cell's top-left corner, so the
		# tile centre must be subtracted to re-centre them on the tile.
		points.append(_to_screen(centre + (vertex - HexGridOverlayRef.TILE_CENTER), camera))
	points.append(points[0])
	draw_polyline(points, GRID_COLOR, GRID_WIDTH)


func _to_screen(world: Vector2, camera: Camera2D) -> Vector2:
	return (world - camera.get_screen_center_position()) * camera.zoom + size * 0.5


func _visible_world_rect(camera: Camera2D) -> Rect2:
	var half := size * 0.5 / camera.zoom.x
	var centre := camera.get_screen_center_position()
	return Rect2(centre - half, half * 2.0)


## The terrain layer joins the `hex_map` group in its own `_ready`, so the editor finds it
## by group rather than by a scene path that a rename would silently break.
func _terrain_layer() -> Node:
	return get_tree().get_first_node_in_group("hex_map")
