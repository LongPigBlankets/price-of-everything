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

## Tile ids stop being readable below this zoom, and drawing ~600 of them wastes the frame.
const LABEL_MIN_ZOOM := 0.45
## Below this, per-tile borders turn into moire; the grid hides rather than lies.
const GRID_MIN_ZOOM := 0.16

const GRID_COLOR := Color(0.45, 0.85, 0.6, 0.30)
const GRID_WIDTH := 1.0
const LABEL_COLOR := Color(0.60, 0.95, 0.75, 0.55)
const LABEL_SIZE := 11

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
	if editor == null or not show_grid:
		return
	var camera: Camera2D = editor.call("camera")
	if camera == null:
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
