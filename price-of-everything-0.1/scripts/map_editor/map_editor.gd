extends Node
## The map editor shell — P0 of `docs/map-editor-plan.md`.
##
## EDITOR-ONLY. This directory is excluded from exported builds (`export_presets.cfg`),
## so NO SHIPPED SCRIPT MAY REFERENCE IT: a `preload` from shipped code resolves at parse
## time and would break the exported game. `main_menu.gd` reaches the editor by probing
## `ResourceLoader.exists()` and loading the scene by path string, never by symbol; the
## unit suite pins that (`_test_shipped_code_avoids_editor_only_paths`).
##
## It boots the real game world and draws on top of it, rather than reimplementing a map:
## the editor previews with the same renderers the bake and the game use, so preview,
## export and play cannot drift. (The browser Packing Lab taught the opposite lesson —
## constants ported by hand go stale.)
##
## P0 SCOPE: boot, camera, overlay toggles, document load/save, the undo stack, and the
## status readout. It authors nothing yet — the pen, stamp and slot tools are P1-P3. The
## gate for this phase is that it opens, draws no authored content, and leaves the game
## and the suite untouched.

const AuthoredMap := preload("res://scripts/authored_map.gd")
const AuthoredRoadGeometry := preload("res://scripts/authored_road_geometry.gd")
const MapEditorDocument := preload("res://scripts/map_editor/map_editor_document.gd")
const MapEditorOverlay := preload("res://scripts/map_editor/map_editor_overlay.gd")
const MapEditorRoadTool := preload("res://scripts/map_editor/map_editor_road_tool.gd")

## Which settlement new content joins. P1 authors into one at a time; the settlement picker
## arrives with the tools that need to move content between them.
const DEFAULT_SETTLEMENT := "untitled"

## Frames to let the world settle before framing the camera. The shot tools use 150 and
## the world build is ~20-30 s of coroutine work on this branch; the readout reports when
## the world is actually ready rather than leaving a blank screen.
const SETTLE_FRAMES := 150

## Editing zooms. Well inside the camera controller's own clamp, and chosen so one tile
## (540x480 u) fills a comfortable working area.
const START_ZOOM := 0.9
const ZOOM_MIN := 0.12
const ZOOM_MAX := 2.5
const ZOOM_STEP := 1.12

# Typed through the const preloads above: an untyped `RefCounted` here makes every call
# return Variant, and `:=` inference then fails at parse time.
var _document: MapEditorDocument
var _overlay: MapEditorOverlay
var _road_tool: MapEditorRoadTool
var _world: Node
var _camera: Camera2D
var _status: Label
var _ready_to_edit := false
var _panning := false
var _settlement := DEFAULT_SETTLEMENT


func _ready() -> void:
	_document = MapEditorDocument.new()
	_road_tool = MapEditorRoadTool.new()
	_build_chrome()
	_boot_world()


# ── Boot ────────────────────────────────────────────────────────────────────────

## Instantiate the real game scene as a child, then take its camera. This is the shot
## tools' recipe (`tools/tile_shot.gd`) with one deliberate difference: input stays
## ENABLED. Those tools call `set_disable_input(true)` because they only capture; an
## editor must receive the mouse.
func _boot_world() -> void:
	_set_status("Building the world…")
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_set_status("Could not load the map scene.")
		return
	_world = packed.instantiate()
	add_child(_world)
	# Draw order: the overlay must sit above every world layer. The world map uses sibling
	# order for layering and reserves z up to 90 (the parchment multiply), so the overlay
	# rides its own CanvasLayer instead of competing for a z_index.
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	_hide_game_ui()
	_take_camera()
	_ready_to_edit = true
	_refresh_status()


## Hide the HUD and the hover grid, leaving the map itself. `main.tscn`'s ROOT node is
## `WorldMap`, so these are direct children of the instantiated scene — not "WorldMap/…"
## paths. Looked up with `get_node_or_null` so a scene rename degrades to "chrome still
## visible" rather than a crash mid-session.
func _hide_game_ui() -> void:
	for node_name in ["UILayer", "HexGridOverlay"]:
		var node := _world.get_node_or_null(NodePath(node_name))
		if node != null and node is CanvasItem:
			(node as CanvasItem).visible = false
		elif node != null and node is CanvasLayer:
			(node as CanvasLayer).visible = false


