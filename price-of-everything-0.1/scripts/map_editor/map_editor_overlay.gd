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
const AuthoredFabricPainter := preload("res://scripts/authored_fabric_painter.gd")
const AuthoredSpecialShapesRef := preload("res://scripts/authored_special_shapes.gd")

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
const CORNER_COLOR := Color(0.55, 0.90, 1.0, 1.0)
const CORNER_RADIUS := 5.0

## Selected shapes are hatched rather than tinted: a tint changes the colour you are judging
## the composition by, and the whole point of the map's palette is that its greys and washes
## read against each other. Diagonal lines say "selected" without touching the fill.
const HATCH_COLOR := Color(0.99, 0.97, 0.90, 0.75)
const HATCH_SPACING := 7.0
const HATCH_WIDTH := 1.6
const TRACE_COLOR := Color(1.0, 0.55, 0.85, 0.95)
const MARQUEE_FILL := Color(0.45, 0.8, 1.0, 0.13)
const MARQUEE_EDGE := Color(0.55, 0.9, 1.0, 0.85)
## Selected strokes are overlined rather than recoloured, so their class is still readable
## while they are picked — you often select in order to change what they are.
const SELECTED_COLOR := Color(1.0, 0.45, 0.35, 0.95)

## THE WATER MASK. The relief paints a generous sand band that reaches well past where
## NavGrid stops calling the ground land — so a road drawn on what looks like solid beach can
## sit over "sea" as far as every audit is concerned. That is not hypothetical: it put a
## hand-drawn coast road 14.9 world units into water-classified cells, invisibly, because the
## stroke was unlockable and would only have appeared over the sea much later. This draws the
## boundary NavGrid actually uses, so the real coast is something you can see.
const WATER_MASK_COLOR := Color(0.30, 0.65, 1.0, 0.26)
const WATER_MASK_EDGE := Color(0.45, 0.80, 1.0, 0.75)
## Below this zoom a per-cell mask is a wash of blue over the whole sea and tells you
## nothing; the boundary is what matters and it needs the resolution.
const WATER_MASK_MIN_ZOOM := 0.30

## Slots by class, so which kind of building a piece of ground is reserved for is readable
## without clicking it. Outlined rather than filled: a slot is EMPTY ground, and a solid box
## would read as something already standing there.
## One colour per box class, and a word for each so the panel can say which is which without
## the reader having to match a swatch from memory. Ordered light-to-heavy with size.
const SLOT_COLORS := {
	"very_small": Color(1.00, 0.78, 0.25, 0.95),
	"small": Color(0.95, 0.32, 0.30, 0.95),
	"medium": Color(0.35, 0.62, 1.00, 0.95),
	"large": Color(0.72, 0.45, 1.00, 0.95),
}
const SLOT_SWATCH := {
	"very_small": "amber",
	"small": "red",
	"medium": "blue",
	"large": "violet",
}
const SLOT_FILL_ALPHA := 0.16
const SLOT_WIDTH := 2.0
const SLOT_PICKED_WIDTH := 4.0

## Set by `map_editor.gd` after construction (an editor tool, not a shipped node, so a
## plain assignment beats a signal here). Untyped to avoid a preload cycle with the editor
## script, which preloads this one.
var editor: Node = null

var show_grid := true
var show_labels := true
## Off by default — it is a check you turn on while drawing a coastline, not scenery.
var show_water_mask := false

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
	_draw_water_mask(camera)
	_draw_authored_fabric(camera)
	_draw_authored_roads(camera)
	_draw_pen(camera)
	_draw_trace(camera)
	_draw_dots(camera)
	_draw_slots(camera)
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


