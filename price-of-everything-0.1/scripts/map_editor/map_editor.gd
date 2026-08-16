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
const MapEditorLayers := preload("res://scripts/map_editor/map_editor_layers.gd")
const MapEditorStrokeEdit := preload("res://scripts/map_editor/map_editor_stroke_edit.gd")
const MapEditorTraceTool := preload("res://scripts/map_editor/map_editor_trace_tool.gd")
const MapEditorSelection := preload("res://scripts/map_editor/map_editor_selection.gd")
const MapEditorConfirm := preload("res://scripts/map_editor/map_editor_confirm.gd")
const MapEditorNameDialog := preload("res://scripts/map_editor/map_editor_name_dialog.gd")
const MapEditorPanel := preload("res://scripts/map_editor/map_editor_panel.gd")

## Tools. NAVIGATE is the default and does nothing but move the view: an editor whose idle
## state authors geometry cannot be explored, and every stray click becomes a road.
const TOOL_PAN := "pan"
const TOOL_ROAD := "road"
## Click an existing road to insert a point, then drag it to bow BOTH adjacent segments.
const TOOL_ANCHOR := "anchor"
## Press and drag to trace a line; the path is simplified into an editable stroke.
const TOOL_TRACE := "trace"
## Click to drop dots, then click two of them to join with a straight run.
const TOOL_DOTS := "dots"
## Click a road to step it up a class; Shift-click steps it back down.
const TOOL_UPGRADE := "upgrade"
## Drag a box over content, then delete it behind a confirmation.
const TOOL_SELECT := "select"

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

## WASD pan speed in SCREEN pixels per second. Divided by zoom before it moves the camera,
## so the map slides past at the same apparent rate whether you are looking at one tile or
## the whole coast — a world-unit speed would crawl when zoomed in and bolt when zoomed out.
const PAN_SPEED := 900.0
## Held Shift multiplier, for crossing the map rather than nudging along a street.
const PAN_FAST := 3.0
## Physical scancodes, so the keys stay under the same fingers on a non-QWERTY layout —
## WASD is a position on the keyboard, not four letters.
const PAN_KEYS := {
	KEY_W: Vector2(0.0, -1.0),
	KEY_S: Vector2(0.0, 1.0),
	KEY_A: Vector2(-1.0, 0.0),
	KEY_D: Vector2(1.0, 0.0),
}

# Typed through the const preloads above: an untyped `RefCounted` here makes every call
# return Variant, and `:=` inference then fails at parse time.
var _document: MapEditorDocument
var _overlay: MapEditorOverlay
var _road_tool: MapEditorRoadTool
var _trace_tool: MapEditorTraceTool
var _layers: MapEditorLayers
## While the anchor tool has a point picked up: `{settlement, stroke, index}`.
var _anchor_grab: Dictionary = {}
var _confirm: MapEditorConfirm
var _name_dialog: MapEditorNameDialog
## Marquee in world units while dragging, and the records it caught.
var _marquee_from := Vector2.INF
var _marquee_to := Vector2.INF
var _selection: Array = []
var _panel: MapEditorPanel
var _tool := TOOL_PAN
var _world: Node
var _camera: Camera2D
var _status: Label
var _ready_to_edit := false
var _panning := false
var _settlement := DEFAULT_SETTLEMENT


func _ready() -> void:
	_document = MapEditorDocument.new()
	_road_tool = MapEditorRoadTool.new()
	_trace_tool = MapEditorTraceTool.new()
	_layers = MapEditorLayers.new()
	_build_chrome()
	_boot_world()