## Take over the game camera. Its `_process` lerps toward `_target_zoom` and re-clamps to
## the map bounds every frame, so an editor that only writes `position`/`zoom` gets
## dragged back — the shot tools hit this too. Disabling its processing is the fix.
func _take_camera() -> void:
	_camera = get_viewport().get_camera_2d()
	if _camera == null:
		return
	_camera.set_process(false)
	_camera.set_physics_process(false)
	if "edge_pan_enabled" in _camera:
		_camera.set("edge_pan_enabled", false)
	_camera.zoom = Vector2(START_ZOOM, START_ZOOM)
	if "_target_zoom" in _camera:
		_camera.set("_target_zoom", _camera.zoom)


# ── Chrome ──────────────────────────────────────────────────────────────────────

func _build_chrome() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 64   # above the world, below the debug terminal (128)
	add_child(layer)

	_overlay = MapEditorOverlay.new()
	_overlay.editor = self
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_overlay)

	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.06, 0.85)
	bar.add_theme_stylebox_override("panel", style)
	layer.add_child(bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	bar.add_child(margin)

	_status = Label.new()
	_status.add_theme_color_override("font_color", Color(0.75, 0.95, 0.8))
	margin.add_child(_status)
	_set_status("Starting…")


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = "MAP EDITOR   %s" % text


func _refresh_status() -> void:
	var counts := _document.counts()
	_set_status("%s   |   %d settlements, %d roads, %d masses   |   pen: %s (1/2/3)   |   %s   |   %s"
		% [_document.display_name(), counts.settlements, counts.roads, counts.masses,
			_road_tool.stroke_class().to_upper(),
			"unsaved" if _document.is_dirty() else "saved",
			"drag=curve · Enter end · Bksp back · F5 save · Esc menu"])


# ── Input ───────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not _ready_to_edit:
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and _panning:
		var motion := event as InputEventMouseMotion
		if _camera != null:
			# Drag the world under the cursor: screen delta / zoom is the world delta.
			_camera.position -= motion.relative / _camera.zoom.x
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event as InputEventKey)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.double_click and _road_tool.is_drawing():
				_finish_stroke()
			elif event.pressed:
				# Alt places a raw point, bypassing the junction snap.
				_road_tool.press(_world_at(event.position),
					MapEditorRoadTool.snap_targets(_document.data()), not event.alt_pressed)
				_overlay.queue_redraw()
			else:
				_road_tool.release(_world_at(event.position))
				_overlay.queue_redraw()
		MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
			_panning = event.pressed
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_zoom_by(ZOOM_STEP)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_zoom_by(1.0 / ZOOM_STEP)


func _handle_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_F5:
			_save()
		KEY_F6:
			_reload()
		KEY_1:
			_road_tool.set_stroke_class("major")
			_refresh_status()
		KEY_2:
			_road_tool.set_stroke_class("mid")
			_refresh_status()
		KEY_3:
			_road_tool.set_stroke_class("minor")
			_refresh_status()
		KEY_ENTER, KEY_KP_ENTER:
			_finish_stroke()
		KEY_BACKSPACE:
			_road_tool.undo_point()
			_overlay.queue_redraw()
		KEY_ESCAPE:
			# Escape abandons an in-progress stroke first; only an idle Escape leaves.
			if _road_tool.is_drawing():
				_road_tool.abandon()
				_overlay.queue_redraw()
				_refresh_status()
				return
			_leave()
		KEY_Z:
			if event.ctrl_pressed or event.meta_pressed:
				var outcome := _document.redo() if event.shift_pressed else _document.undo()
				_set_status(outcome)
				await get_tree().process_frame
				_refresh_status()