## Ground and fabric, drawn with the SAME painter the game uses, through a transform rather
## than a re-implementation — so the preview cannot drift from what will be rendered.
## Roads draw after, matching the game's layering.
func _draw_authored_fabric(camera: Camera2D) -> void:
	var document: Dictionary = editor.call("document").call("data")
	var settlements_value: Variant = document.get("settlements", {})
	if typeof(settlements_value) != TYPE_DICTIONARY:
		return
	# The painter works in world units; this Control draws in screen space. Rather than
	# teach the painter about cameras, the canvas is transformed for the duration.
	draw_set_transform(size * 0.5 - camera.get_screen_center_position() * camera.zoom.x,
		0.0, Vector2(camera.zoom.x, camera.zoom.x))
	var settlements: Dictionary = settlements_value
	var selected: Dictionary = editor.call("selected_ids")
	var keys := settlements.keys()
	keys.sort()
	for key in keys:
		var settlement_value: Variant = settlements[key]
		if typeof(settlement_value) != TYPE_DICTIONARY:
			continue
		var settlement: Dictionary = settlement_value
		for area in _entries(settlement, "farms"):
			AuthoredFabricPainter.draw_farm(self, area)
			if selected.has(str(area.get("id", ""))):
				_hatch([_polygon_of(area)], camera)
		for plaza in _entries(settlement, "plazas"):
			AuthoredFabricPainter.draw_plaza(self, plaza)
			if selected.has(str(plaza.get("id", ""))):
				_hatch([_polygon_of(plaza)], camera)
		for park in _entries(settlement, "parks"):
			AuthoredFabricPainter.draw_park(self, park)
			if selected.has(str(park.get("id", ""))):
				_hatch([_polygon_of(park)], camera)
		for mass in _entries(settlement, "decor"):
			AuthoredFabricPainter.draw_mass(self, mass)
			if selected.has(str(mass.get("id", ""))):
				_hatch(AuthoredFabricPainter.mass_polygons(mass), camera)
		for special in _entries(settlement, "specials"):
			AuthoredFabricPainter.draw_special(self, special)
			if selected.has(str(special.get("id", ""))):
				_hatch([AuthoredSpecialShapesRef.render_polygon(special)], camera)
		for area in _entries(settlement, "forests"):
			AuthoredFabricPainter.draw_forest(self, area)
	# The stamp being dragged, previewed as the real thing.
	var shape: RefCounted = editor.call("shape_tool")
	if shape != null and bool(shape.call("is_stamping")):
		var preview: Dictionary = shape.call("stamp_preview", "__preview__")
		if not preview.is_empty():
			AuthoredFabricPainter.draw_mass(self, preview)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_corner_handles(camera)

	# The outline being clicked out stays in screen space: it is scaffolding, not content.
	var pending: Array = editor.call("poly_points")
	if not pending.is_empty():
		var poly_screen := PackedVector2Array()
		for entry_value in pending:
			var entry: Array = entry_value as Array
			if entry != null and entry.size() >= 2:
				poly_screen.append(_to_screen(Vector2(float(entry[0]), float(entry[1])), camera))
		for point in poly_screen:
			draw_circle(point, POINT_RADIUS + 1.0, PEN_POINT_COLOR)
		if poly_screen.size() >= 2:
			var closed_poly := poly_screen.duplicate()
			closed_poly.append(poly_screen[0])
			draw_polyline(closed_poly, PEN_COLOR, 2.0, true)
	if shape != null and bool(shape.call("is_drawing")):
		var points: Array = shape.call("polygon_points")
		var screen := PackedVector2Array()
		for entry_value in points:
			var entry: Array = entry_value as Array
			if entry != null and entry.size() >= 2:
				screen.append(_to_screen(Vector2(float(entry[0]), float(entry[1])), camera))
		for point in screen:
			draw_circle(point, POINT_RADIUS + 1.0, PEN_POINT_COLOR)
		if screen.size() >= 2:
			var closed := screen.duplicate()
			closed.append(screen[0])
			draw_polyline(closed, PEN_COLOR, 2.0, true)


## Diagonal hatching clipped to a set of polygons. Drawn in WORLD space (the canvas is
## already transformed here) but stepped in world units so the density is stable as the
## shape moves; at very low zoom it thins out rather than turning into a solid block.
func _hatch(polygons: Array, camera: Camera2D) -> void:
	var spacing := HATCH_SPACING / maxf(camera.zoom.x, 0.05)
	for polygon_value in polygons:
		var polygon: PackedVector2Array = polygon_value
		if polygon.size() < 3:
			continue
		var bounds := Rect2(polygon[0], Vector2.ZERO)
		for point in polygon:
			bounds = bounds.expand(point)
		# 45° lines across the box, clipped to the shape by Godot's own clipper so the
		# hatching stops exactly at the outline rather than at its bounding box.
		var reach := bounds.size.x + bounds.size.y
		var steps := int(reach / spacing) + 1
		for i in steps:
			var offset := bounds.position + Vector2(float(i) * spacing - bounds.size.y, 0.0)
			var line := PackedVector2Array([offset, offset + Vector2(bounds.size.y, bounds.size.y)])
			for piece in Geometry2D.intersect_polyline_with_polygon(line, polygon):
				if (piece as PackedVector2Array).size() >= 2:
					draw_polyline(piece, HATCH_COLOR, HATCH_WIDTH / maxf(camera.zoom.x, 0.05), true)