## Continuous panning has to be polled rather than driven by key events: an editor that
## moved one step per repeat would inherit the OS's repeat delay and rate, which is a typing
## setting, not a camera one.
func _process(delta: float) -> void:
	if not _ready_to_edit or _camera == null:
		return
	var direction := Vector2.ZERO
	for key in PAN_KEYS:
		if Input.is_physical_key_pressed(key):
			direction += PAN_KEYS[key] as Vector2
	if direction == Vector2.ZERO:
		return
	var speed := PAN_SPEED * (PAN_FAST if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	_camera.position += direction.normalized() * speed * delta / _camera.zoom.x


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
	_silence_world_input(_world)
	_take_camera()
	_layers.bind(_world)
	_panel.build(self, _layers)
	_ready_to_edit = true
	_refresh_status()


## Stop the GAME from consuming input while the editor is up.
##
## `camera_controller`, `hex_map` and `world_map` all run `_input`/`_unhandled_input`, and
## the world is a CHILD of this node, so they see every event first. That is why Escape
## never reached the editor and why dragging fought the pen: the game was still panning,
## picking tiles and claiming keys underneath. Disabling their processing is far more
## honest than trying to out-order them, and it leaves this node the single owner of input.
func _silence_world_input(node: Node) -> void:
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	node.set_process_shortcut_input(false)
	for child in node.get_children():
		_silence_world_input(child)


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

	_confirm = MapEditorConfirm.new()
	_confirm.set_anchors_preset(Control.PRESET_CENTER)
	_confirm.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_confirm.grow_vertical = Control.GROW_DIRECTION_BOTH
	_confirm.confirmed.connect(_delete_selection)
	_confirm.cancelled.connect(func() -> void: _set_status("Deletion cancelled."))
	layer.add_child(_confirm)

	_name_dialog = MapEditorNameDialog.new()
	_name_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_name_dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_name_dialog.grow_vertical = Control.GROW_DIRECTION_BOTH
	_name_dialog.accepted.connect(_save_as)
	_name_dialog.cancelled.connect(func() -> void: _set_status("Save cancelled."))
	layer.add_child(_name_dialog)

	_panel = MapEditorPanel.new()
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 8.0
	_panel.offset_top = 44.0
	_panel.offset_bottom = -8.0
	layer.add_child(_panel)

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
	if _panel != null:
		_panel.set_status(text)


func _refresh_status() -> void:
	var counts := _document.counts()
	_set_status("%s   |   %d settlements · %d roads · %d masses   |   %s"
		% [_document.display_name(), counts.settlements, counts.roads, counts.masses,
			"UNSAVED" if _document.is_dirty() else "saved"])
	if _panel != null:
		_panel.refresh()


# ── Input ───────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not _ready_to_edit:
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _panning and _camera != null:
			# Drag the world under the cursor: screen delta / zoom is the world delta.
			_camera.position -= motion.relative / _camera.zoom.x
		elif _tool == TOOL_TRACE and _trace_tool.is_tracing():
			_trace_tool.extend_trace(_world_at(motion.position))
			_overlay.queue_redraw()
		elif _tool == TOOL_SELECT and _marquee_from != Vector2.INF:
			_marquee_to = _world_at(motion.position)
			_overlay.queue_redraw()
		elif _tool == TOOL_ANCHOR and not _anchor_grab.is_empty():
			# Live reshaping: the curve follows the pointer, so the bend is judged against
			# the map rather than guessed and corrected.
			MapEditorStrokeEdit.shape_anchor(_anchor_grab["stroke"] as Dictionary,
				int(_anchor_grab["index"]), _world_at(motion.position))
			_overlay.queue_redraw()
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event as InputEventKey)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			var world := _world_at(event.position)
			match _tool:
				# In NAVIGATE the left button drags the view. Only the drawing tools author,
				# so an idle click can never leave geometry behind.
				TOOL_PAN:
					_panning = event.pressed
				TOOL_ROAD:
					if event.double_click and _road_tool.is_drawing():
						_finish_stroke()
					elif event.pressed:
						# Alt places a raw point, bypassing the junction snap.
						_road_tool.press(world,
							MapEditorRoadTool.snap_targets(_document.data()), not event.alt_pressed)
					else:
						_road_tool.release(world)
				TOOL_ANCHOR:
					if event.pressed:
						_anchor_press(world)
					else:
						_anchor_grab = {}
				TOOL_TRACE:
					if event.pressed:
						_trace_tool.begin_trace(world)
					else:
						_finish_trace()
				TOOL_DOTS:
					if event.pressed:
						_dot_press(world)
				TOOL_UPGRADE:
					if event.pressed:
						_upgrade_press(world, not event.shift_pressed)
				TOOL_SELECT:
					if event.pressed:
						_marquee_from = world
						_marquee_to = world
					else:
						_finish_marquee(world)
			_overlay.queue_redraw()
		MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
			# Always available, whatever the tool: panning mid-stroke is normal when a road
			# runs off the edge of the view.
			_panning = event.pressed
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_zoom_by(ZOOM_STEP, event.position)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_zoom_by(1.0 / ZOOM_STEP, event.position)