func _zoom_by(factor: float) -> void:
	if _camera == null:
		return
	var z := clampf(_camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	_camera.zoom = Vector2(z, z)
	if "_target_zoom" in _camera:
		_camera.set("_target_zoom", _camera.zoom)


# ── Authoring ───────────────────────────────────────────────────────────────────

## World position under a screen point. The inverse of the overlay's projection, and the
## reason the editor drives the camera directly rather than letting the controller lerp:
## a moving camera would put the click somewhere the designer did not aim.
func _world_at(screen: Vector2) -> Vector2:
	if _camera == null:
		return screen
	var viewport_size := get_viewport().get_visible_rect().size
	return _camera.get_screen_center_position() + (screen - viewport_size * 0.5) / _camera.zoom.x


## Commit the stroke being drawn into the document, under the current settlement.
func _finish_stroke() -> void:
	if not _road_tool.is_drawing():
		return
	var terrain := get_tree().get_first_node_in_group("hex_map")
	var settlement := _ensure_settlement()
	var next_id := int(settlement.get("next_id", 1))
	var stroke := _road_tool.finish(_settlement, next_id, terrain)
	if stroke.is_empty():
		_set_status("Stroke discarded — too short to keep.")
		_overlay.queue_redraw()
		return
	# begin_edit snapshots first, so this is undoable like every other mutation.
	_document.begin_edit("draw road")
	settlement = _ensure_settlement()
	settlement["next_id"] = next_id + 1
	var roads: Array = settlement.get("roads", []) as Array
	roads.append(stroke)
	settlement["roads"] = roads
	# The settlement's tile list is the suppression key: a tile only stands its procedural
	# systems down once something authored actually sits on it.
	var tiles: Array = settlement.get("tiles", []) as Array
	for tile_id in (stroke.get("tiles", []) as Array):
		if not tiles.has(tile_id):
			tiles.append(tile_id)
	tiles.sort()
	settlement["tiles"] = tiles
	_overlay.queue_redraw()
	_report_stroke(stroke)


func _report_stroke(stroke: Dictionary) -> void:
	var wet := _wet_length(stroke)
	var note := "%s road, %d tiles%s" % [
		str(stroke.get("class", "")),
		(stroke.get("tiles", []) as Array).size(),
		", UNLOCKABLE" if bool(stroke.get("unlockable", false)) else "",
	]
	if not (stroke.get("bridges", []) as Array).is_empty():
		note += ", %d bridge(s)" % (stroke.get("bridges", []) as Array).size()
	if wet > 0.0:
		# The lint that matters most: a road drawn over sea or lake. Reported rather than
		# refused — the designer may be mid-stroke on a causeway — but never silent.
		note += "   ⚠ %d sample(s) OVER WATER" % int(wet)
	_set_status(note)


func _wet_length(stroke: Dictionary) -> float:
	var centreline := AuthoredRoadGeometry.sample(stroke)
	return float(AuthoredRoadGeometry.wet_samples(centreline, NavGrid.instance()).size())


## The settlement new content joins, created on first use.
func _ensure_settlement() -> Dictionary:
	var doc := _document.data()
	var settlements_value: Variant = doc.get("settlements", {})
	var settlements: Dictionary = settlements_value if typeof(settlements_value) == TYPE_DICTIONARY else {}
	if not settlements.has(_settlement):
		settlements[_settlement] = {"tiles": [], "next_id": 1, "roads": []}
	doc["settlements"] = settlements
	return settlements[_settlement]


func road_tool() -> MapEditorRoadTool:
	return _road_tool


# ── Document ────────────────────────────────────────────────────────────────────

func _save() -> void:
	var absolute := ProjectSettings.globalize_path(AuthoredMap.DOC_PATH)
	var problem := _document.save_to(absolute)
	if problem == "":
		# Drop the game-side cache so a reload in this session sees what was just written.
		AuthoredMap.reset_for_tests()
		_set_status("Saved %s" % absolute)
	else:
		_set_status("SAVE FAILED — %s" % problem)
	await get_tree().process_frame
	_refresh_status()


func _reload() -> void:
	AuthoredMap.reset_for_tests()
	_document.reload()
	_refresh_status()


func _leave() -> void:
	if _document.is_dirty() and not _document.discard_armed():
		# One press arms, the second leaves: an editor that discards an hour's work on a
		# stray Escape is worse than one that asks twice.
		_document.arm_discard()
		_set_status("UNSAVED CHANGES — press Esc again to discard, or F5 to save.")
		return
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


## True once the world has settled and the camera is under editor control. Capture
## harnesses poll this instead of guessing a frame count.
func is_ready_to_edit() -> bool:
	return _ready_to_edit


## Frame the view on a tile, for capture harnesses and (later) the editor's own
## go-to-tile command. Returns false when the tile id is unknown.
func focus_tile(tile_id: String, zoom: float = START_ZOOM) -> bool:
	if _camera == null:
		return false
	var terrain := get_tree().get_first_node_in_group("hex_map")
	if terrain == null:
		return false
	var coord: Vector2i = terrain.call("id_to_coord", tile_id)
	if not (terrain.get("tiles") as Dictionary).has(coord):
		return false
	_camera.position = terrain.call("map_to_local", terrain.call("map_coord_for_tile_coord", coord))
	var z := clampf(zoom, ZOOM_MIN, ZOOM_MAX)
	_camera.zoom = Vector2(z, z)
	if "_target_zoom" in _camera:
		_camera.set("_target_zoom", _camera.zoom)
	return true


func document() -> MapEditorDocument:
	return _document


func camera() -> Camera2D:
	return _camera