func _polygon_of(record: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for entry in (record.get("outline", []) as Array):
		var values: Array = entry as Array
		if values != null and values.size() >= 2:
			out.append(Vector2(float(values[0]), float(values[1])))
	return out


func _entries(settlement: Dictionary, key: String) -> Array:
	var out: Array = []
	for value in (settlement.get(key, []) as Array):
		if typeof(value) == TYPE_DICTIONARY:
			out.append(value)
	return out


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


## NavGrid's water cells, as the editor's own overlay. Only the cells on the BOUNDARY are
## outlined; filling every wet cell to the horizon would drown the map in blue and hide the
## one line that matters.
func _draw_water_mask(camera: Camera2D) -> void:
	if not show_water_mask or camera.zoom.x < WATER_MASK_MIN_ZOOM:
		return
	var nav := NavGrid.instance()
	if nav == null or not nav.is_ready():
		return
	var view := _visible_world_rect(camera)
	var step: float = nav.step
	var first := nav.cell_of(view.position)
	var last := nav.cell_of(view.position + view.size)
	var size := Vector2(step, step) * camera.zoom.x
	for ix in range(first.x, last.x + 1):
		for iy in range(first.y, last.y + 1):
			if nav.water(ix, iy) == NavGrid.WATER_LAND:
				continue
			var centre: Vector2 = nav.world_of(ix, iy)
			var top_left := _to_screen(centre - Vector2(step, step) * 0.5, camera)
			draw_rect(Rect2(top_left, size), WATER_MASK_COLOR, true)
			# A cell with a dry neighbour is on the shoreline: stroke it so the boundary
			# reads as a line rather than as the edge of a wash.
			for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if nav.water(ix + offset.x, iy + offset.y) == NavGrid.WATER_LAND:
					draw_rect(Rect2(top_left, size), WATER_MASK_EDGE, false, 1.0)
					break


## Corner handles of the shape being edited. Screen-space and generous: a handle is a click
## target, and at working zooms a world-sized dot is a test of aim.
func _draw_corner_handles(camera: Camera2D) -> void:
	var corners: PackedVector2Array = editor.call("editable_corners")
	if corners.is_empty():
		return
	var held := int(editor.call("held_corner"))
	for i in corners.size():
		var centre := _to_screen(corners[i], camera)
		draw_circle(centre, CORNER_RADIUS + 1.5, DOT_EDGE)
		draw_circle(centre, CORNER_RADIUS, DOT_ARMED if i == held else CORNER_COLOR)


## Reserved ground for gameplay buildings. Drawn as an oriented outline with a faint fill and
## a facing tick, so the direction a building will front is visible before anything is built.
func _draw_slots(camera: Camera2D) -> void:
	var boxes: Array = editor.call("document_slot_boxes")
	if boxes.is_empty():
		return
	var picked: Dictionary = editor.call("picked_slot")
	for box_value in boxes:
		var box: Dictionary = box_value
		var colour: Color = SLOT_COLORS.get(str(box["class"]), SLOT_COLORS["small"])
		var centre: Vector2 = box["centre"]
		var size: Vector2 = box["size"]
		var angle := float(box["angle"])
		var corners := PackedVector2Array()
		for corner in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
			corners.append(_to_screen(centre + (corner * size).rotated(angle), camera))
		var fill := colour
		fill.a = SLOT_FILL_ALPHA
		draw_colored_polygon(corners, fill)
		var ring := corners.duplicate()
		ring.append(corners[0])
		var is_picked: bool = str(picked.get("tile_id", "")) == str(box["tile_id"]) \
			and int(picked.get("index", -1)) == int(box["index"])
		draw_polyline(ring, colour, SLOT_PICKED_WIDTH if is_picked else SLOT_WIDTH, true)
		# A tick on the fronting edge: a slot carries a facing, and a plain box hides it.
		var front := _to_screen(centre + Vector2(0.0, -size.y * 0.5).rotated(angle), camera)
		draw_line(_to_screen(centre, camera), front, colour, SLOT_WIDTH, true)


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