func _handle_key(event: InputEventKey) -> void:
	# The confirmation is modal — while it is up, Enter and Escape belong to it and nothing
	# else may act. Anything less makes Escape ambiguous at exactly the wrong moment.
	if _name_dialog != null and _name_dialog.is_open():
		# The field owns typing while it is open; only Escape is taken from it here, and
		# Enter is handled by the field's own submit.
		if event.keycode == KEY_ESCAPE:
			_name_dialog.close()
			_set_status("Save cancelled.")
			_refresh_status()
		return
	if _confirm != null and _confirm.is_open():
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_confirm.close()
			_delete_selection()
		elif event.keycode == KEY_ESCAPE:
			_confirm.close()
			_set_status("Deletion cancelled.")
		_refresh_status()
		return
	match event.keycode:
		KEY_F5:
			_save()
		KEY_F6:
			_reload()
		KEY_V:
			set_tool(TOOL_PAN)
		KEY_R:
			set_tool(TOOL_ROAD)
		KEY_T:
			set_tool(TOOL_ANCHOR)
		KEY_F:
			set_tool(TOOL_TRACE)
		KEY_C:
			set_tool(TOOL_DOTS)
		KEY_U:
			set_tool(TOOL_UPGRADE)
		KEY_X:
			set_tool(TOOL_SELECT)
		KEY_DELETE:
			_ask_delete()
		KEY_G:
			toggle_grid()
		KEY_E:
			_zoom_by(ZOOM_STEP)
		KEY_Q:
			_zoom_by(1.0 / ZOOM_STEP)
		KEY_1:
			set_road_class("major")
		KEY_2:
			set_road_class("mid")
		KEY_3:
			set_road_class("minor")
		KEY_ENTER, KEY_KP_ENTER:
			_finish_stroke()
		KEY_BACKSPACE:
			if _tool == TOOL_DOTS:
				_trace_tool.undo_dot()
			else:
				_road_tool.undo_point()
			_overlay.queue_redraw()
		KEY_ESCAPE:
			# Escape abandons work in progress first; only an idle Escape leaves. Dots count
			# as work in progress: clearing them is what "cancel" means for that tool.
			if not _selection.is_empty():
				_selection = []
				_overlay.queue_redraw()
				_set_status("Selection cleared.")
				_refresh_status()
				return
			if _road_tool.is_drawing() or _trace_tool.is_tracing() \
					or not _trace_tool.dots().is_empty():
				_road_tool.abandon()
				_trace_tool.cancel_trace()
				_trace_tool.clear_dots()
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


## Zoom about the CURSOR, not the screen centre: in an editor you zoom in on the junction
## you are about to draw, and a centre-anchored zoom slides it out of view exactly when you
## are trying to get closer to it. The world point under the pointer is pinned by moving the
## camera to compensate — the same thing the game's own controller does for the player.
## `anchor` is a screen position; the keyboard path passes the viewport centre, which makes
## it behave like a plain zoom.
func _zoom_by(factor: float, anchor: Vector2 = Vector2.INF) -> void:
	if _camera == null:
		return
	var screen_anchor := anchor
	if screen_anchor == Vector2.INF:
		screen_anchor = get_viewport().get_visible_rect().size * 0.5
	var before := _world_at(screen_anchor)
	var z := clampf(_camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	_camera.zoom = Vector2(z, z)
	if "_target_zoom" in _camera:
		_camera.set("_target_zoom", _camera.zoom)
	_camera.position += before - _world_at(screen_anchor)


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


## ADD ANCHOR. A press either picks up an existing point of the stroke under the cursor, or
## inserts a new one there. Inserting alone never changes the road's shape — the new point is
## a plain corner sitting exactly on the line it was inserted into — so the curve is entirely
## the product of the drag that follows, which is what makes the gesture predictable.
func _anchor_press(world: Vector2) -> void:
	var found := MapEditorStrokeEdit.stroke_at(_document.data(), world)
	if found.is_empty():
		_set_status("No road under the cursor.")
		return
	var stroke: Dictionary = found["stroke"]
	# One snapshot for the whole grab: the drag that follows mutates in place, so undo steps
	# back to before the anchor appeared rather than through every frame of the drag.
	_document.begin_edit("shape road")
	var existing := MapEditorStrokeEdit.point_at(stroke, world, MapEditorStrokeEdit.HIT_MIN)
	var index := existing
	if index < 0:
		index = MapEditorStrokeEdit.insert_anchor(stroke,
			MapEditorStrokeEdit.anchor_slot(stroke, world))
	if index < 0:
		_set_status("Could not place an anchor there.")
		return
	_anchor_grab = {"stroke": stroke, "index": index}
	_set_status("Drag to curve both segments%s." % ("" if existing < 0 else " (existing point)"))


## UPGRADE. One click steps the road under the cursor up a class; Shift-click steps it back.
func _upgrade_press(world: Vector2, up: bool) -> void:
	var found := MapEditorStrokeEdit.stroke_at(_document.data(), world)
	if found.is_empty():
		_set_status("No road under the cursor.")
		return
	var stroke: Dictionary = found["stroke"]
	var was := str(stroke.get("class", "mid"))
	_document.begin_edit("change road class")
	var now := MapEditorStrokeEdit.step_class(stroke, up)
	if now == "":
		_set_status("Already %s — %s." % [was, "the widest class" if up else "the narrowest class"])
		return
	# The stroke's drawn geometry is unchanged, but its width is not, so the runtime cache
	# keyed by id would otherwise keep the old look.
	_set_status("%s → %s" % [was, now])


## SELECT. Close the marquee and record what it caught.
func _finish_marquee(world: Vector2) -> void:
	if _marquee_from == Vector2.INF:
		return
	_marquee_to = world
	var rect := Rect2(_marquee_from, Vector2.ZERO).expand(_marquee_to)
	var dragged := rect.size.length() * (_camera.zoom.x if _camera != null else 1.0)
	_marquee_from = Vector2.INF
	_marquee_to = Vector2.INF
	if dragged < MapEditorSelection.MIN_DRAG:
		# A click, not a box: clear rather than select nothing, so clicking empty ground is
		# the natural way to drop a selection.
		_selection = []
		_set_status("Selection cleared.")
		_overlay.queue_redraw()
		return
	_selection = MapEditorSelection.in_rect(_document.data(), rect)
	_set_status("%d selected — Delete to remove." % _selection.size() if not _selection.is_empty()
		else "Nothing in the box.")
	_overlay.queue_redraw()


## Ask before removing. Deletion is the one action here that destroys authored work, and the
## marquee makes it easy to catch more than intended.
func _ask_delete() -> void:
	if _selection.is_empty():
		_set_status("Nothing selected.")
		return
	_confirm.ask("Delete %d selected item%s?" % [_selection.size(),
		"" if _selection.size() == 1 else "s"])
	_panel.refresh()


func _delete_selection() -> void:
	if _selection.is_empty():
		return
	_document.begin_edit("delete selection")
	var removed := MapEditorSelection.delete(_document.data(), _selection)
	_selection = []
	_overlay.queue_redraw()
	_set_status("Deleted %d item%s." % [removed, "" if removed == 1 else "s"])


## CONNECT THE DOTS. Dots live outside the document until two are joined; the join is what
## produces a stroke.
func _dot_press(world: Vector2) -> void:
	var link := _trace_tool.click_dot(world)
	if link.is_empty():
		var pending := _trace_tool.pending_dot()
		_set_status("Dot armed — click another to join." if pending >= 0
			else "Dot placed (%d)." % _trace_tool.dots().size())
		return
	_commit_points(link, "connect dots")


## FREEHAND. The traced path is simplified before it becomes a stroke — see the tool's
## header for why a recording of the gesture would be useless as an object.
func _finish_trace() -> void:
	var points := _trace_tool.end_trace()
	if points.is_empty():
		_set_status("Trace too short to keep.")
		return
	_commit_points(points, "trace road")


## Turn a bare point list into a stroke and put it in the document, with the same
## tile-touch, unlockable and bridge treatment a penned stroke gets. Shared so the three
## drawing tools cannot drift apart in what they record.
func _commit_points(points: Array, label: String) -> void:
	var terrain := get_tree().get_first_node_in_group("hex_map")
	var settlement := _ensure_settlement()
	var next_id := int(settlement.get("next_id", 1))
	var stroke := _road_tool.build_stroke(points, _settlement, next_id, terrain)
	if stroke.is_empty():
		_set_status("Stroke discarded — too short to keep.")
		return
	_document.begin_edit(label)
	settlement = _ensure_settlement()
	settlement["next_id"] = next_id + 1
	var roads: Array = settlement.get("roads", []) as Array
	roads.append(stroke)
	settlement["roads"] = roads
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


func trace_tool() -> MapEditorTraceTool:
	return _trace_tool


## The live marquee in world units, or an empty Rect2 when not dragging.
func marquee_rect() -> Rect2:
	if _marquee_from == Vector2.INF or _marquee_to == Vector2.INF:
		return Rect2()
	return Rect2(_marquee_from, Vector2.ZERO).expand(_marquee_to)


## Ids of the selected records, for the overlay's highlight.
func selected_ids() -> Dictionary:
	var out: Dictionary = {}
	for entry_value in _selection:
		out[str((entry_value as Dictionary).get("id", ""))] = true
	return out


func selection_size() -> int:
	return _selection.size()


# ── Public API (the tool panel and the keyboard share it) ───────────────────────
#
# Every control the panel offers routes through these, so a button and its shortcut cannot
# drift apart — they are the same call.

func current_tool() -> String:
	return _tool


func set_tool(value: String) -> void:
	if value == _tool:
		return
	# Leaving the pen mid-stroke would otherwise strand a half-drawn road that no longer has
	# a tool to finish it.
	if _road_tool.is_drawing():
		_road_tool.abandon()
	_trace_tool.cancel_trace()
	_anchor_grab = {}
	_marquee_from = Vector2.INF
	_marquee_to = Vector2.INF
	_overlay.queue_redraw()
	_tool = value
	_panning = false
	_refresh_status()


func current_road_class() -> String:
	return _road_tool.stroke_class()


func set_road_class(value: String) -> void:
	_road_tool.set_stroke_class(value)
	# Picking a class is a statement of intent to draw, so it selects the pen too.
	if _tool != TOOL_ROAD:
		set_tool(TOOL_ROAD)
	else:
		_refresh_status()


func grid_shown() -> bool:
	return _overlay != null and _overlay.show_grid


func toggle_grid() -> void:
	if _overlay != null:
		_overlay.show_grid = not _overlay.show_grid
		_overlay.queue_redraw()
	_refresh_status()


func run_action(action: String) -> void:
	match action:
		"save":
			_save()
		"reload":
			_reload()
		"leave":
			_leave()
		"delete":
			_ask_delete()
		"save_as":
			_ask_name()


# ── Document ────────────────────────────────────────────────────────────────────

## F5 saves under the document's current name, and asks for one the first time.
func _save() -> void:
	if _document.name_of() == "":
		_ask_name()
		return
	_save_as(_document.name_of())


func _ask_name() -> void:
	_name_dialog.open(_document.name_of())
	_panel.refresh()


## Write the document under `name` and point the game at it. Saving and activating are one
## step deliberately: a save that did not become the map you then look at would be a trap,
## and every other variant stays on disk to switch back to.
func _save_as(name: String) -> void:
	var directory := ProjectSettings.globalize_path(AuthoredMap.DOC_DIR)
	DirAccess.make_dir_recursive_absolute(directory)
	var absolute := "%s/%s.json" % [directory, name]
	var problem := _document.save_to(absolute)
	if problem != "":
		_set_status("SAVE FAILED — %s" % problem)
		_refresh_status()
		return
	var pointed := AuthoredMap.write_active(name, directory)
	_document.set_name(name)
	# Drop the game-side cache so anything reading it now sees what was just written.
	AuthoredMap.reset_for_tests()
	_set_status("Saved '%s'%s" % [name,
		"" if pointed == "" else "  (but the active pointer failed: %s)" % pointed])
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
